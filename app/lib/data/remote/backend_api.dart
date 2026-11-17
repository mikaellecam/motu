import 'package:dio/dio.dart';

import '../../core/failure.dart';
import '../../domain/market/market_calendar.dart';
import 'dto.dart';
import 'http.dart';

/// Our backend (BRIEF §8.3). Every method throws a typed `Failure`.
///
/// Once a request finds the backend unreachable, the calls of the next
/// [quiet] fail at once with the same [NetworkFailure], without a request
/// (M13-18): offline, a screen's dozens of reads each wait on the network
/// otherwise, and the cache answers late. A success or [reconnect] ends the
/// pause; other failures (a rate limit, a 404, a server error) start none.
class BackendApi {
  BackendApi(
    String baseUrl, {
    HttpClientAdapter? adapter,
    this.quiet = Duration.zero,
    DateTime Function()? now,
  }) : _dio = httpClient(baseUrl, adapter: adapter),
       _now = now ?? DateTime.now;

  final Dio _dio;
  final Duration quiet;
  final DateTime Function() _now;

  /// Until when the backend counts as unreachable.
  DateTime? _downUntil;

  /// « Réessayer »: the next call tries the network, even mid-pause.
  void reconnect() => _downUntil = null;

  Future<T> _guard<T>(Future<T> Function() body) async {
    if (_downUntil case final until? when _now().isBefore(until)) {
      throw const NetworkFailure();
    }
    try {
      final result = await guardNetwork(body);
      _downUntil = null;
      return result;
    } on NetworkFailure {
      if (quiet > Duration.zero) _downUntil = _now().add(quiet);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, dynamic>? query,
  ]) async => (await _dio.get<Map<String, dynamic>>(
    path,
    queryParameters: query,
  )).data!;

  static List<T> _list<T>(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic>) decode,
  ) => [
    for (final item in json[key] as List) decode(item as Map<String, dynamic>),
  ];

  Future<List<AssetDto>> assets() => _guard(
    () async => _list(await _get('/v1/assets'), 'assets', AssetDto.fromJson),
  );

  /// Bars from [from] to [to] included; open ends mean the whole history.
  Future<HistoryDto> history(String assetId, {DateTime? from, DateTime? to}) =>
      _guard(
        () async => HistoryDto.fromJson(
          await _get('/v1/assets/${Uri.encodeComponent(assetId)}/history', {
            if (from != null) 'from': const DayConverter().toJson(from),
            if (to != null) 'to': const DayConverter().toJson(to),
          }),
        ),
      );

  /// Unknown ids are left out of the answer.
  Future<List<QuoteDto>> quotes(Iterable<String> assetIds) => _guard(
    () async => _list(
      await _get('/v1/quotes', {'ids': assetIds.join(',')}),
      'quotes',
      QuoteDto.fromJson,
    ),
  );

  Future<LivretDto> livret() =>
      _guard(() async => LivretDto.fromJson(await _get('/v1/livret/rates')));

  Future<CalendarDto> calendar(Exchange exchange, int year) => _guard(
    () async => CalendarDto.fromJson(
      await _get('/v1/calendar/${exchange.name}', {'year': year}),
    ),
  );

  /// The latest version of each island's content pack (ADR-006).
  Future<Map<String, int>> contentManifest() => _guard(() async {
    final json = await _get('/v1/content/manifest');
    return {
      for (final p in json['packs'] as List)
        (p as Map)['islandId'] as String: p['version'] as int,
    };
  });

  /// One version of an island's pack, as the JSON text to cache.
  Future<String> contentPack(String islandId, int version) => _guard(
    () async => (await _dio.get<String>(
      '/v1/content/packs/${Uri.encodeComponent(islandId)}/$version',
      options: Options(responseType: ResponseType.plain),
    )).data!,
  );
}
