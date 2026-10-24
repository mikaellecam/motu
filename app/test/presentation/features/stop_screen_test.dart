import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/learning/glossary.dart';
import 'package:finance_companion/application/trip/trip_stop.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/wallet/stop_decision.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/trip/stop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';

const nnbsp = ' ';
const nbsp = ' ';
DateTime day(int m, int d) => DateTime.utc(2008, m, d);
Decimal dec(String s) => Decimal.parse(s);

/// Records the answers.
class FakeStopActions extends StopActions {
  final decisions = <(StopDecision, String?)>[];

  @override
  FutureOr<void> build(String walletId) {}

  @override
  Future<void> decide(StopDecision decision, {String? reason}) async =>
      decisions.add((decision, reason));
}

StopView view(
  List<StopReason> reasons, {
  StopChart? chart,
  Decimal? portfolioLoss,
}) => StopView(
  walletId: 'trip',
  name: 'Crise financière',
  date: day(10, 6),
  reasons: reasons,
  assetNames: const {'o1': 'Coca-Cola', 'ko': 'Coca-Cola'},
  chart: chart,
  cash: const Money(218800, Currency.eur),
  portfolioLoss: portfolioLoss,
);

Future<FakeStopActions> show(WidgetTester tester, StopView v) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final actions = FakeStopActions();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tripStopProvider.overrideWith((ref, id) async => v),
        stopActionsProvider.overrideWith2((_) => actions),
        termSheetProvider.overrideWith(
          (ref, id) async => TermSheetView(
            term: GlossaryTerm(
              id: id,
              title: const Localized('Pire baisse', 'Worst drop'),
              short: const Localized('La plus forte chute.', 'x'),
              body: const Localized('x', 'x'),
            ),
            related: const [],
            firstOpen: false,
            terms: const {},
          ),
        ),
      ],
      child: MainApp(
        router: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const StopScreen(walletId: 'trip'),
            ),
            GoRoute(
              path: '/wallet/:id',
              builder: (_, s) => Text('wallet ${s.pathParameters['id']}'),
            ),
            GoRoute(path: '/wallets', builder: (_, _) => const Text('wallets')),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return actions;
}

/// Scrolls the screen (not the reason field) until [finder] shows.
Future<void> scrollTo(WidgetTester tester, Finder finder) => tester
    .scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);

void main() {
  final drop = view(
    const [
      DrawdownStop(
        value: Money(840000, Currency.eur),
        threshold: Money(850000, Currency.eur),
      ),
    ],
    chart: StopChart(
      [day(9, 15), day(10, 3), day(10, 6)],
      [dec('10000'), dec('9100'), dec('8400')],
      [dec('8500'), dec('8500'), dec('8500')],
      limit: dec('0.15'),
      market: dec('-0.04'),
    ),
    portfolioLoss: dec('-0.16'),
  );

  testWidgets('a drop: the trip, the fall against its threshold, the market, '
      'three answers with their risks', (tester) async {
    final semantics = tester.ensureSemantics();
    final actions = await show(tester, drop);
    // The trip's header, then the card's overline.
    expect(find.text('Voyage «${nbsp}Crise financière$nbsp»'), findsOneWidget);
    expect(find.text('6 octobre 2008'), findsOneWidget);
    expect(find.text('Arrêt automatique'), findsNWidgets(2));
    final headline = find.text(
      "Ton portefeuille est à −16,00$nnbsp% de l'argent versé.",
    );
    expect(tester.widget<Text>(headline).style?.fontFamily, 'Baloo2');
    expect(find.text('Ton seuil$nnbsp: −15$nnbsp%'), findsOneWidget);
    expect(find.text('6 oct.'), findsOneWidget, reason: 'a dated axis');
    expect(
      find.text(
        "Sur la même période, l'ETF Monde a fait −4,00$nnbsp%. "
        'Il te reste 2${nnbsp}188,00$nbsp€ de liquidités.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('Garder')).style?.fontFamily,
      'Baloo2',
    );
    expect(
      find.text('Si la baisse continue, tu limites la perte.'),
      findsOneWidget,
    );
    expect(
      find.text('Tu ne profites pas d’une remontée, et tu paies des frais.'),
      findsOneWidget,
    );
    // Below the fold from here on.
    await scrollTo(
      tester,
      find.text('Les ventes passent au prochain jour de cotation.'),
    );
    // The reason: labelled, for screen readers too, and where it goes.
    await scrollTo(
      tester,
      find.text(
        'Ta décision est notée dans ton journal de voyage. '
        'On la relira ensemble à la fin.',
      ),
    );
    expect(find.text('Pourquoi$nnbsp? (facultatif)'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(TextField)),
      isSemantics(
        label:
            'Pourquoi$nnbsp? (facultatif)\n'
            'Ex.$nnbsp: j\'ai peur que ça continue',
        isTextField: true,
      ),
    );

    await scrollTo(tester, find.text('Valider'));
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(actions.decisions, isEmpty, reason: 'no answer chosen yet');

    await tester.ensureVisible(find.text('Vendre la moitié'));
    await tester.tap(find.text('Vendre la moitié'));
    await tester.enterText(find.byType(TextField), 'Je dors mal');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Valider'));
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(actions.decisions, [(StopDecision.sellHalf, 'Je dors mal')]);
    expect(find.text('wallet trip'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a filled order or a contribution: just carry on', (
    tester,
  ) async {
    final actions = await show(
      tester,
      view(const [
        OrderFilledStop('o1'),
        ContributionStop(Money(20000, Currency.eur)),
      ]),
    );
    expect(find.text('Ton ordre sur Coca-Cola a été exécuté.'), findsOneWidget);
    expect(
      find.text('Ton versement mensuel de 200,00$nbsp€ est arrivé.'),
      findsOneWidget,
    );
    expect(find.text('Garder'), findsNothing);
    expect(find.text('c’est quoi, une pire baisse$nnbsp?'), findsNothing);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(actions.decisions, [(StopDecision.carryOn, '')]);
  });

  testWidgets('a position drop names the asset and its loss', (tester) async {
    await show(tester, view([PositionLossStop('ko', dec('-0.2134'))]));
    expect(
      find.text("Coca-Cola est à −21,34$nnbsp% de son prix d'achat."),
      findsOneWidget,
    );
  });

  testWidgets('before choosing, what a worst drop is', (tester) async {
    await show(tester, drop);
    final link = find.text('c’est quoi, une pire baisse$nnbsp?');
    await scrollTo(tester, link);
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    expect(find.text('Avant de choisir$nnbsp:'), findsOneWidget);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('La plus forte chute.'), findsOneWidget);
  });

  testWidgets('the way out of the trip leads to the wallets', (tester) async {
    await show(tester, drop);
    await tester.tap(find.bySemanticsLabel('Quitter le voyage'));
    await tester.pumpAndSettle();
    expect(find.text('wallets'), findsOneWidget);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester, drop);
    await expectAccessible(tester);
  });
}
