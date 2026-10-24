import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/asset/asset_page.dart';
import 'package:finance_companion/application/companion/companion.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/l10n/formats.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/analytics/drawdown.dart';
import 'package:finance_companion/domain/analytics/stability.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/market/quote.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/asset/asset_screen.dart';
import 'package:finance_companion/presentation/features/asset/stability_card.dart';
import 'package:finance_companion/presentation/features/glossary/term_sheet.dart';
import 'package:finance_companion/presentation/features/order/order_sheet.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);
const nnbsp = ' ';
const nbsp = ' ';
const minus = '−';

final apple = Asset(
  id: 'apple',
  symbol: 'AAPL',
  name: 'Apple',
  type: AssetType.stock,
  exchange: Exchange.nasdaq,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(1980),
);

List<PriceBar> bars(Decimal Function(DateTime) close) => [
  for (
    var t = day(2021, 9, 1);
    !t.isAfter(day(2026, 10, 7));
    t = t.add(const Duration(days: 1))
  )
    if (t.weekday <= 5)
      PriceBar(
        date: t,
        open: close(t),
        high: close(t),
        low: close(t),
        close: close(t),
        volume: 1,
        currency: Currency.usd,
      ),
];

Fill buy(DateTime date, String qty, String price, String rate) => Fill(
  assetId: 'apple',
  side: Side.buy,
  date: date,
  quantity: Quantity.truncate(d(qty)),
  price: Price(d(price), Currency.usd),
  fxRate: d(rate),
  fees: const Money.zero(Currency.eur),
);

AssetOverview overview({
  int level = 1,
  bool held = true,
  WalletStatus status = WalletStatus.active,
}) {
  final fills = [
    if (held) buy(day(2026, 3, 2), '10', '100', '0.9'),
    if (held) buy(day(2026, 6, 1), '5', '120', '0.85'),
  ];
  return buildAssetOverview(
    asset: apple,
    wallet: WalletState(
      id: 'live',
      kind: WalletKind.live,
      name: 'live',
      startDate: day(2026, 1, 1),
      simDate: null,
      status: status,
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: Decimal.zero,
          fixedFee: const Money.zero(Currency.eur),
          fractionalShares: true,
        ),
        monthlyContribution: const Money.zero(Currency.eur),
        stops: const StopConditions(),
      ),
      cash: const Money.zero(Currency.eur),
      fills: fills,
      positions: positionsFrom(fills),
      pendingOrders: const [],
      values: const [],
      livretMovements: const [],
      plans: const [],
    ),
    asOf: DateTime.utc(2026, 10, 8, 15),
    bars: bars(
      (t) => t.year < 2026
          ? d('100')
          : t.month == 5
          ? d('120')
          : d('150'),
    ),
    benchmark: bars((t) => t.year < 2026 ? d('50') : d('55')),
    quote: Quote(
      Price(d('200'), Currency.usd),
      DateTime.utc(2026, 10, 8, 14, 45),
      marketOpen: true,
    ),
    closeObservedAt: null,
    fx: (t) => t.year < 2026 ? d('0.9') : d('0.85'),
    uiLevel: level,
  );
}

