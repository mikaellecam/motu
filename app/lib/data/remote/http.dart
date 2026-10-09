import 'package:dio/dio.dart';

import '../../core/failure.dart';

/// A Dio for one service, with timeouts: a request that hangs surfaces as a
/// [NetworkFailure] instead of a spinner forever.
Dio httpClient(String baseUrl, {HttpClientAdapter? adapter}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  if (adapter != null) dio.httpClientAdapter = adapter;
  return dio;
}

/// Runs a request and decodes its body. Failures come out typed:
/// unreachable or timed out → [NetworkFailure] (also 502–504, a proxy with no
/// server behind it), 429 → [RateLimitedFailure], 404 → [NotFoundFailure],
/// any other error status or an unreadable body → [ServerFailure].
Future<T> guardNetwork<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on Failure {
    rethrow;
  } on DioException catch (e) {
    throw _failureOf(e);
  } catch (_) {
    // Only decoding runs past the request: whatever it throws means the
    // body did not have the expected shape.
    throw const ServerFailure();
  }
}

Failure _failureOf(DioException e) {
  final response = e.response;
  if (e.type != DioExceptionType.badResponse || response == null) {
    return const NetworkFailure();
  }
  return switch (response.statusCode) {
    429 => RateLimitedFailure(
      Duration(
        seconds:
            int.tryParse(response.headers.value('retry-after') ?? '') ?? 60,
      ),
    ),
    404 => const NotFoundFailure(),
    502 || 503 || 504 => const NetworkFailure(),
    _ => const ServerFailure(),
  };
}
