import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // As main() runs it: inside a provider scope. No wallet behind the map.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          livingIslandProvider.overrideWith((ref) async => const []),
        ],
        child: MainApp(router: buildRouter()),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
