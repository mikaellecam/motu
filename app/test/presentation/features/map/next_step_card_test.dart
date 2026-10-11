import 'package:finance_companion/application/learning/glossary.dart';
import 'package:finance_companion/application/learning/next_step_card.dart';
import 'package:finance_companion/core/l10n/app_localizations.dart';
import 'package:finance_companion/core/theme/app_theme.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/next_step.dart';
import 'package:finance_companion/presentation/features/glossary/term_sheet.dart';
import 'package:finance_companion/presentation/features/map/next_step_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The card on a bare screen; the routes it opens print where they lead.
Future<void> show(WidgetTester tester, NextStepView? view) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nextStepViewProvider.overrideWith((ref) async => view),
        termSheetProvider.overrideWith(
          (ref, id) async => TermSheetView(
            term: GlossaryTerm(
              id: id,
              title: const Localized('Matelas de sécurité', 'Safety cushion'),
              short: const Localized('x', 'x'),
              body: const Localized('x', 'x'),
            ),
            related: const [],
            firstOpen: true,
            terms: const {},
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: appTheme(),
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: NextStepCard()),
            ),
            for (final path in ['/node/:id', '/wallet/:id'])
              GoRoute(
                path: path,
                builder: (_, state) =>
                    Text('${path.split('/')[1]} ${state.pathParameters['id']}'),
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> go(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a lesson: its title, then the node player', (tester) async {
    await show(
      tester,
      const NextStepView(
        PlayNode('ae.fees-toy'),
        title: Localized('Le jouet des frais', 'The fees toy'),
      ),
    );
    expect(find.text('Prochaine leçon'), findsOneWidget);
    expect(find.text('Le jouet des frais'), findsOneWidget);
    await go(tester, 'Jouer');
    expect(find.text('node ae.fees-toy'), findsOneWidget);
  });

  testWidgets('a mission: « Voir la mission »', (tester) async {
    await show(
      tester,
      const NextStepView(
        DoMission('ae.mission-first-etf'),
        title: Localized('Ton premier ETF', 'Your first ETF'),
      ),
    );
    expect(find.text('Ta mission'), findsOneWidget);
    await go(tester, 'Voir la mission');
    expect(find.text('node ae.mission-first-etf'), findsOneWidget);
  });

  testWidgets('the safety cushion opens its sheet', (tester) async {
    await show(
      tester,
      const NextStepView(
        OpenGlossary('matelas-de-securite'),
        title: Localized('Matelas de sécurité', 'Safety cushion'),
      ),
    );
    expect(find.text("Avant d'investir"), findsOneWidget);
    await go(tester, 'Lire');
    expect(find.byType(TermSheet), findsOneWidget);
  });

  testWidgets('a trip: its name, then its wallet', (tester) async {
    await show(
      tester,
      const NextStepView(ContinueTrip('t2'), tripName: 'Covid'),
    );
    expect(find.text('Ton voyage dans le temps'), findsOneWidget);
    expect(find.text('Covid'), findsOneWidget);
    await go(tester, 'Reprendre');
    expect(find.text('wallet t2'), findsOneWidget);
  });

  testWidgets('nothing else to do: the live wallet', (tester) async {
    await show(tester, const NextStepView(OpenLiveWallet()));
    expect(find.text('Vois où en sont tes positions'), findsOneWidget);
    await go(tester, 'Ouvrir');
    expect(find.text('wallet live'), findsOneWidget);
  });

  testWidgets('before the questionnaire: no card', (tester) async {
    await show(tester, null);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(Text), findsNothing);
  });
}
