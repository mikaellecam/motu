import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/repositories/profile_repository.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const nbsp = ' ';

void main() {
  testWidgets('five questions, then where the path starts and why', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MainApp(router: buildRouter(initialLocation: '/onboarding')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Question 1 sur 5'), findsOneWidget);

    // Nothing chosen: the spec's message, no move.
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choisis une réponse pour continuer. Aucune n\'est mauvaise.'),
      findsOneWidget,
    );
    expect(find.text('Question 1 sur 5'), findsOneWidget);

    for (final answer in [
      'Long terme, plus de 8 ans',
      'J\'attends',
      'Ce qu\'est un ETF',
      'Compte courant',
      '15${nbsp}min',
    ]) {
      await tester.tap(find.text(answer));
      await tester.pump();
      expect(
        tester.getSemantics(find.text(answer)),
        matchesSemantics(
          label: answer,
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
    }

    expect(
      find.text(
        'On commence par «${nbsp}Ton premier ETF$nbsp» parce que tu as répondu '
        '«${nbsp}Ce qu\'est un ETF$nbsp».',
      ),
      findsOneWidget,
    );
    expect((await ProfileRepository(db).load()), isNotNull);

    await tester.tap(find.text('C\'est parti'));
    await tester.pumpAndSettle();
    expect(find.byType(MapTab), findsOneWidget);
  });
}
