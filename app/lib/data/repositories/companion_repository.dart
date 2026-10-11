import '../../domain/companion/rules.dart';
import '../companion/companion_codec.dart';
import '../local/database.dart';
import 'guard.dart';

/// A companion moment not read yet (BRIEF §4.12): its card stays until the
/// user dismisses it.
final class ActiveMoment {
  const ActiveMoment({
    required this.id,
    required this.walletId,
    required this.rule,
    required this.key,
    required this.firedAt,
    required this.params,
  });

  final int id;
  final String walletId;
  final CompanionRule rule;
  final String key;
  final DateTime firedAt;

  /// What its copy needs (see `CompanionTracker.observe`).
  final Map<String, Object> params;

  /// The asset it is about, when it is about one.
  String? get assetId => params['assetId'] as String?;
}

/// Companion moments to read and dismiss. The engine logs them as wallets
/// move on; the cooldowns run on that log.
class CompanionRepository {
  CompanionRepository(this._db);

  final AppDatabase _db;

  /// Moments not dismissed yet, oldest first, across wallets; then every
  /// change.
  Stream<List<ActiveMoment>> watchActive() =>
      _db.learningDao.watchUnreadMoments().map(
        (rows) => [
          for (final row in rows)
            ActiveMoment(
              id: row.id,
              walletId: row.walletId,
              rule: row.rule,
              key: row.key,
              firedAt: row.firedAt,
              params: decodeParams(row.params),
            ),
        ],
      );

  /// « J'ai compris »: the card goes.
  Future<void> dismiss(int id, DateTime at) =>
      guardStorage(() => _db.learningDao.dismissMoment(id, at));
}
