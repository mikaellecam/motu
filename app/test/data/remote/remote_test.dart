import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with [respond] and remembers the last one.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);

  ResponseBody Function(RequestOptions) respond;
  late RequestOptions last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(
  Object body, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
    ...headers,
  },
);

Decimal d(String s) => Decimal.parse(s);

void main() {
  late FakeAdapter adapter;
  late BackendApi api;

  setUp(() {
    adapter = FakeAdapter((_) => json({}));
    api = BackendApi('http://backend.test', adapter: adapter);
  });

  test('assets decode to the domain', () async {
    adapter.respond = (_) => json({
      'assets': [
        {
          'id': 'lvmh',
          'symbol': 'LVMUY',
          'name': 'LVMH',
          'type': 'stock',
          'exchange': 'otc',
          'currency': 'USD',
          'region': 'europe',
          'listingDate': '2000-01-03',
        },
      ],
    });
    final asset = (await api.assets()).single.toDomain();
    expect(adapter.last.uri.toString(), 'http://backend.test/v1/assets');
    expect(asset.type, AssetType.stock);
    expect(asset.exchange, Exchange.otc);
    expect(asset.currency, Currency.usd);
    expect(asset.listingDate, DateTime.utc(2000, 1, 3));
  });

  test('history sends days and keeps prices and adjustedAt exact', () async {
    adapter.respond = (_) => json({
      'assetId': 'world',
      'currency': 'USD',
      'adjustedAt': '2026-10-06T21:30:00Z',
      'bars': [
        {
          'date': '2026-10-06',
          'open': '160.00',
          'high': '161.00',
          'low': '159.50',
          'close': '160.71',
          'volume': 1200,
        },
      ],
    });
    final history = await api.history(
      'world',
      from: DateTime.utc(2026, 10, 6),
      to: DateTime.utc(2026, 10, 7),
    );
    expect(adapter.last.uri.path, '/v1/assets/world/history');
    expect(adapter.last.uri.queryParameters, {
      'from': '2026-10-06',
      'to': '2026-10-07',
    });
    expect(history.adjustedAt, DateTime.utc(2026, 10, 6, 21, 30));
    final bar = history.toDomain().single;
    expect(bar.date, DateTime.utc(2026, 10, 6));
    expect(bar.close, d('160.71'));
    expect(bar.currency, Currency.usd);
  });

  test('history without a refetch and without bounds', () async {
    adapter.respond = (_) => json({
      'assetId': 'world',
      'currency': 'USD',
      'adjustedAt': null,
      'bars': <Object>[],
    });
    final history = await api.history('world');
    expect(adapter.last.uri.queryParameters, isEmpty);
    expect(history.adjustedAt, isNull);
    expect(history.toDomain(), isEmpty);
  });

  test('quotes keep the instant of the price', () async {
    adapter.respond = (_) => json({
      'quotes': [
        {
          'assetId': 'apple',
          'price': '231.4',
          'currency': 'USD',
          'asOf': '2026-10-07T15:30:00.5-04:00',
          'marketOpen': true,
        },
      ],
    });
    final quote = (await api.quotes(['apple', 'nvidia'])).single;
    expect(adapter.last.uri.queryParameters['ids'], 'apple,nvidia');
    expect(quote.price, d('231.4'));
    expect(quote.asOf, DateTime.utc(2026, 10, 7, 19, 30, 0, 500));
    expect(quote.asOf.isUtc, isTrue);
    expect(quote.marketOpen, isTrue);
  });

  test('livret history becomes rates and euro ceilings', () async {
    adapter.respond = (_) => json({
      'rates': [
        {'validFrom': '2026-08-01', 'annualRate': '0.017'},
      ],
      'ceilings': [
        {'validFrom': '1999-08-01', 'amountCents': 1524490},
      ],
    });
    final livret = await api.livret();
    expect(livret.toRates().single.annualRate, d('0.017'));
    expect(livret.toRates().single.validFrom, DateTime.utc(2026, 8, 1));
    expect(
      livret.toCeilings().single.amount,
      const Money(1524490, Currency.eur),
    );
  });

  test('calendar asks for one exchange and year', () async {
    adapter.respond = (_) => json({
      'exchange': 'otc',
      'year': 2026,
      'holidays': ['2026-07-03'],
    });
    final calendar = await api.calendar(Exchange.otc, 2026);
    expect(adapter.last.uri.path, '/v1/calendar/otc');
    expect(adapter.last.uri.queryParameters, {'year': '2026'});
    expect(calendar.holidays, [DateTime.utc(2026, 7, 3)]);
    expect(calendar.earlyCloses, isEmpty, reason: 'a backend before M9-37');
  });

  test('calendar early closes come with their local closing time', () async {
    adapter.respond = (_) => json({
      'exchange': 'nyse',
      'year': 2005,
      'holidays': <String>[],
      'earlyCloses': [
        {'date': '2005-06-01', 'close': '15:56'},
        {'date': '2005-11-25', 'close': '13:00'},
      ],
    });
    final calendar = await api.calendar(Exchange.nyse, 2005);
    expect(
      [for (final e in calendar.earlyCloses) (e.date, e.close)],
      [
        (DateTime.utc(2005, 6, 1), (15, 56)),
        (DateTime.utc(2005, 11, 25), (13, 0)),
      ],
    );
  });

  test('Frankfurter rates come back exact and oldest first', () async {
    final fx = FakeAdapter(
      (_) => json({
        'amount': 1.0,
        'base': 'USD',
        'start_date': '2026-10-01',
        'end_date': '2026-10-07',
        'rates': {
          '2026-10-07': {'EUR': 0.85251},
          '2026-10-01': {'EUR': 0.8513},
          '2026-10-02': <String, Object>{},
          '2026-10-06': {'EUR': 1},
        },
      }),
    );
    final rates = await FrankfurterApi(adapter: fx).rates(
      Currency.usd,
      Currency.eur,
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 10, 7),
    );
    expect(
      fx.last.uri.toString(),
      'https://api.frankfurter.dev/v1/2026-10-01..2026-10-07?base=USD&symbols=EUR',
    );
    expect([for (final r in rates) r.date.day], [1, 6, 7]);
    expect(
      [for (final r in rates) r.rate],
      [d('0.8513'), d('1'), d('0.85251')],
    );
  });

  group('failures are typed', () {
    Future<Failure> failureOf(
      ResponseBody Function(RequestOptions) respond,
    ) async {
      adapter.respond = respond;
      try {
        await api.livret();
      } on Failure catch (f) {
        return f;
      }
      fail('no failure');
    }

    ResponseBody error(
      int status, [
      Map<String, List<String>> headers = const {},
    ]) => json(
      {
        'error': {'code': 'x', 'message': 'y'},
      },
      status: status,
      headers: headers,
    );

    test('429 carries Retry-After, 60 s without it', () async {
      final limited = await failureOf(
        (_) => error(429, {
          'retry-after': ['17'],
        }),
      );
      expect(
        (limited as RateLimitedFailure).retryAfter,
        const Duration(seconds: 17),
      );
      final bare = await failureOf((_) => error(429));
      expect(
        (bare as RateLimitedFailure).retryAfter,
        const Duration(seconds: 60),
      );
    });

    test('404 is not found', () async {
      expect(await failureOf((_) => error(404)), isA<NotFoundFailure>());
    });

    test(
      'unreachable, timed out or a proxy without its server is network',
      () async {
        expect(
          await failureOf((_) => throw const SocketException('down')),
          isA<NetworkFailure>(),
        );
        expect(
          await failureOf(
            (o) => throw DioException.receiveTimeout(
              timeout: const Duration(seconds: 30),
              requestOptions: o,
            ),
          ),
          isA<NetworkFailure>(),
        );
        for (final status in [502, 503, 504]) {
          expect(await failureOf((_) => error(status)), isA<NetworkFailure>());
        }
      },
    );

    test('other errors and unreadable bodies are the server', () async {
      for (final status in [400, 500]) {
        expect(await failureOf((_) => error(status)), isA<ServerFailure>());
      }
      // A price as a JSON number would have gone through a double.
      expect(
        await failureOf(
          (_) => json({
            'rates': [
              {'validFrom': '2026-08-01', 'annualRate': 0.017},
            ],
            'ceilings': <Object>[],
          }),
        ),
        isA<ServerFailure>(),
      );
      expect(
        await failureOf(
          (_) => json({
            'rates': [
              {'validFrom': 'août', 'annualRate': '0.017'},
            ],
            'ceilings': <Object>[],
          }),
        ),
        isA<ServerFailure>(),
      );
    });

    test('a closing time that is not HH:mm is the server', () async {
      for (final close in ['1pm', '13', '24:00', '13:60', '9:30']) {
        adapter.respond = (_) => json({
          'exchange': 'nyse',
          'year': 2026,
          'holidays': <String>[],
          'earlyCloses': [
            {'date': '2026-11-27', 'close': close},
          ],
        });
        await expectLater(
          api.calendar(Exchange.nyse, 2026),
          throwsA(isA<ServerFailure>()),
          reason: close,
        );
      }
    });

    test('an unknown currency is the server', () async {
      adapter.respond = (_) => json({
        'quotes': [
          {
            'assetId': 'x',
            'price': '1',
            'currency': 'GBP',
            'asOf': '2026-10-07T20:00:00Z',
            'marketOpen': false,
          },
        ],
      });
      await expectLater(api.quotes(['x']), throwsA(isA<ServerFailure>()));
    });
  });
}
