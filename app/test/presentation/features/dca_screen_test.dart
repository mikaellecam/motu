import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/dca/dca_simulator.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/glossary.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/dca_plans.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/dca_simulator.dart';
import 'package:finance_companion/domain/wallet/trip_start.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/dca/dca_screen.dart';
import 'package:finance_companion/presentation/features/dca/plan_sheet.dart';
import 'package:finance_companion/presentation/features/glossary/term_sheet.dart';
import 'package:finance_companion/core/widgets/chunky.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_plan_setup.dart';
import '../../helpers.dart';
import '../../fakes/lesson_pack.dart';

import 'package:finance_companion/data/content/pack_codec.dart';

const nnbsp = ' ';
const nbsp = ' ';

Decimal d(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(d(s), Currency.eur);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);

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

final params = DcaParams(
  assetId: 'apple',
  amount: eur('100'),
  frequency: DcaFrequency.monthly,
  start: day(2025, 10, 8),
);

InvestmentRun runOf(String invested, String finalValue, int buys) =>
    InvestmentRun(
      purchases: [
        for (var i = 0; i < buys; i++)
          Purchase(
            date: day(2025, 10 + i, 8),
            amount: eur('100'),
            fees: eur('0.15'),
            quantity: Quantity.whole(1),
            price: Price(d('100'), Currency.usd),
          ),
      ],
      invested: eur(invested),
      quantity: Quantity.whole(buys),
      finalValue: d(finalValue),
      series: [
        ValuePoint(day(2025, 10, 8), d('100'), eur('100')),
        ValuePoint(day(2025, 11, 10), d('210'), eur('200')),
        ValuePoint(day(2025, 12, 8), d(finalValue), eur(invested)),
      ],
    );

final result = DcaResult(
  params: params,
  asset: apple,
  end: day(2025, 12, 8),
  dca: runOf('300', '330', 3),
  lumpSum: runOf('300', '320', 1),
  livret: LivretRun(
    invested: eur('300'),
    uninvested: eur('0'),
    finalValue: d('301'),
    series: const [],
  ),
  insight: DcaCheapYear(2025, d('0.16')),
);

DcaFormView viewOf(DcaForm form, {List<ValidationFailure> errors = const []}) =>
    DcaFormView(
      form: form,
      assets: [
        apple,
        Asset(
          id: 'world',
          symbol: 'ACWI',
          name: 'ETF Monde',
          type: AssetType.etf,
          exchange: Exchange.nasdaq,
          currency: Currency.usd,
          region: 'world',
          listingDate: DateTime.utc(2008, 3, 28),
        ),
      ],
      years: form.date.isEmpty ? (form.years ?? 10) : null,
      start: StartOk(day(2016, 10, 10)),
      amountErrors: errors,
      params: errors.isEmpty ? params : null,
    );

const dcaTerm = GlossaryTerm(
  id: 'dca',
  title: Localized('Investissement programmé (DCA)', 'Dollar-cost averaging'),
  short: Localized('x', 'x'),
  body: Localized('x', 'x'),
);

late AppDatabase db;

