import '../../core/failure.dart';

/// Runs a storage operation; any storage exception surfaces as a
/// [StorageFailure], typed failures pass through.
Future<T> guardStorage<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on Failure {
    rethrow;
  } on Exception {
    throw const StorageFailure();
  }
}
