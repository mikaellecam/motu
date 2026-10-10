import 'package:drift/drift.dart';

import '../../core/clock/simulation_clock.dart';
import '../../core/failure.dart';
import '../../domain/learning/content.dart';
import '../content/pack_codec.dart';
import '../local/daos/market_dao.dart';
import '../local/database.dart';
import '../remote/backend_api.dart';
import 'guard.dart';

/// Island content (ADR-006). The app bundles a baseline pack per island, so
/// the first launch works offline; once a day it asks the backend for a
/// newer version and caches it. A cached or downloaded pack that cannot be
/// read never replaces a good one: the bundled pack stands in.
class ContentRepository {
  ContentRepository(
    AppDatabase db,
    this._api, {
    required this._bundled,
    SimulationClock wallClock = const LiveClock(),
  }) : _dao = db.marketDao,
       _wall = wallClock;

  final MarketDao _dao;
  final BackendApi _api;
  final Future<String> Function(String islandId) _bundled;
  final SimulationClock _wall;

  /// Content packs are checked at most once a day (BRIEF §6.2).
  static const check = Duration(days: 1);

  /// When the manifest was last checked for an island still on its bundled
  /// pack (a cached pack keeps it in its row).
  final _checkedAt = <String, DateTime>{};

  /// The newest readable pack of [islandId]: cached, downloaded or bundled.
  Future<ContentPack> pack(String islandId) => guardStorage(() async {
    // The bundle ships with the app: if it cannot be read, that is a build
    // bug, and it surfaces.
    var current = decodePack(await _bundled(islandId));
    final row = await _dao.contentPack(islandId);
    if (row != null) {
      final cached = _read(row.json);
      if (cached == null || cached.id != islandId) {
        await _dao.deleteContentPack(islandId);
      } else if (cached.version > current.version) {
        current = cached;
      }
    }

    final now = _wall.now();
    final checked = row?.checkedAt ?? _checkedAt[islandId];
    if (checked != null && now.difference(checked) < check) return current;
    try {
      final latest = (await _api.contentManifest())[islandId];
      if (latest != null && latest > current.version) {
        final json = await _api.contentPack(islandId, latest);
        final fresh = _read(json);
        if (fresh != null && fresh.id == islandId && fresh.version == latest) {
          await _dao.saveContentPack(
            ContentPacksCompanion.insert(
              islandId: islandId,
              version: latest,
              json: json,
              checkedAt: now,
            ),
          );
          return fresh;
        }
      }
      if (row != null && current.version == row.version) {
        await _dao.saveContentPack(
          row.toCompanion(true).copyWith(checkedAt: Value(now)),
        );
      } else {
        _checkedAt[islandId] = now;
      }
    } on Failure {
      // Offline or the backend failed: the current pack stays.
    }
    return current;
  });

  static ContentPack? _read(String json) {
    try {
      return decodePack(json);
    } on FormatException {
      return null;
    }
  }
}
