import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_wizard.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/trip_wizard/trip_wizard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';

const nnbsp = ' ';
const nbsp = ' ';
DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

final dates = WizardDates(
  presets: [
    PresetOption(TripPreset.dotcom, day(2000, 3, 10), 12),
    PresetOption(TripPreset.lehman, day(2008, 9, 15), 22),
    PresetOption(TripPreset.covid, day(2020, 2, 18), 29),
    PresetOption(TripPreset.inflation, day(2022, 1, 3), 29),
    PresetOption(TripPreset.oneYear, day(2025, 10, 10), 29),
    PresetOption(TripPreset.fiveYears, day(2021, 10, 11), 29),
    PresetOption(TripPreset.tenYears, day(2016, 10, 11), 28),
  ],
  catalogueSize: 29,
  exchanges: {Exchange.nyse},
  listingDates: [for (var i = 0; i < 22; i++) day(2000, 1, 3)],
);

Future<void> show(
  WidgetTester tester, {
  TripWizardArgs args = const TripWizardArgs(),
}) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final wall = WallClock(DateTime.utc(2026, 10, 11, 10));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(wall),
        marketRepositoryProvider.overrideWithValue(
          MarketRepository(
            db,
            BackendApi('http://t', adapter: FakeBackend()),
            wallClock: wall,
          ),
        ),
        wizardDatesProvider.overrideWith((ref) async => dates),
        lessonBeforeProvider.overrideWith(
          (ref, d) async => d.year == 1929
              ? const NodeContent(
                  id: 'basics.1929',
                  type: NodeType.predictReveal,
                  title: Localized('Le krach de 1929', 'The 1929 crash'),
                  status: ContentStatus.draft,
                )
              : null,
        ),
      ],
      child: MainApp.screen(TripWizardScreen(args: args)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> typeDate(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

Finder get next => find.text('Suivant');

void main() {
  testWidgets('the moments and shortcuts, each with what existed then', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Étape 1 sur 3'), findsOneWidget);
    expect(find.text('Quand pars-tu$nnbsp?'), findsOneWidget);
    expect(find.text('Crise financière'), findsOneWidget);
    expect(find.text('15 septembre 2008'), findsOneWidget);
    expect(
      find.text('Le jour de la faillite de Lehman Brothers'),
      findsOneWidget,
    );
    expect(find.text('22 actifs sur 29 disponibles'), findsOneWidget);
    expect(find.text('Il y a 1 an'), findsOneWidget);
    expect(find.text('Il y a 10 ans'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('choosing a moment enables Suivant, which moves on', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Crise financière'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget, reason: 'step 2');
  });

  testWidgets('a typed date: errors, the floor and its lesson, a roll', (
    tester,
  ) async {
    await show(tester);
    await typeDate(tester, '31/02/2020');
    expect(
      find.text("Cette date n'existe pas. Écris-la comme 15/09/2008."),
      findsOneWidget,
    );

    await typeDate(tester, '24/10/1929');
    expect(
      find.text('Nos cours commencent le 3 janvier 2000.'),
      findsOneWidget,
    );
    expect(
      find.text('Voir la leçon «${nbsp}Le krach de 1929$nbsp»'),
      findsOneWidget,
    );

    await typeDate(tester, '01/10/2026');
    expect(
      find.text(
        'Pars au plus tard le 11 septembre 2026$nnbsp: il faut au moins 30 jours de cours devant toi.',
      ),
      findsOneWidget,
    );

    await typeDate(tester, '13/09/2008');
    expect(
      find.text(
        "Le 13 septembre 2008 n'a pas eu de séance$nnbsp: départ le 15 septembre 2008.",
      ),
      findsOneWidget,
    );
    expect(find.text('22 actifs sur 29 disponibles'), findsNWidgets(2));
  });

  testWidgets('a lesson bridge arrives with its moment chosen', (tester) async {
    await show(
      tester,
      args: TripWizardArgs(date: day(2020, 2, 18), fromNode: 'ae.march-2020'),
    );
    final card = find
        .ancestor(of: find.text('Covid'), matching: find.byType(Semantics))
        .first;
    expect(tester.getSemantics(card), isSemantics(isSelected: true));
  });
}
