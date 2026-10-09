import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/core/clock/simulation_clock.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_frankfurter.dart';
import '../../fakes/fake_backend.dart' show WallClock;

DateTime day(int m, int d) => DateTime.utc(2026, m, d);
Decimal dec(String s) => Decimal.parse(s);

void main() {
  late AppDatabase db;
  late FakeFrankfurter api;
  late WallClock wall;
  late FxService fx;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeFrankfurter();
    // Thursday 2026-10-08, 10:00 UTC: today's rate is not published yet.
    wall = WallClock(DateTime.utc(2026, 10, 8, 10));
    fx = FxService(db, FrankfurterApi(adapter: api), wallClock: wall);
  });
  tearDown(() => db.close());

  Future<Decimal> usdEur(DateTime asOf) =>
      fx.rate(Currency.usd, Currency.eur, asOf: asOf);

  test('the same currency is 1, without the network', () async {
    expect(
      await fx.rate(Currency.eur, Currency.eur, asOf: wall.now()),
      Decimal.one,
    );
    expect(api.requests, isEmpty);
  });

  test('the first need caches the whole history in one request', () async {
    expect(await usdEur(day(10, 5)), dec('0.85251'));
    expect(api.requests.single.path, '/v1/2000-01-03..2026-10-08');
    expect(api.requests.single.queryParameters, {
      'base': 'USD',
      'symbols': 'EUR',
    });
  });

  test('a cached date never calls the network, a trip date included', () async {
    await usdEur(day(10, 7));
    expect(await usdEur(day(10, 6)), dec('0.85'));
    expect(await usdEur(DateTime.utc(2008, 9, 15)), dec('0.70582'));
    expect(await usdEur(DateTime.utc(2000, 1, 3)), dec('0.9847'));
    expect(api.requests, hasLength(1));

    // Days later, after a restart: still from the cache.
    wall.t = DateTime.utc(2026, 10, 12, 18);
    final restarted = FxService(
      db,
      FrankfurterApi(adapter: api),
      wallClock: wall,
    );
    expect(
      await restarted.rate(Currency.usd, Currency.eur, asOf: day(10, 4)),
      dec('0.85125'),
    );
    expect(api.requests, hasLength(1));
  });

  test('a day without a rate takes the previous one', () async {
    await usdEur(day(10, 7));
    // Weekend: Friday's rate.
    expect(await usdEur(day(10, 3)), dec('0.85125'));
    expect(await usdEur(day(10, 4)), dec('0.85125'));
    // Long gaps too: the last rate before them.
    expect(await usdEur(DateTime.utc(2008, 12, 25)), dec('0.70582'));
    expect(api.requests, hasLength(1));
  });

  test('never a rate dated after asOf', () async {
    await usdEur(day(10, 7));
    // A trip at 2026-10-05 00:00 (HistoricalClock) sees that day's fixing.
    expect(await usdEur(HistoricalClock(day(10, 5)).now()), dec('0.85251'));
    expect(await usdEur(day(10, 4)), dec('0.85125'));
  });

  test(
    'today before the fixing: the last rate, checked again after 15 min',
    () async {
      expect(await usdEur(wall.now()), dec('0.8547'));
      wall.t = wall.t.add(const Duration(minutes: 14));
      expect(await usdEur(wall.now()), dec('0.8547'));
      expect(
        api.requests,
        hasLength(1),
        reason: 'the first fetch ran to today',
      );

      wall.t = wall.t.add(const Duration(minutes: 1));
      expect(await usdEur(wall.now()), dec('0.8547'));
      expect(api.requests, hasLength(2));
      expect(api.requests.last.path, '/v1/2026-10-08..2026-10-08');

      api.published['2026-10-08'] = 0.85633;
      wall.t = DateTime.utc(2026, 10, 8, 16);
      expect(await usdEur(wall.now()), dec('0.85633'));
      expect(api.requests, hasLength(3));
      wall.t = DateTime.utc(2026, 10, 8, 23);
      expect(await usdEur(wall.now()), dec('0.85633'));
      expect(api.requests, hasLength(3), reason: 'today is cached now');
    },
  );

  test('offline: the last cached rate, else the failure', () async {
    api.offline = true;
    await expectLater(usdEur(day(10, 7)), throwsA(isA<NetworkFailure>()));

    api.offline = false;
    await usdEur(day(10, 7));
    api.offline = true;
    wall.t = DateTime.utc(2026, 10, 12, 18);
    expect(await usdEur(wall.now()), dec('0.8547'));
  });

  test('before the first published rate there is none', () async {
    await expectLater(
      usdEur(DateTime.utc(1999, 6, 1)),
      throwsA(isA<DataUnavailableFailure>()),
    );
  });

  test('lookup: many days from one read, cut at asOf', () async {
    final rate = await fx.lookup(
      Currency.usd,
      Currency.eur,
      start: day(10, 3),
      asOf: day(10, 6),
    );
    expect(api.requests, hasLength(1));
    // Saturday 10-03 takes Friday's rate, read before the range.
    expect(rate(day(10, 3)), dec('0.85125'));
    expect(rate(day(10, 5)), dec('0.85251'));
    expect(rate(day(10, 6)), dec('0.85'));
    expect(() => rate(day(10, 7)), throwsArgumentError);

    final early = await fx.lookup(
      Currency.usd,
      Currency.eur,
      start: DateTime.utc(1999, 6, 1),
      asOf: DateTime.utc(2000, 1, 3),
    );
    expect(early(DateTime.utc(2000, 1, 3)), dec('0.9847'));
    expect(
      () => early(DateTime.utc(1999, 12, 31)),
      throwsA(isA<DataUnavailableFailure>()),
    );

    final same = await fx.lookup(
      Currency.eur,
      Currency.eur,
      start: day(1, 1),
      asOf: day(10, 6),
    );
    expect(same(day(5, 5)), Decimal.one);
  });
}
