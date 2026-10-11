import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

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

  test('v1 → v2: a trip keeps its row and has no stop reasons yet', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) => batch.insert(
        oldDb.wallets,
        const v1.WalletsData(
          id: 'trip',
          kind: 'trip',
          name: 'Lehman',
          startDate: '2008-09-15T00:00:00.000Z',
          simDate: '2008-10-03T00:00:00.000Z',
          difficulty: 'realiste',
          params: '{}',
          status: 'stopped',
          createdAt: '2026-10-11T00:00:00.000Z',
          breachedStops: '["drawdown"]',
          companionState: null,
        ),
      ),
      validateItems: (newDb) async {
        final row = await newDb.select(newDb.wallets).getSingle();
        expect(row.name, 'Lehman');
        expect(row.breachedStops, '["drawdown"]');
        expect(row.stopReasons, isNull);
      },
    );
  });

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
