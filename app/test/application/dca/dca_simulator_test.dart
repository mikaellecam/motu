import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/dca/dca_simulator.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/dca_simulator.dart';
import 'package:finance_companion/domain/wallet/trip_start.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/fake_frankfurter.dart';

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);
Money eur(String s) => Money.book(Decimal.parse(s), Currency.eur);

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  final now = DateTime.utc(2026, 10, 8, 12);

  // Apple: 100 $ to the end of 2025, 70 $ for the first quarter of 2026,
  // 110 $ since; a close every weekday from September 2025.
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final wall = WallClock(now);
    final backend = FakeBackend();
    final closes = <String, String>{};
    for (var d = day(2025, 9, 1); d.isBefore(day(2026, 10, 8));) {
      if (d.weekday <= 5) {
        closes[d.toIso8601String().substring(0, 10)] = d.year == 2025
            ? '100'
            : d.month <= 3
            ? '70'
            : '110';
      }
      d = DateTime.utc(d.year, d.month, d.day + 1);
    }
    backend.closes['apple'] = closes;
    backend.assets.add({
      ...backend.assets.first,
      'id': 'world',
      'name': 'ETF Monde',
      'type': 'etf',
      'listingDate': '2008-03-28',
    });
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(wall),
        marketRepositoryProvider.overrideWithValue(
          MarketRepository(
            db,
            BackendApi('http://t', adapter: backend),
            wallClock: wall,
          ),
        ),
        fxServiceProvider.overrideWithValue(
          FxService(
            db,
            FrankfurterApi(adapter: FakeFrankfurter()),
            wallClock: wall,
          ),
        ),
      ],
    );
    await c.read(walletRepositoryProvider).ensureLiveWallet(now);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<DcaResult> run(DcaParams p) {
    c.listen(dcaRunProvider(p), (_, _) {});
    return c.read(dcaRunProvider(p).future);
  }

  Future<DcaFormView> view() {
    c.listen(dcaFormViewProvider, (_, _) {});
    return c.read(dcaFormViewProvider.future);
  }

  DcaFormController form() => c.read(dcaFormControllerProvider.notifier);

  final monthly = DcaParams(
    assetId: 'apple',
    amount: eur('100'),
    frequency: DcaFrequency.monthly,
    start: day(2025, 10, 8),
  );

  test('a year of monthly buys, against the lump sum and the Livret', () async {
    final r = await run(monthly);
    // 8 October 2025 to 8 September 2026: the October 2026 date is past
    // the last close.
    expect(r.dca.purchases, hasLength(12));
    expect(r.dca.invested, eur('1200'));
    expect(r.end, day(2026, 10, 7));
    // The same total, in once on the first day.
    expect(r.lumpSum.invested, r.dca.invested);
    expect(r.lumpSum.purchases.single.date, day(2025, 10, 8));
    // Fees as in the sandbox: 0,15 % on a dollar asset.
    expect(r.dca.purchases.first.fees.isPositive, isTrue);
    // The Livret got the same deposits and earned.
    expect(r.livret.invested, eur('1200'));
    expect(r.livret.finalValue, greaterThan(Decimal.fromInt(1200)));
    // 2026's buys: 3 at 70 $ and 6 at 110 $, about 92 $ a share on average,
    // 16 % under the last close.
    expect(r.insight, isA<DcaCheapYear>());
    expect((r.insight! as DcaCheapYear).year, 2026);
  });

  group('the form', () {
    test(
      'valid by default: 100 € a month, from the profile\'s horizon',
      () async {
        form().setAsset('apple');
        final v = await view();
        // No profile: a 10-year horizon, the « 10 ans » preset.
        expect(v.years, 10);
        expect(v.start, isA<StartOk>());
        expect(v.amountErrors, isEmpty);
        expect(v.params!.amount, eur('100'));
        expect(v.params!.frequency, DcaFrequency.monthly);
      },
    );

    test('the amount: above zero, at most 100 000 €', () async {
      form().setAmount('0');
      expect(
        [for (final e in (await view()).amountErrors) e.code],
        ['amount_not_positive'],
      );
      form().setAmount('200 000');
      final v = await view();
      expect([for (final e in v.amountErrors) e.code], ['amount_too_large']);
      expect(v.params, isNull);
    });

    test(
      'the start: a real day, after the asset\'s first close, a month back',
      () async {
        form()
          ..setAsset('world')
          ..setDate('31/02/2026');
        expect((await view()).start, isA<StartUnreadable>());
        form().setDate('01/01/2005');
        // The world ETF trades since 28 March 2008.
        expect(
          ((await view()).start as StartBeforeFloor).floor,
          day(2008, 3, 28),
        );
        form().setDate('01/10/2026');
        expect((await view()).start, isA<StartTooRecent>());
        form().setDate('04/10/2025');
        // A Saturday: the next session.
        final v = await view();
        expect((v.start as StartOk).date, day(2025, 10, 6));
        expect(v.params!.start, day(2025, 10, 6));
        expect(v.years, isNull);
      },
    );
  });

  test('saved, listed newest first, and back in the form', () async {
    final r = await run(monthly);
    await form().save(r);
    final saved = await c.read(savedDcaProvider.future);
    expect(saved.single.params, monthly);
    expect(saved.single.summary.invested, eur('1200'));
    expect(saved.single.summary.finalValue, r.dca.finalValue);

    form().load(saved.single.params);
    final f = c.read(dcaFormControllerProvider);
    expect(
      (f.assetId, f.amount, f.date, f.run),
      ('apple', '100', '08/10/2025', monthly),
    );
  });
}
