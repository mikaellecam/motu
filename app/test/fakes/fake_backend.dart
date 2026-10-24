import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:finance_companion/core/clock/simulation_clock.dart';

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

  /// Content packs served, by island and version, as JSON text.
  final packs = <String, Map<int, String>>{};

  final holidays = <int, List<String>>{
    2025: ['2025-12-25'],
    2026: ['2026-07-03', '2026-11-26', '2026-12-25'],
    2027: ['2027-01-01'],
  };
  final earlyCloses = <int, List<Map<String, String>>>{
    2026: [
      {'date': '2026-11-27', 'close': '13:00'},
      {'date': '2026-12-24', 'close': '13:00'},
    ],
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
      case ['v1', 'livret', 'rates']:
        body = {
          'rates': [
            {'validFrom': '2025-08-01', 'annualRate': '0.017'},
            {'validFrom': '2026-02-01', 'annualRate': '0.015'},
            {'validFrom': '2026-08-01', 'annualRate': '0.017'},
          ],
          'ceilings': [
            {'validFrom': '2013-01-01', 'amountCents': 2295000},
          ],
        };
      case ['v1', 'content', 'manifest']:
        body = {
          'packs': [
            for (final MapEntry(key: id, value: versions) in packs.entries)
              {
                'islandId': id,
                'version': versions.keys.reduce((a, b) => a > b ? a : b),
              },
          ],
        };
      case ['v1', 'content', 'packs', final id, final version]:
        final json = packs[id]?[int.parse(version)];
        if (json == null) return _json({}, 404);
        return ResponseBody.fromString(
          json,
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      case ['v1', 'calendar', final exchange]:
        final year = int.parse(q['year']!);
        final days = holidays[year];
        if (days == null) {
          return _json({
            'error': {'code': 'not_found', 'message': 'no calendar'},
          }, 404);
        }
        body = {
          'exchange': exchange,
          'year': year,
          'holidays': days,
          'earlyCloses': earlyCloses[year] ?? [],
        };
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