Future<void> show(
  WidgetTester tester, {
  List<ValidationFailure> errors = const [],
}) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dcaFormViewProvider.overrideWith(
          (ref) async =>
              viewOf(ref.watch(dcaFormControllerProvider), errors: errors),
        ),
        dcaRunProvider.overrideWith((ref, p) async => result),
        planSetupProvider.overrideWith2(
          (_) => FakePlanSetup(planContext(apple)),
        ),
        // The companion's glossary link: no pack to download.
        contentPackProvider(actionsEtfIsland).overrideWith(
          (ref) async => const ContentPack(
            id: 'actions-etf',
            version: 1,
            title: Localized('Actions & ETF', 'Stocks & ETFs'),
            nodes: [],
            datasets: {},
            glossary: {'dca': dcaTerm},
          ),
        ),
        contentPackProvider(lesBasesIsland)
            .overrideWith((ref) async => decodePack(emptyBasesJson())),
        termSheetProvider.overrideWith(
          (ref, id) async => const TermSheetView(
            term: dcaTerm,
            related: [],
            firstOpen: true,
            terms: {},
          ),
        ),
      ],
      child: MainApp.screen(const DcaScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drift closes its watch queries on a timer once the tree is gone.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('« Simuler »: the result, the comparisons and the insight', (
    tester,
  ) async {
    await show(tester);
    expect(find.text("Et si j'avais investi…"), findsOneWidget);
    // The world ETF by default.
    expect(find.text('ETF Monde'), findsOneWidget);
    expect(find.widgetWithText(ChunkyChip, '10 ans'), findsOneWidget);
    expect(
      tester
          .widget<ChunkyChip>(find.widgetWithText(ChunkyChip, '10 ans'))
          .selected,
      isTrue,
    );

    await tester.tap(find.text('Simuler'));
    await tester.pumpAndSettle();
    // The hero: what went in, what it would be worth, the signed gain.
    expect(find.text('Résultat, 3 achats'), findsOneWidget);
    expect(find.text('Apple, du 8 octobre 2025 au 8 décembre 2025'), findsOne);
    expect(find.text('Tu aurais versé'), findsOneWidget);
    expect(find.text('Ça vaudrait'), findsOneWidget);
    expect(find.text('300$nbsp€'), findsOneWidget);
    expect(find.text('330$nbsp€'), findsNWidgets(2));
    final gain = find.text('+30$nbsp€ (+10,00$nnbsp%)');
    expect(gain, findsOneWidget);
    expect(tester.widget<Text>(gain).style?.color, AppColors.gain);
    // The chart: its legend, and dated.
    expect(find.text('Valeur de ton placement'), findsOneWidget);
    expect(find.text('Argent versé'), findsOneWidget);
    expect(find.text('10 nov.'), findsOneWidget);
    // The comparisons.
    expect(find.text('Avec la même somme'), findsOneWidget);
    expect(find.text('+10,00$nnbsp%'), findsOneWidget);
    expect(find.text('Tout placé le premier jour'), findsOneWidget);
    expect(find.text('Sur un Livret A'), findsOneWidget);
    // The companion, with the glossary's DCA.
    expect(find.text('Ton compagnon'), findsOneWidget);
    expect(
      find.text(
        'Tes achats de 2025 se sont faits à prix cassés$nnbsp: en moyenne '
        '16,00$nnbsp% sous le dernier cours. Avec la même somme à chaque '
        'fois, tu as acheté plus de parts quand le prix était bas.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Investissement programmé (DCA)'));
    await tester.pumpAndSettle();
    expect(find.byType(TermSheet), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('« Le mettre en place »: the same plan, in the live wallet', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Simuler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Le mettre en place'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<PlanSheet>(find.byType(PlanSheet));
    expect(
      (sheet.assetId, sheet.walletId, sheet.amount, sheet.frequency),
      ('apple', 'live', eur('100'), DcaFrequency.monthly),
    );
    expect(
      find.widgetWithText(ChunkyButton, 'Investir 100,00$nbsp€ chaque mois'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('a wrong amount says why, and nothing runs', (tester) async {
    await show(
      tester,
      errors: [
        ValidationFailure('amount_too_large', {'max': maxDcaAmount}),
      ],
    );
    expect(
      find.text('Au plus 100${nnbsp}000,00$nbsp€ par achat.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Simuler'));
    await tester.pumpAndSettle();
    expect(find.text('Tu aurais versé'), findsNothing);
  });

  testWidgets('saved, listed, and run again from the list', (tester) async {
    await show(tester);
    await tester.tap(find.text('Simuler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Simulation enregistrée.'), findsOneWidget);
    expect(find.text('Tes simulations'), findsOneWidget);
    expect(
      find.textContaining('100,00$nbsp€ par mois depuis le 8 octobre 2025'),
      findsOneWidget,
    );

    // The message gone, the row is free to tap.
    ScaffoldMessenger.of(tester.element(find.byType(DcaScreen)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    // The list sits under the result.
    await tester.ensureVisible(find.text('Relancer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relancer'));
    await tester.pumpAndSettle();
    // Back in the form, with its date.
    await tester.scrollUntilVisible(
      find.text('08/10/2025'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('08/10/2025'), findsOneWidget);
    expect(find.textContaining('3 achats'), findsOneWidget);
  });

  testWidgets('accessible, with text at 130 %, form and result', (
    tester,
  ) async {
    textAt(tester, 1.3);
    await show(tester);
    await tester.tap(find.text('Simuler'));
    await tester.pumpAndSettle();
    expect(find.text('Tu aurais versé'), findsOneWidget);
    await expectAccessible(tester);
  });
}
