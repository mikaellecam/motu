import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

/// Every schema ever shipped (drift_schemas/) must migrate to the current
/// one. After a schema change: bump `schemaVersion`, add the step, run
/// `dart run drift_dev make-migrations` and
/// `dart run drift_dev schema generate drift_schemas/app_database/ test/drift/app_database/generated/`.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  for (final from in GeneratedHelper.versions) {
    test('schema v$from migrates to the current schema', () async {
      final db = AppDatabase(await verifier.startAt(from));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, db.schemaVersion);
    });
  }

  test('the code matches the latest recorded schema', () async {
    // Fails when a table changes without a new schema version and dump.
    final db = AppDatabase(
      await verifier.startAt(GeneratedHelper.versions.last),
    );
    addTearDown(db.close);
    await db.validateDatabaseSchema();
  });

  test('the current schema version is recorded', () {
    final db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(db.close);
    expect(GeneratedHelper.versions.last, db.schemaVersion);
  });
}
