import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/core/clock/simulation_clock.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

class WallClock implements SimulationClock {
  WallClock(this.t);
  DateTime t;
  @override
  DateTime now() => t;
  void advance(Duration d) => t = t.add(d);
}

/// The backend's endpoints over in-memory data; records every request.
class FakeBackend implements HttpClientAdapter {
  final requests = <Uri>[];
  bool offline = false;

  final assets = <Map<String, Object>>[
    _asset('apple', 'nasdaq', '1980-12-12'),
    _asset('meta', 'nasdaq', '2012-05-18'),
  ];

  /// Closes by asset and day.
  final closes = <String, Map<String, String>>{
    'apple': {'2026-10-05': '100', '2026-10-06': '101', '2026-10-07': '102'},
  };
  final adjustedAt = <String, String?>{};
  final quotes = <String, Map<String, Object>>{};
  final holidays = <int, List<String>>{
    2025: ['2025-12-25'],
    2026: ['2026-07-03', '2026-11-26', '2026-12-25'],
    2027: ['2027-01-01'],
  };

  static Map<String, Object> _asset(String id, String exchange, String since) =>
      {
        'id': id,
        'symbol': id.toUpperCase(),
        'name': id,
        'type': 'stock',
        'exchange': exchange,
        'currency': 'USD',
        'region': 'us',
        'listingDate': since,
      };

  /// Requests whose path starts with [prefix].
  List<Uri> to(String prefix) => [
    for (final r in requests)
      if (r.path.startsWith(prefix)) r,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    requests.add(uri);
    if (offline) throw const SocketException('offline');
    final q = uri.queryParameters;
    final segments = uri.pathSegments;
    final Object body;
    switch (segments) {
      case ['v1', 'assets']:
        body = {'assets': assets};
      case ['v1', 'assets', final id, 'history']:
        final days = (closes[id] ?? {}).keys.toList()..sort();
        body = {
          'assetId': id,
          'currency': 'USD',
          'adjustedAt': adjustedAt[id],
          'bars': [
            for (final day in days)
              if ((q['from'] == null || day.compareTo(q['from']!) >= 0) &&
                  (q['to'] == null || day.compareTo(q['to']!) <= 0))
                {
                  'date': day,
                  'open': closes[id]![day],
                  'high': closes[id]![day],
                  'low': closes[id]![day],
                  'close': closes[id]![day],
                  'volume': 1,
                },
          ],
        };
      case ['v1', 'quotes']:
        body = {
          'quotes': [
            for (final id in q['ids']!.split(','))
              if (quotes[id] != null) quotes[id]!,
          ],
        };
      case ['v1', 'calendar', final exchange]:
        final year = int.parse(q['year']!);
        final days = holidays[year];
        if (days == null) {
          return _json({
            'error': {'code': 'not_found', 'message': 'no calendar'},
          }, 404);
        }
        body = {'exchange': exchange, 'year': year, 'holidays': days};
      default:
        return _json({}, 404);
    }
    return _json(body, 200);
  }

  static ResponseBody _json(Object body, int status) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

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
}
