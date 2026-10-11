import 'package:drift/drift.dart';

import '../../domain/learning/profile.dart';
import '../local/database.dart';
import '../local/tables.dart';
import 'guard.dart';

/// The onboarding answers (BRIEF §4.1). Saving replaces the answers only:
/// retaking the questionnaire never touches progress, discoveries or
/// settings.
class ProfileRepository {
  ProfileRepository(this._db);

  final AppDatabase _db;

  /// Null before the first onboarding.
  Future<Profile?> load() => guardStorage(() async {
    final row = await _db.learningDao.profile();
    if (row == null) return null;
    return Profile(
      goal: row.goal,
      dropReaction: row.dropReaction,
      knowledge: row.knowledge,
      savings: row.savings,
      weeklyTime: row.weeklyTime,
    );
  });

  Future<void> save(Profile profile) => guardStorage(
    () => _db.learningDao.saveProfile(
      ProfilesCompanion(
        goal: Value(profile.goal),
        dropReaction: Value(profile.dropReaction),
        knowledge: Value(profile.knowledge),
        savings: Value(profile.savings),
        weeklyTime: Value(profile.weeklyTime),
      ),
    ),
  );

  /// The « Tout afficher dès maintenant » setting (BRIEF §4.15).
  Future<bool> showAll() => guardStorage(
    () async => (await _db.learningDao.profile())?.showAll ?? false,
  );

  /// Ids of the nodes the user completed, then every change.
  Stream<Set<String>> watchCompletedNodes() =>
      _db.learningDao.watchProgress().map(
        (rows) => {
          for (final row in rows)
            if (row.status == NodeStatus.completed) row.nodeId,
        },
      );

  /// Ids of the nodes the user completed.
  Future<Set<String>> completedNodes() => guardStorage(
    () async => {
      for (final row in await _db.learningDao.progress())
        if (row.status == NodeStatus.completed) row.nodeId,
    },
  );

  /// Records a finished [nodeId] (BRIEF §4.3): one more attempt, the last
  /// [answer] when the node asks one, and the first completion kept.
  Future<void> completeNode(
    String nodeId, {
    String? answer,
    required DateTime at,
  }) => guardStorage(
    () => _db.transaction(() async {
      final before = (await _db.learningDao.progress())
          .where((r) => r.nodeId == nodeId)
          .firstOrNull;
      await _db.learningDao.saveProgress(
        NodeProgressCompanion.insert(
          nodeId: nodeId,
          status: NodeStatus.completed,
          attempts: Value((before?.attempts ?? 0) + 1),
          lastAnswer: Value(answer),
          completedAt: Value(before?.completedAt ?? at),
        ),
      );
    }),
  );
}
