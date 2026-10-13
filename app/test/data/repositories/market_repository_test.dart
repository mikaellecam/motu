import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/clock/simulation_clock.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';

DateTime day(int m, int d) => DateTime.utc(2026, m, d);
Decimal dec(String s) => Decimal.parse(s);

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late WallClock wall;
  late MarketRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend();
    // Thursday 2026-10-08, 08:00 in New York: before the open.
    wall = WallClock(DateTime.utc(2026, 10, 8, 12));
    repo = MarketRepository(
      db,
      BackendApi('http://backend.test', adapter: backend),
      wallClock: wall,
    );
  });
  tearDown(() => db.close());

  Future<List<String>> closes({
    DateTime? from,
    DateTime? to,
    DateTime? asOf,
  }) async => [
    for (final bar in await repo.history(
      'apple',
      from: from ?? day(10, 1),
      to: to ?? day(10, 31),
      asOf: asOf ?? wall.now(),
    ))
      '${bar.date.day}:${bar.close}',
  ];

  group('history', () {
    test(
      'first fetch takes the whole history; then it reads the cache',
      () async {
        expect(await closes(), ['5:100', '6:101', '7:102']);
        final fetches = backend.to('/v1/assets/apple/history');
        expect(fetches.single.queryParameters, isEmpty);

        final bars = await repo.history(
          'apple',
          from: day(10, 6),
          to: day(10, 6),
          asOf: wall.now(),
        );
        expect(bars.single.date, day(10, 6));
        expect(bars.single.date.isUtc, isTrue);
        expect(bars.single.close, dec('101'));
        expect(backend.to('/v1/assets/apple/history'), hasLength(1));
      },
    );

    test('later fetches start the day after the last cached one', () async {
      await closes();
      backend.closes['apple']!['2026-10-08'] = '103';
      wall.t = DateTime.utc(2026, 10, 8, 22); // after the backend's sync

      expect(await closes(), ['5:100', '6:101', '7:102', '8:103']);
      final fetches = backend.to('/v1/assets/apple/history');
      expect(fetches, hasLength(2));
      expect(fetches.last.queryParameters, {'from': '2026-10-08'});
    });

    test('a fresh fetch is not repeated before the recheck delay', () async {
      await closes();
      wall.advance(const Duration(minutes: 14));
      await closes();
      expect(backend.to('/v1/assets/apple/history'), hasLength(1));

      wall.advance(const Duration(minutes: 1));
      await closes();
      // Nothing new yet (a holiday, or the backend has not synced): the
      // empty answer still counts as a check.
      await closes();
      expect(backend.to('/v1/assets/apple/history'), hasLength(2));
    });

    test('a re-adjusted history replaces the cached one', () async {
      await closes();
      backend.adjustedAt['apple'] = '2026-10-08T21:05:00Z';
      backend.closes['apple'] = {
        '2026-10-05': '50',
        '2026-10-06': '50.5',
        '2026-10-07': '51',
        '2026-10-08': '51.5',
      };
      wall.t = DateTime.utc(2026, 10, 8, 22);

      expect(await closes(), ['5:50', '6:50.5', '7:51', '8:51.5']);
      final fetches = backend.to('/v1/assets/apple/history');
      expect(
        [for (final f in fetches) f.queryParameters],
        [
          {},
          {'from': '2026-10-08'},
          {},
        ],
      );

      backend.closes['apple']!['2026-10-09'] = '52';
      wall.t = DateTime.utc(2026, 10, 9, 22);
      expect((await closes()).last, '9:52');
      expect(backend.to('/v1/assets/apple/history').last.queryParameters, {
        'from': '2026-10-09',
      }, reason: 'same adjustedAt: no refetch');
    });

    test('nothing after asOf is returned or fetched for', () async {
      // A trip on 2026-10-06 (HistoricalClock: the day after its close).
      final tripDay = HistoricalClock(day(10, 6)).now();
      expect(await closes(asOf: tripDay), ['5:100', '6:101']);

      backend.closes['apple']!['2026-10-08'] = '103';
      wall.advance(const Duration(days: 1));
      expect(await closes(asOf: tripDay), ['5:100', '6:101']);
      expect(
        await closes(from: day(10, 7), asOf: tripDay),
        isEmpty,
        reason: 'the whole range is after asOf',
      );
      expect(backend.to('/v1/assets/apple/history'), hasLength(1));
    });

    test('offline: the cache, else the failure', () async {
      backend.offline = true;
      await expectLater(closes(), throwsA(isA<NetworkFailure>()));

      backend.offline = false;
      await closes();
      backend.offline = true;
      wall.advance(const Duration(days: 2));
      expect(await closes(), ['5:100', '6:101', '7:102']);
    });

    test(
      'an unknown asset is not found, after one catalogue refresh',
      () async {
        await closes();
        await expectLater(
          repo.history(
            'nope',
            from: day(10, 1),
            to: day(10, 7),
            asOf: wall.now(),
          ),
          throwsA(isA<NotFoundFailure>()),
        );
        expect(backend.to('/v1/assets/nope'), isEmpty);
        expect(
          backend.requests.where((r) => r.path == '/v1/assets'),
          hasLength(2),
        );
      },
    );
  });

  group('quotes', () {
    Map<String, Object> quote(
      String price,
      DateTime asOf, {
      bool open = true,
    }) => {
      'assetId': 'apple',
      'price': price,
      'currency': 'USD',
      'asOf': asOf.toIso8601String(),
      'marketOpen': open,
    };

    test('last 15 minutes while the market is open', () async {
      wall.t = DateTime.utc(2026, 10, 7, 15); // 11:00 in New York
      backend.quotes['apple'] = quote(
        '231.4',
        DateTime.utc(2026, 10, 7, 14, 55),
      );
      final first = await repo.latest('apple', asOf: wall.now());
      expect(first!.price.value, dec('231.4'));
      expect(first.marketOpen, isTrue);

      backend.quotes['apple'] = quote('232', DateTime.utc(2026, 10, 7, 15, 25));
      wall.advance(const Duration(minutes: 14));
      expect(
        (await repo.latest('apple', asOf: wall.now()))!.price.value,
        dec('231.4'),
      );
      wall.advance(const Duration(minutes: 2));
      expect(
        (await repo.latest('apple', asOf: wall.now()))!.price.value,
        dec('232'),
      );
      expect(backend.to('/v1/quotes'), hasLength(2));
    });

    test('last until the next open when closed, holidays included', () async {
      // Thanksgiving: closed all day. The next open is Friday 09:30 in New
      // York, 14:30 UTC (standard time).
      wall.t = DateTime.utc(2026, 11, 26, 15);
      backend.quotes['apple'] = quote(
        '240',
        DateTime.utc(2026, 11, 25, 21),
        open: false,
      );
      await repo.latest('apple', asOf: wall.now());

      wall.t = DateTime.utc(2026, 11, 27, 14, 29);
      await repo.latest('apple', asOf: wall.now());
      expect(backend.to('/v1/quotes'), hasLength(1));

      wall.t = DateTime.utc(2026, 11, 27, 14, 31);
      await repo.latest('apple', asOf: wall.now());
      expect(backend.to('/v1/quotes'), hasLength(2));
    });

    test('a price observed after asOf is withheld', () async {
      backend.quotes['apple'] = quote(
        '231.4',
        DateTime.utc(2026, 10, 7, 20),
        open: false,
      );
      expect(await repo.latest('apple', asOf: day(10, 6)), isNull);
      expect(await repo.latest('apple', asOf: day(10, 7)), isNotNull);
    });

    test('offline: the cached quote, else the failure', () async {
      backend.quotes['apple'] = quote(
        '231.4',
        DateTime.utc(2026, 10, 7, 20),
        open: false,
      );
      await repo.assets(asOf: wall.now());
      backend.offline = true;
      await expectLater(
        repo.latest('apple', asOf: wall.now()),
        throwsA(isA<NetworkFailure>()),
      );

      backend.offline = false;
      await repo.latest('apple', asOf: wall.now());
      backend.offline = true;
      wall.advance(const Duration(days: 3));
      expect(
        (await repo.latest('apple', asOf: wall.now()))!.price.value,
        dec('231.4'),
      );
    });

    test('no price at all is null', () async {
      expect(await repo.latest('meta', asOf: wall.now()), isNull);
    });

    test('many assets: the expired ones in one request', () async {
      final closed = DateTime.utc(2026, 10, 7, 20);
      backend.quotes['apple'] = quote('231.4', closed, open: false);
      backend.quotes['meta'] = {
        ...quote('600', closed, open: false),
        'assetId': 'meta',
      };
      final both = await repo.latestAll(['apple', 'meta'], asOf: wall.now());
      expect(
        {for (final e in both.entries) e.key: e.value.price.value},
        {'apple': dec('231.4'), 'meta': dec('600')},
      );
      final requests = backend.to('/v1/quotes');
      expect(requests, hasLength(1));
      expect(
        requests.single.queryParameters['ids']!.split(','),
        unorderedEquals(['apple', 'meta']),
      );

      // Both still fresh (closed market): no request at all.
      await repo.latestAll(['apple', 'meta'], asOf: wall.now());
      expect(backend.to('/v1/quotes'), hasLength(1));
    });

    test('many assets offline: what is cached, else the failure', () async {
      backend.quotes['apple'] = quote(
        '231.4',
        DateTime.utc(2026, 10, 7, 20),
        open: false,
      );
      await repo.latestAll(['apple'], asOf: wall.now());
      backend.offline = true;
      wall.advance(const Duration(days: 2));
      final partial = await repo.latestAll(['apple', 'meta'], asOf: wall.now());
      expect(partial.keys, ['apple']);
      await expectLater(
        repo.latestAll(['meta'], asOf: wall.now()),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  test(
    'assets listed after asOf are hidden; the catalogue is checked daily',
    () async {
      expect(
        [for (final a in await repo.assets(asOf: DateTime.utc(2010))) a.id],
        ['apple'],
      );
      expect(
        [for (final a in await repo.assets(asOf: wall.now())) a.id],
        ['apple', 'meta'],
      );
      expect(backend.requests, hasLength(1));
      wall.advance(const Duration(days: 1));
      await repo.assets(asOf: wall.now());
      expect(backend.requests, hasLength(2));
    },
  );

  test('calendar: past years once, the current one daily, unserved years weekends only', () async {
    Future<MarketCalendar> load(int from, int to) =>
        repo.calendar({Exchange.nyse}, fromYear: from, toYear: to);

    final markets = await load(2025, 2026);
    expect(
      markets.isTradingDay(Exchange.nyse, DateTime.utc(2025, 12, 25)),
      isFalse,
    );
    expect(markets.isTradingDay(Exchange.nyse, day(11, 26)), isFalse);
    expect(markets.isTradingDay(Exchange.nyse, day(11, 27)), isTrue);
    expect(backend.to('/v1/calendar'), hasLength(2));

    await load(2025, 2026);
    expect(backend.to('/v1/calendar'), hasLength(2));

    wall.advance(const Duration(days: 1));
    await load(2025, 2026);
    expect(
      [for (final r in backend.to('/v1/calendar')) r.queryParameters['year']],
      ['2025', '2026', '2026'],
    );

    final old = await load(1999, 1999);
    expect(old.isTradingDay(Exchange.nyse, DateTime.utc(1999, 12, 24)), isTrue);
  });

  test('Livret history: cut at asOf, checked daily, cached offline', () async {
    final now = await repo.livret(asOf: wall.now());
    expect(
      [for (final r in now.rates) r.annualRate],
      [dec('0.017'), dec('0.015'), dec('0.017')],
    );
    expect(now.ceilings.single.amount.minorUnits, 2295000);

    final trip = await repo.livret(asOf: day(3, 1));
    expect(trip.rates.last.validFrom, day(2, 1));
    expect(backend.to('/v1/livret'), hasLength(1));

    backend.offline = true;
    wall.advance(const Duration(days: 1));
    expect((await repo.livret(asOf: wall.now())).rates, hasLength(3));
    expect(backend.to('/v1/livret'), hasLength(2));
  });

  group('status', () {
    late StreamController<bool> online;
    late List<CacheStatus> seen;
    final firstFetch = DateTime.utc(2026, 10, 8, 12);

    MarketRepository start() {
      final repository = MarketRepository(
        db,
        BackendApi('http://backend.test', adapter: backend),
        wallClock: wall,
        online: online.stream,
      );
      addTearDown(repository.dispose);
      seen = [];
      repository.status().listen(seen.add);
      return repository;
    }

    setUp(() {
      online = StreamController<bool>();
      repo = start();
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test(
      'fresh, stale after a failed refresh, offline without a connection',
      () async {
        await closes();
        await settle();
        expect(seen, [const Fresh()]);

        // The server cannot be reached; the device is still connected.
        backend.offline = true;
        wall.t = DateTime.utc(2026, 10, 9, 22);
        expect(await closes(), hasLength(3));
        await settle();
        expect(seen.last, Stale(firstFetch));

        online.add(false);
        await settle();
        expect(seen.last, Offline(firstFetch));
        online.add(true);
        await settle();
        expect(seen.last, Stale(firstFetch), reason: 'nothing refetched yet');

        backend.offline = false;
        await closes();
        await settle();
        expect(seen, [
          const Fresh(),
          Stale(firstFetch),
          Offline(firstFetch),
          Stale(firstFetch),
          const Fresh(),
        ]);
      },
    );

    test('a failed quote refresh is stale as of the cached quote', () async {
      backend.quotes['apple'] = {
        'assetId': 'apple',
        'price': '231.4',
        'currency': 'USD',
        'asOf': '2026-10-07T20:00:00Z',
        'marketOpen': false,
      };
      await repo.latest('apple', asOf: wall.now());
      backend.offline = true;
      wall.t = DateTime.utc(2026, 10, 12, 15);
      await repo.latest('apple', asOf: wall.now());
      await settle();
      expect(seen.last, Stale(firstFetch));
    });

    test('after a restart offline: when prices were last fetched', () async {
      await closes();
      wall.t = DateTime.utc(2026, 10, 10, 9);
      online = StreamController<bool>()..add(false);
      start();
      await settle();
      expect(seen.last, Offline(firstFetch));
    });

    test('offline before any fetch: no date to show', () async {
      online.add(false);
      await settle();
      expect(seen.last, const Offline(null));
    });
  });

  group('the cache, for Settings', () {
    test('what it holds, when prices last came, and its size', () async {
      final empty = await repo.cacheInfo();
      expect((empty.histories, empty.closes, empty.lastFetch), (0, 0, null));
      expect(empty.bytes, greaterThan(0));

      await closes();
      final info = await repo.cacheInfo();
      expect((info.histories, info.closes), (1, 3));
      expect(info.lastFetch, wall.now());
    });

    // Closed until Thursday's open: without « Actualiser maintenant », the
    // quote would last until then.
    void appleQuote() => backend.quotes['apple'] = {
      'assetId': 'apple',
      'price': '231.4',
      'currency': 'USD',
      'asOf': '2026-10-07T20:00:00Z',
      'marketOpen': false,
    };

    test('« Actualiser maintenant »: the next reads fetch histories and quotes '
        'again', () async {
      appleQuote();
      await closes();
      await repo.latest('apple', asOf: wall.now());
      wall.advance(const Duration(minutes: 1));
      await repo.refreshNow();
      await closes();
      await repo.latest('apple', asOf: wall.now());
      expect(backend.to('/v1/assets/apple/history'), hasLength(2));
      expect(backend.to('/v1/quotes'), hasLength(2));
    });

    test('« Actualiser maintenant » keeps when prices last came', () async {
      appleQuote();
      await closes();
      await repo.latest('apple', asOf: wall.now());
      final before = (await repo.cacheInfo()).lastFetch;
      wall.advance(const Duration(minutes: 5));
      await repo.refreshNow();
      expect((await repo.cacheInfo()).lastFetch, before);
    });

    test('« Actualiser maintenant », then offline: the cached quote stands '
        'in', () async {
      appleQuote();
      await repo.latest('apple', asOf: wall.now());
      wall.advance(const Duration(minutes: 1));
      await repo.refreshNow();
      backend.offline = true;
      final quote = await repo.latest('apple', asOf: wall.now());
      expect(quote!.price.value, dec('231.4'));
      expect(backend.to('/v1/quotes'), hasLength(2), reason: 'it was due');
    });

    test('« Vider le cache »: the prices go, then come back', () async {
      await closes();
      await repo.clearCache();
      expect((await repo.cacheInfo()).closes, 0);
      expect(await closes(), ['5:100', '6:101', '7:102']);
    });
  });
}
