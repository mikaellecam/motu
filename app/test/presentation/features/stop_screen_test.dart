import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/trip/trip_stop.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/wallet/stop_decision.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/trip/stop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

StopView view(List<StopReason> reasons, {StopChart? chart}) => StopView(
  walletId: 'trip',
  date: day(10, 6),
  reasons: reasons,
  assetNames: const {'o1': 'Coca-Cola', 'ko': 'Coca-Cola'},
  chart: chart,
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
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return actions;
}

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
    ),
  );

  testWidgets('a drop: why, the stop line, three answers with their risks', (
    tester,
  ) async {
    final actions = await show(tester, drop);
    expect(find.text('Arrêt automatique'), findsOneWidget);
    expect(find.text('Le 6 octobre 2008'), findsOneWidget);
    expect(
      find.text(
        "Ton portefeuille vaut 8${nnbsp}400,00$nbsp€, sous la ligne de 8${nnbsp}500,00$nbsp€$nnbsp: 15$nnbsp% sous l'argent versé.",
      ),
      findsOneWidget,
    );
    expect(find.text("Ligne d'arrêt"), findsOneWidget);
    expect(find.text('Garder'), findsOneWidget);
    expect(
      find.text('Si la baisse continue, tu limites la perte.'),
      findsOneWidget,
    );
    expect(
      find.text('Tu ne profites pas d’une remontée, et tu paies des frais.'),
      findsOneWidget,
    );
    expect(
      find.text('Les ventes passent au prochain jour de cotation.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(actions.decisions, isEmpty, reason: 'no answer chosen yet');

    await tester.tap(find.text('Vendre la moitié'));
    await tester.enterText(find.byType(TextField), 'Je dors mal');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(actions.decisions, [(StopDecision.sellHalf, 'Je dors mal')]);
    expect(find.text('wallet trip'), findsOneWidget);
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
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(actions.decisions, [(StopDecision.carryOn, '')]);
  });

  testWidgets('a position drop names the asset and its loss', (tester) async {
    await show(tester, view([PositionLossStop('ko', dec('-0.2134'))]));
    expect(
      find.text(
        "Coca-Cola a perdu −21,34$nnbsp% par rapport à son prix d'achat.",
      ),
      findsOneWidget,
    );
  });
}
