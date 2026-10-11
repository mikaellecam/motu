import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'learning_dao.g.dart';

/// The user's profile, progress, discoveries, favorites, companion log and
/// saved simulations.
@DriftAccessor(
  tables: [
    Profiles,
    NodeProgress,
    GlossaryState,
    Favorites,
    CompanionLog,
    DcaSimulations,
  ],
)
class LearningDao extends DatabaseAccessor<AppDatabase>
    with _$LearningDaoMixin {
  LearningDao(super.attachedDatabase);

  Future<ProfileRow?> profile() => select(profiles).getSingleOrNull();

  Stream<ProfileRow?> watchProfile() => select(profiles).watchSingleOrNull();

  /// Saves the single profile row (id 1).
  Future<void> saveProfile(ProfilesCompanion row) =>
      into(profiles).insertOnConflictUpdate(row.copyWith(id: const Value(1)));

  /// Writes the present fields of [row] to the existing profile (settings).
  Future<void> updateProfile(ProfilesCompanion row) =>
      (update(profiles)..where((p) => p.id.equals(1))).write(row);

  Future<List<NodeProgressRow>> progress() => select(nodeProgress).get();

  Stream<List<NodeProgressRow>> watchProgress() => select(nodeProgress).watch();

  Future<void> saveProgress(NodeProgressCompanion row) =>
      into(nodeProgress).insertOnConflictUpdate(row);

  /// Marks [termId] discovered; the first discovery date is kept.
  Future<void> discover(String termId, DateTime at) =>
      into(glossaryState).insert(
        GlossaryStateCompanion.insert(termId: termId, discoveredAt: at),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> passQuiz(String termId) =>
      (update(glossaryState)..where((g) => g.termId.equals(termId))).write(
        const GlossaryStateCompanion(quizPassed: Value(true)),
      );

  Future<List<GlossaryStateRow>> discovered() => select(glossaryState).get();

  Stream<List<GlossaryStateRow>> watchGlossary() =>
      select(glossaryState).watch();

  /// Every companion moment, in any wallet.
  Future<List<CompanionLogRow>> allMoments() => select(companionLog).get();

  Stream<Set<String>> watchFavorites() =>
      select(favorites)
          .watch()
          .map((rows) => {for (final row in rows) row.assetId});

  /// Adds or removes a favorite; returns whether it is now a favorite.
  Future<bool> toggleFavorite(String assetId, DateTime at) =>
      transaction(() async {
        final removed = await (delete(
          favorites,
        )..where((f) => f.assetId.equals(assetId))).go();
        if (removed > 0) return false;
        await into(favorites)
            .insert(FavoritesCompanion.insert(assetId: assetId, addedAt: at));
        return true;
      });

  Future<int> logMoment(CompanionLogCompanion row) =>
      into(companionLog).insert(row);

  Future<List<CompanionLogRow>> momentsOf(String walletId) =>
      (select(companionLog)
            ..where((m) => m.walletId.equals(walletId))
            ..orderBy([(m) => OrderingTerm(expression: m.firedAt)]))
          .get();

  /// Moments not dismissed yet, oldest first, across wallets.
  Future<List<CompanionLogRow>> unreadMoments() =>
      (select(companionLog)
            ..where((m) => m.dismissedAt.isNull())
            ..orderBy([(m) => OrderingTerm(expression: m.firedAt)]))
          .get();

  /// [unreadMoments], then every change.
  Stream<List<CompanionLogRow>> watchUnreadMoments() =>
      (select(companionLog)
            ..where((m) => m.dismissedAt.isNull())
            ..orderBy([
              (m) => OrderingTerm(expression: m.firedAt),
              (m) => OrderingTerm(expression: m.id),
            ]))
          .watch();

  Future<void> dismissMoment(int id, DateTime at) =>
      (update(companionLog)..where((m) => m.id.equals(id))).write(
        CompanionLogCompanion(dismissedAt: Value(at)),
      );

  Future<void> saveSimulation(DcaSimulationsCompanion row) =>
      into(dcaSimulations).insertOnConflictUpdate(row);

  Future<List<DcaSimulationRow>> simulations() =>
      (select(dcaSimulations)..orderBy([
            (s) => OrderingTerm(expression: s.savedAt, mode: OrderingMode.desc),
          ]))
          .get();

  Future<void> deleteSimulation(String id) =>
      (delete(dcaSimulations)..where((s) => s.id.equals(id))).go();
}
