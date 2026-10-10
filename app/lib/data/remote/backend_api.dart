import 'package:dio/dio.dart';

import '../../domain/market/market_calendar.dart';
import 'dto.dart';
import 'http.dart';

/// Our backend (BRIEF §8.3). Every method throws a typed `Failure`.
class BackendApi {
  BackendApi(String baseUrl, {HttpClientAdapter? adapter})
    : _dio = httpClient(baseUrl, adapter: adapter);

  final Dio _dio;

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

  Future<List<AssetDto>> assets() => guardNetwork(
    () async => _list(await _get('/v1/assets'), 'assets', AssetDto.fromJson),
  );

  /// Bars from [from] to [to] included; open ends mean the whole history.
  Future<HistoryDto> history(String assetId, {DateTime? from, DateTime? to}) =>
      guardNetwork(
        () async => HistoryDto.fromJson(
          await _get('/v1/assets/${Uri.encodeComponent(assetId)}/history', {
            if (from != null) 'from': const DayConverter().toJson(from),
            if (to != null) 'to': const DayConverter().toJson(to),
          }),
        ),
      );

  /// Unknown ids are left out of the answer.
  Future<List<QuoteDto>> quotes(Iterable<String> assetIds) => guardNetwork(
    () async => _list(
      await _get('/v1/quotes', {'ids': assetIds.join(',')}),
      'quotes',
      QuoteDto.fromJson,
    ),
  );

  Future<LivretDto> livret() => guardNetwork(
    () async => LivretDto.fromJson(await _get('/v1/livret/rates')),
  );

  Future<CalendarDto> calendar(Exchange exchange, int year) => guardNetwork(
    () async => CalendarDto.fromJson(
      await _get('/v1/calendar/${exchange.name}', {'year': year}),
    ),
  );

  /// The latest version of each island's content pack (ADR-006).
  Future<Map<String, int>> contentManifest() => guardNetwork(() async {
    final json = await _get('/v1/content/manifest');
    return {
      for (final p in json['packs'] as List)
        (p as Map)['islandId'] as String: p['version'] as int,
    };
  });

  /// One version of an island's pack, as the JSON text to cache.
  Future<String> contentPack(String islandId, int version) => guardNetwork(
    () async => (await _dio.get<String>(
      '/v1/content/packs/${Uri.encodeComponent(islandId)}/$version',
      options: Options(responseType: ResponseType.plain),
    )).data!,
  );
}
