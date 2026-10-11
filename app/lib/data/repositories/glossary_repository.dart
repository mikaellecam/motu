import '../../domain/companion/rules.dart';
import '../local/database.dart';
import 'guard.dart';

/// What the user did with a glossary term: when its sheet was first opened,
/// and whether its quiz was passed (BRIEF §4.4, `glossary_state`).
final class TermProgress {
  const TermProgress(this.discoveredAt, {required this.quizPassed});
  final DateTime discoveredAt;
  final bool quizPassed;
}

/// Glossary discoveries and quizzes, and the companion moments whose terms
/// count as met.
class GlossaryRepository {
  GlossaryRepository(this._db);

  final AppDatabase _db;

  /// Term id → its progress, for the terms discovered; then every change.
  Stream<Map<String, TermProgress>> watch() =>
      _db.learningDao.watchGlossary().map(
        (rows) => {
          for (final r in rows)
            r.termId: TermProgress(r.discoveredAt, quizPassed: r.quizPassed),
        },
      );

  /// Marks [termId] discovered on its first open (persisted); true when
  /// this open was the first.
  Future<bool> discover(String termId, DateTime at) => guardStorage(
    () => _db.transaction(() async {
      final known = (await _db.learningDao.discovered()).any(
        (r) => r.termId == termId,
      );
      if (!known) await _db.learningDao.discover(termId, at);
      return !known;
    }),
  );

  Future<void> passQuiz(String termId) =>
      guardStorage(() => _db.learningDao.passQuiz(termId));

  /// The rules of every companion moment shown, in any wallet.
  Future<Set<CompanionRule>> momentsShown() => guardStorage(
    () async => {for (final r in await _db.learningDao.allMoments()) r.rule},
  );
}
