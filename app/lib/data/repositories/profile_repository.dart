import 'package:drift/drift.dart';

import '../../core/money/money.dart';
import '../../domain/learning/profile.dart';
import '../local/database.dart';
import '../local/tables.dart';
import 'guard.dart';

/// What Settings keeps (BRIEF §4.14) beside the questionnaire's answers.
final class AppSettings {
  const AppSettings({
    this.language,
    this.showAll = false,
    this.liveStartingCash,
  });

  /// `fr` or `en`; null follows the device.
  final String? language;
  final bool showAll;

  /// The live wallet's next starting cash; null for the default.
  final Money? liveStartingCash;
}

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

  /// The settings (BRIEF §4.14), then every change; the defaults before the
  /// first onboarding.
  Stream<AppSettings> watchSettings() => _db.learningDao.watchProfile().map(
    (row) => AppSettings(
      language: row?.language,
      showAll: row?.showAll ?? false,
      liveStartingCash: row?.liveStartingCents == null
          ? null
          : Money(row!.liveStartingCents!, Currency.eur),
    ),
  );

  /// `fr` or `en`; null follows the device.
  Future<void> setLanguage(String? code) => guardStorage(
    () =>
        _db.learningDao.updateProfile(ProfilesCompanion(language: Value(code))),
  );

  Future<void> setShowAll(bool on) => guardStorage(
    () => _db.learningDao.updateProfile(ProfilesCompanion(showAll: Value(on))),
  );

  /// The live wallet's starting cash the next time it is created (decided
  /// 2026-10-12: it applies at the next reset).
  Future<void> setLiveStartingCash(Money amount) => guardStorage(
    () => _db.learningDao.updateProfile(
      ProfilesCompanion(liveStartingCents: Value(amount.minorUnits)),
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

  /// The nodes the user completed, each with its first completion, then
  /// every change (the next-step card's pacing counts today's).
  Stream<Map<String, DateTime>> watchCompletions() =>
      _db.learningDao.watchProgress().map(
        (rows) => {
          for (final row in rows)
            if (row.status == NodeStatus.completed && row.completedAt != null)
              row.nodeId: row.completedAt!,
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