Future<void> show(WidgetTester tester, AssetOverview o) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  // Tall enough for every section, the position last.
  tester.view.physicalSize = const Size(1170, 7200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
        assetOverviewProvider.overrideWith((ref, args) async => o),
        // The companion card has its own tests.
        walletMomentProvider.overrideWith((ref, args) async => null),
        assetChartProvider.overrideWith((ref, args) async {
          final (_, _, period, benchmark) = args;
          return assetChartFor(o, period, benchmark: benchmark);
        }),
      ],
      child: MainApp(
        router: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const AssetScreen(assetId: 'apple'),
            ),
            GoRoute(
              path: '/wallet/:walletId/order/:orderId',
              builder: (_, state) => Text(
                'order ${state.pathParameters['walletId']}/'
                '${state.pathParameters['orderId']}',
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('header: listing, price, euros, session, timestamp', (
    tester,
  ) async {
    await show(tester, overview());
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('AAPL · Nasdaq · coté en dollars US'), findsOneWidget);
    expect(find.text('200,00$nbsp\$'), findsOneWidget);
    expect(find.text('≈ 170,00$nbsp€'), findsOneWidget);
    expect(find.text('+33,33$nnbsp% sur la dernière séance'), findsOneWidget);
    expect(find.textContaining('Cours du '), findsOneWidget);
  });

  testWidgets('chart: buys, worst drop, the world ETF on demand, periods', (
    tester,
  ) async {
    await show(tester, overview());
    expect(find.text('Tes achats'), findsOneWidget);
    expect(
      find.text('Pire baisse$nnbsp: ${minus}20,00$nnbsp%'),
      findsOneWidget,
    );
    String chartLabel() => tester
        .widget<Semantics>(
          find
              .ancestor(
                of: find.byType(LineChart),
                matching: find.byType(Semantics),
              )
              .first,
        )
        .properties
        .label!;
    expect(
      chartLabel(),
      "Cours d'Apple sur 1 an$nnbsp: de 100,00$nbsp\$ à 150,00$nbsp\$.",
    );
    expect(find.text('ETF Monde'), findsOneWidget, reason: 'the chip only');
    await tester.tap(find.widgetWithText(FilterChip, 'ETF Monde'));
    await tester.pumpAndSettle();
    expect(find.text('ETF Monde'), findsNWidgets(2));

    await tester.tap(find.text('5A'));
    await tester.pumpAndSettle();
    expect(chartLabel(), contains('sur 5 ans'));
  });

  testWidgets('why it moved, over the chart period', (tester) async {
    await show(tester, overview());
    expect(find.text('Pourquoi ça bouge$nnbsp?'), findsOneWidget);
    expect(find.text('+88,89$nnbsp% en euros sur 1 an'), findsOneWidget);
    expect(find.text('Le marché mondial'), findsOneWidget);
    expect(find.text('+10,00$nnbsp%'), findsOneWidget);
    expect(find.text('Le dollar'), findsOneWidget);
    expect(find.text('${minus}5,56$nnbsp%'), findsOneWidget);
    expect(find.text('Le reste, propre à Apple'), findsOneWidget);
  });

  testWidgets('essentials: level 1 shows the band, level 2 the figure too', (
    tester,
  ) async {
    final o = overview();
    expect(o.riskBand, 5);
    await show(tester, o);
    expect(find.text('Performance sur 1 an'), findsOneWidget);
    expect(find.text('+100,00$nnbsp%'), findsOneWidget);
    expect(find.text('Volatilité'), findsOneWidget);
    expect(find.text('Très élevée'), findsOneWidget);
    expect(find.text('${minus}20,00$nnbsp% sur 1 an'), findsOneWidget);
    expect(find.text('Risque de change'), findsOneWidget);
    expect(
      find.text('Dollar US · ${minus}5,56$nnbsp% sur 1 an'),
      findsOneWidget,
    );
  });

  testWidgets('each essentials tile opens its term, about this asset', (
    tester,
  ) async {
    await show(tester, overview());
    for (final (tile, term) in [
      ('Volatilité', 'volatilite'),
      ('Risque de change', 'risque-de-change'),
    ]) {
      await tester.tap(find.text(tile));
      // The sheet loads its term: frames, not settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final sheet = tester.widget<TermSheet>(find.byType(TermSheet));
      expect((sheet.termId, sheet.assetId), (term, overview().asset.id));
      Navigator.of(tester.element(find.byType(TermSheet))).pop();
      await tester.pump(const Duration(milliseconds: 400));
    }
  });

  testWidgets('« Acheter · Vendre »: Vendre only with a position', (
    tester,
  ) async {
    await show(tester, overview());
    expect(find.widgetWithText(FilledButton, 'Acheter'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Vendre'), findsOneWidget);
  });

  testWidgets('no position: « Acheter » alone', (tester) async {
    await show(tester, overview(held: false));
    expect(find.widgetWithText(FilledButton, 'Acheter'), findsOneWidget);
    expect(find.text('Vendre'), findsNothing);
  });

  testWidgets('a finished trip takes no order', (tester) async {
    await show(tester, overview(status: WalletStatus.finished));
    expect(find.text('Acheter'), findsNothing);
  });

  testWidgets('« Acheter » opens the order sheet', (tester) async {
    await show(tester, overview());
    await tester.tap(find.widgetWithText(FilledButton, 'Acheter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final sheet = tester.widget<OrderSheet>(find.byType(OrderSheet));
    expect(
      (sheet.assetId, sheet.walletId, sheet.side),
      ('apple', 'live', Side.buy),
    );
  });

  testWidgets('once placed: the message, and « Voir l\'ordre »', (
    tester,
  ) async {
    await show(tester, overview());
    await tester.tap(find.widgetWithText(FilledButton, 'Acheter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    Navigator.of(tester.element(find.byType(OrderSheet)))
        .pop((message: 'Ordre envoyé', orderId: 'o9'));
    await tester.pumpAndSettle();
    expect(find.text('Ordre envoyé'), findsOneWidget);
    await tester.tap(find.text('Voir l\'ordre'));
    await tester.pumpAndSettle();
    expect(find.text('order live/o9'), findsOneWidget);
  });

  testWidgets('level 2: the band and its figure', (tester) async {
    await show(tester, overview(level: 2));
    expect(find.textContaining('Très élevée · '), findsOneWidget);
  });

  testWidgets('position: value, unrealised gain, currency effect', (
    tester,
  ) async {
    await show(tester, overview());
    expect(find.text('Ta position'), findsOneWidget);
    expect(find.text('15 actions'), findsOneWidget);
    expect(find.text('2${nnbsp}550,00$nbsp€'), findsOneWidget);
    expect(find.text('+1${nnbsp}140,00$nbsp€ (+80,85$nnbsp%)'), findsOneWidget);
    expect(find.text('dont effet de change'), findsOneWidget);
    expect(find.text('${minus}93,75$nbsp€'), findsOneWidget);
  });

  testWidgets('« Stabilité passée »: the score, its parts, what it is not', (
    tester,
  ) async {
    await show(tester, overview());
    expect(find.text('Stabilité passée'), findsOneWidget);
    expect(find.text('35/100'), findsOneWidget);
    expect(
      find.text('Plus il est haut, moins le cours a bougé par le passé.'),
      findsOneWidget,
    );
    for (final (label, fact, points) in [
      ('Mouvements', 'Volatilité sur 1 an$nnbsp: Très élevée', '0/40'),
      ('Pire baisse', '${minus}20$nnbsp% entre janvier et mai 2026', '20/30'),
      (
        'Une entreprise ou un panier',
        'Action$nnbsp: une seule entreprise',
        '0/15',
      ),
      ("Durée de l'historique", '46 ans de cours, depuis 1980', '15/15'),
    ]) {
      final card = find.byType(StabilityCard);
      for (final text in [label, fact, points]) {
        expect(
          find.descendant(of: card, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
    }
    expect(
      find.text(
        'Ce score décrit les cinq dernières années. Il ne dit rien de '
        "l'avenir et ce n'est pas un conseil.",
      ),
      findsOneWidget,
    );
    // Between the essentials and the position.
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Stabilité passée'), greaterThan(top("L'essentiel")));
    expect(top('Stabilité passée'), lessThan(top('Ta position')));
  });

  testWidgets('« Stabilité passée » reads as one sentence', (tester) async {
    await show(tester, overview());
    expect(
      find.bySemanticsLabel(
        'Stabilité passée$nnbsp: 35 sur 100. '
        'Plus il est haut, moins le cours a bougé par le passé. '
        'Mouvements$nnbsp: 0 sur 40, Volatilité sur 1 an$nnbsp: Très élevée. '
        'Pire baisse$nnbsp: 20 sur 30, '
        '${minus}20$nnbsp% entre janvier et mai 2026. '
        'Une entreprise ou un panier$nnbsp: 0 sur 15, '
        'Action$nnbsp: une seule entreprise. '
        "Durée de l'historique$nnbsp: 15 sur 15, "
        '46 ans de cours, depuis 1980. '
        'Ce score décrit les cinq dernières années. Il ne dit rien de '
        "l'avenir et ce n'est pas un conseil.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('« Stabilité passée » at level 2: the volatility figure', (
    tester,
  ) async {
    final o = overview(level: 2);
    await show(tester, o);
    final figure = Formats('fr').percent(o.stability!.volatility, decimals: 0);
    expect(find.text('Volatilité sur 1 an$nnbsp: $figure'), findsOneWidget);
  });

  PastStability stability({required Drawdown fall, AssetType? type}) =>
      PastStability(
        movementPoints: 40,
        volatility: Decimal.zero,
        band: 1,
        fallPoints: 30,
        worstFall: fall,
        basketPoints: 15,
        type: type ?? AssetType.etf,
        historyPoints: 4,
        historyYears: 3,
        since: day(2023, 6, 1),
      );

  testWidgets('« Stabilité passée »: falls over one month, two years, none', (
    tester,
  ) async {
    for (final (fall, text) in [
      (
        Drawdown(
          d('-0.08'),
          peakDate: day(2020, 3, 2),
          troughDate: day(2020, 3, 23),
        ),
        '${minus}8$nnbsp% en mars 2020',
      ),
      (
        Drawdown(
          d('-0.34'),
          peakDate: day(2019, 12, 20),
          troughDate: day(2020, 3, 23),
        ),
        '${minus}34$nnbsp% entre décembre 2019 et mars 2020',
      ),
      (Drawdown(Decimal.zero), "Le cours n'a pas baissé"),
    ]) {
      await pumpApp(
        tester,
        StabilityCard(score: stability(fall: fall), uiLevel: 1),
      );
      expect(find.text(text), findsOneWidget);
    }
    expect(
      find.text('ETF$nnbsp: le risque est réparti sur un panier'),
      findsOneWidget,
    );
    expect(find.text('3 ans de cours, depuis 2023'), findsOneWidget);
    expect(find.text('89/100'), findsOneWidget);
  });

  testWidgets(
    '« Stabilité passée » under a year of closes: why there is none',
    (tester) async {
      await pumpApp(tester, const StabilityCard(score: null, uiLevel: 1));
      expect(find.text('Stabilité passée'), findsOneWidget);
      expect(
        find.text('Pas de score$nnbsp: il faut au moins un an de cours.'),
        findsOneWidget,
      );
      expect(find.textContaining('/100'), findsNothing);
    },
  );

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester, overview());
    expect(find.byType(StabilityCard), findsOneWidget, reason: 'laid out');
    await expectAccessible(tester);
  });
}
