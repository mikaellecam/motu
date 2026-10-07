/// Typed errors carried by `AsyncValue.error` and returned by domain
/// validation (BRIEF §5.3). The UI turns them into copy; nothing downstream
/// ever sees a raw error string.
sealed class Failure {
  const Failure();
}

/// The server could not be reached, or the request timed out.
final class NetworkFailure extends Failure {
  const NetworkFailure();
}

/// HTTP 429: the backend asks to wait before the next request.
final class RateLimitedFailure extends Failure {
  const RateLimitedFailure(this.retryAfter);
  final Duration retryAfter;
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure();
}

/// No data on or before [asOf] in the cache, and none can be fetched.
final class DataUnavailableFailure extends Failure {
  const DataUnavailableFailure(this.asOf);
  final DateTime asOf;
}

/// A rule broken by user input. [code] selects the copy, [params] fill it.
final class ValidationFailure extends Failure {
  const ValidationFailure(this.code, [this.params = const {}]);
  final String code;
  final Map<String, Object> params;
}

/// The local database could not be read or written.
final class StorageFailure extends Failure {
  const StorageFailure();
}
