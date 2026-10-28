import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/wallet/dca_plans.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/dca/plan_sheet.dart';
import 'package:finance_companion/core/widgets/chunky.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../fakes/fake_plan_setup.dart';
import '../../helpers.dart';

const nnbsp = '\u202f';
const nbsp = '\u00a0';

Money eur(String s) => Money.book(Decimal.parse(s), Currency.eur);

final apple = Asset(
  id: 'apple',
  symbol: 'AAPL',
  name: 'Apple',
  type: AssetType.stock,
  exchange: Exchange.nasdaq,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(1980, 12, 12),
);

late FakePlanSetup setup;

Future<void> show(
  WidgetTester tester, {
  Money? amount,
  DcaFrequency frequency = DcaFrequency.monthly,
  Money? fixedFee,
}) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  setup = FakePlanSetup(planContext(apple, fixedFee: fixedFee));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [planSetupProvider.overrideWith2((_) => setup)],
      child: MainApp(
        router: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () => showPlanSheet(
                        context,
                        assetId: 'apple',
                        walletId: 'live',
                        amount: amount,
                        frequency: frequency,
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/wallet/:walletId',
              builder: (_, state) =>
                  Text('wallet ${state.pathParameters['walletId']}'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder button(String label) => find.widgetWithText(ChunkyButton, label);

void main() {
  testWidgets('the amount, the frequency, the first purchase', (tester) async {
    await show(tester);
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Versement programmé'), findsOneWidget);
    expect(
      find.text(
        'Le même montant est investi à chaque date, quel que soit le cours.',
      ),
      findsOneWidget,
    );
    expect(find.text('Premier achat$nnbsp: le 9 octobre 2026'), findsOneWidget);
    expect(
      find.text(
        'Puis chaque mois à la même date, ou le jour de bourse suivant.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Chaque achat se fait à l\'ouverture du marché. Si tes liquidités ne '
        'suffisent pas ce jour-là, il est annulé.',
      ),
      findsOneWidget,
    );
    expect(button('Investir chaque mois'), findsOneWidget);
    expect(find.text('Argent fictif. Aucune transaction réelle.'), findsOne);

    await tester.tap(find.widgetWithText(ChunkyChip, '100$nbsp€'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '100'), findsOneWidget);
    expect(button('Investir 100,00$nbsp€ chaque mois'), findsOneWidget);

    await tester.tap(find.text('Chaque semaine'));
    await tester.pump();
    expect(
      find.text(
        'Puis chaque semaine le même jour, ou le jour de bourse suivant.',
      ),
      findsOneWidget,
    );
    await tester.tap(button('Investir 100,00$nbsp€ chaque semaine'));
    await tester.pumpAndSettle();

    final plan = setup.saved.single;
    expect((plan.amount, plan.frequency), (eur('100'), DcaFrequency.weekly));
    // The sheet closed on what it set up, with a way to the wallet.
    expect(find.byType(PlanSheet), findsNothing);
    expect(
      find.text('Versement programmé$nnbsp: premier achat le 9 octobre 2026.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Mon portefeuille'));
    await tester.pumpAndSettle();
    expect(find.text('wallet live'), findsOneWidget);
  });

  testWidgets('a wrong amount says why under the field, and waits', (
    tester,
  ) async {
    await show(tester, fixedFee: eur('1'));
    // Nothing typed: pressing shows what is missing.
    await tester.tap(button('Investir chaque mois'));
    await tester.pump();
    expect(find.text('Saisis un montant supérieur à zéro.'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(
      tester.widget<ChunkyButton>(button('Investir chaque mois')).onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), '1');
    await tester.pump();
    expect(
      find.text('Le montant doit dépasser les frais fixes (1,00$nbsp€).'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '200000');
    await tester.pump();
    expect(find.text('Au plus 100${nnbsp}000,00$nbsp€ par achat.'), findsOne);
    expect(setup.saved, isEmpty);
  });

  testWidgets('the simulator\'s amount and frequency, prefilled', (
    tester,
  ) async {
    await show(tester, amount: eur('125.50'), frequency: DcaFrequency.weekly);
    expect(find.widgetWithText(TextField, '125,5'), findsOneWidget);
    expect(button('Investir 125,50$nbsp€ chaque semaine'), findsOneWidget);
  });

  testWidgets('closing sets nothing up', (tester) async {
    await show(tester);
    await tester.tap(find.bySemanticsLabel('Fermer'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanSheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester);
    await expectAccessible(tester);
  });
}
