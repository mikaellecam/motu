import 'package:finance_companion/data/repositories/profile_repository.dart';
import 'package:finance_companion/domain/learning/profile.dart';

/// Records the completed nodes.
class RecordingProfiles implements ProfileRepository {
  final completed = <(String, String?)>[];

  @override
  Future<void> completeNode(
    String nodeId, {
    String? answer,
    required DateTime at,
  }) async => completed.add((nodeId, answer));

  @override
  Future<Profile?> load() async => null;
  @override
  Future<void> save(Profile profile) async {}
  @override
  Future<bool> showAll() async => false;
  @override
  Future<Set<String>> completedNodes() async => const {};
  @override
  Stream<Set<String>> watchCompletedNodes() => Stream.value(const {});
}
