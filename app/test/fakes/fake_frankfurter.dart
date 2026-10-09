import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Frankfurter's range endpoint over a set of published USD→EUR rates. Like
/// the real one, a range starting on a day without a rate also brings the
/// last rate before it.
class FakeFrankfurter implements HttpClientAdapter {
  final requests = <Uri>[];
  bool offline = false;
  final published = <String, num>{
    '2000-01-03': 0.9847,
    '2008-09-15': 0.70582,
    '2026-10-01': 0.8513,
    '2026-10-02': 0.85125, // Friday
    '2026-10-05': 0.85251, // Monday
    '2026-10-06': 0.85,
    '2026-10-07': 0.8547,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    if (offline) throw const SocketException('offline');
    final [from, to] = options.uri.pathSegments.last.split('..');
    final days = published.keys.toList()..sort();
    final inRange = [
      for (final d in days)
        if (d.compareTo(from) >= 0 && d.compareTo(to) <= 0) d,
    ];
    final before = [
      for (final d in days)
        if (d.compareTo(from) < 0) d,
    ];
    if (!published.containsKey(from) && before.isNotEmpty) {
      inRange.insert(0, before.last);
    }
    return ResponseBody.fromString(
      jsonEncode({
        'amount': 1.0,
        'base': 'USD',
        'rates': {
          for (final d in inRange) d: {'EUR': published[d]},
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
