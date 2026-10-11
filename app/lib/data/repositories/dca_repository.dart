import 'dart:convert';

import '../../domain/wallet/dca_simulator.dart';
import '../local/database.dart';
import 'guard.dart';

/// A simulation the user saved (BRIEF §4.10).
final class SavedDca {
  const SavedDca({
    required this.id,
    required this.params,
    required this.summary,
    required this.savedAt,
  });

  final String id;
  final DcaParams params;
  final DcaSummary summary;
  final DateTime savedAt;
}

/// Saved DCA simulations (BRIEF §6.1 `dca_simulations`). Every storage error
/// surfaces as a `StorageFailure`.
class DcaRepository {
  DcaRepository(this._db);

  final AppDatabase _db;

  Future<void> save(DcaParams params, DcaSummary summary, DateTime at) =>
      guardStorage(
        () => _db.learningDao.saveSimulation(
          DcaSimulationsCompanion.insert(
            id: '${at.microsecondsSinceEpoch}',
            params: jsonEncode(params.toJson()),
            result: jsonEncode(summary.toJson()),
            savedAt: at,
          ),
        ),
      );

  /// Newest first.
  Future<List<SavedDca>> saved() => guardStorage(
    () async => [
      for (final row in await _db.learningDao.simulations())
        SavedDca(
          id: row.id,
          params: DcaParams.fromJson(
            jsonDecode(row.params) as Map<String, Object?>,
          ),
          summary: DcaSummary.fromJson(
            jsonDecode(row.result) as Map<String, Object?>,
          ),
          savedAt: row.savedAt,
        ),
    ],
  );
}
