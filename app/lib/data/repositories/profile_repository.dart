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

  /// Ids of the nodes the user completed.
  Future<Set<String>> completedNodes() => guardStorage(
    () async => {
      for (final row in await _db.learningDao.progress())
        if (row.status == NodeStatus.completed) row.nodeId,
    },
  );
}
