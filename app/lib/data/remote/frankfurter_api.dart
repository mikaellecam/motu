import 'package:dio/dio.dart';

import '../../core/money/money.dart';
import 'dto.dart';
import 'http.dart';

/// ECB reference rates from Frankfurter (no key), called directly by the app.
/// Every method throws a typed `Failure`.
class FrankfurterApi {
  FrankfurterApi({HttpClientAdapter? adapter})
    : _dio = httpClient('https://api.frankfurter.dev/v1', adapter: adapter);

  final Dio _dio;

  /// Daily rates of [base] → [quote] from [from] to [to], oldest first. Only
  /// days with an ECB fixing appear; a [from] without one may bring the last
  /// rate before it.
  Future<List<FxRateDto>> rates(
    Currency base,
    Currency quote,
    DateTime from,
    DateTime to,
  ) => guardNetwork(() async {
    const day = DayConverter();
    final response = await _dio.get<Map<String, dynamic>>(
      '/${day.toJson(from)}..${day.toJson(to)}',
      queryParameters: {'base': base.code, 'symbols': quote.code},
    );
    return FrankfurterSeriesDto.fromJson(response.data!).ratesOf(quote);
  });
}
