import '../local/database.dart';
import 'guard.dart';

/// Assets the user starred in the Explorer (BRIEF §4.9), kept on the device.
class FavoritesRepository {
  FavoritesRepository(this._db);

  final AppDatabase _db;

  /// The starred asset ids, then every change.
  Stream<Set<String>> watch() => _db.learningDao.watchFavorites();

  /// Stars or unstars [assetId]; returns whether it is starred now.
  Future<bool> toggle(String assetId, DateTime at) =>
      guardStorage(() => _db.learningDao.toggleFavorite(assetId, at));
}
