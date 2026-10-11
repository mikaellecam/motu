import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/live_catch_up.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/l10n/formats.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/wallet/wallet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(d(s), Currency.eur);
DateTime day(int m, int dd) => DateTime.utc(2026, m, dd);
const nnbsp = ' ';
const nbsp = ' ';

Asset stock(String id, String name) => Asset(
  id: id,
  symbol: id.toUpperCase(),
  name: name,
  type: AssetType.stock,
  exchange: Exchange.nasdaq,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(1990),
);

Fill buy(String id, String qty, String price) => Fill(
  assetId: id,
  side: Side.buy,
  date: day(10, 1),
  quantity: Quantity.truncate(d(qty)),
  price: Price(d(price), Currency.usd),
  fxRate: d('0.9'),
  fees: eur('0'),
);

final observed = DateTime.utc(2026, 10, 8, 14, 45);

WalletOverview overview({
  List<Fill> fills = const [],
  Money? cash,
  List<Order> pending = const [],
}) {
  final assets = {
    'apple': stock('apple', 'Apple'),
    'nvidia': stock('nvidia', 'Nvidia'),
  };
  return buildOverview(
    wallet: WalletState(
      id: 'live',
      kind: WalletKind.live,
      name: 'live',
      startDate: day(10, 1),
      simDate: null,
      status: WalletStatus.active,
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: d('0.0015'),
          fixedFee: eur('0'),
          fractionalShares: true,
        ),
        monthlyContribution: eur('0'),
        stops: const StopConditions(),
      ),
      cash: cash ?? eur('50000'),
      fills: fills,
      positions: positionsFrom(fills),
      pendingOrders: pending,
      values: [
        DailyValue(date: day(10, 1), value: eur('50000'), flow: eur('50000')),
        if (fills.isNotEmpty)
          DailyValue(date: day(10, 7), value: eur('50100'), flow: eur('0')),
      ],
      livretMovements: const [],
      plans: const [],
    ),
    asOf: DateTime.utc(2026, 10, 8, 15, 30),
    assets: assets,
    prices: {
      for (final (id, price) in [('apple', '220'), ('nvidia', '150')])
        id: ObservedPrice(
          PriceAsOf(Price(d(price), Currency.usd), day(10, 8), stale: false),
          observed,
        ),
    },
    fxRates: {Currency.usd: d('0.85')},
    livret: Decimal.zero,
  );
}

/// Counts the catch-ups asked for.
class FakeCatchUp extends LiveCatchUp {
  var runs = 0;

  @override
  FutureOr<TripAdvance?> build() => null;

  @override
  Future<void> run() async => runs++;
}

late FakeCatchUp catchUp;

Future<void> show(
  WidgetTester tester,
  Future<WalletOverview> Function() o,
) async {
  catchUp = FakeCatchUp();
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
        walletOverviewProvider.overrideWith((ref, id) => o()),
        liveCatchUpProvider.overrideWith(() => catchUp),
        walletChartProvider.overrideWith((ref, args) async {
          final (_, period, benchmark) = args;
          final series = (await o()).series;
          return chartFor(
            series,
            period,
            benchmark: benchmark == null
                ? null
                : [ValuePoint(day(10, 1), d('49900'), eur('50000'))],
          );
        }),
      ],
      child: MainApp(
        router: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const WalletScreen(walletId: 'live'),
            ),
            GoRoute(
              path: '/wallet/:walletId/order/:orderId',
              builder: (_, state) =>
                  Text('order ${state.pathParameters['orderId']}'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final invested = [buy('apple', '10', '200'), buy('nvidia', '2', '100')];

  testWidgets('header, tiles, allocation and positions', (tester) async {
    await show(
      tester,
      () async => overview(fills: invested, cash: eur('48020')),
    );
    final local = observed.toLocal();
    final formats = Formats('fr');

    expect(find.text('Mon portefeuille'), findsOneWidget);
    expect(find.text('50${nnbsp}145,00$nbsp€'), findsOneWidget);
    expect(
      find.text('+145,00$nbsp€ (+0,29$nnbsp%) depuis le début'),
      findsOneWidget,
    );
    expect(
      find.text('Cours du ${formats.date(local)}, ${formats.time(local)}'),
      findsOneWidget,
    );
    expect(find.text('Investi'), findsOneWidget);
    expect(find.text('2${nnbsp}125,00$nbsp€'), findsOneWidget);
    expect(find.text('Liquidités disponibles'), findsOneWidget);
    expect(find.text('48${nnbsp}020,00$nbsp€'), findsOneWidget);
    expect(find.text('Investir'), findsOneWidget);

    expect(find.text('Répartition'), findsOneWidget);
    expect(find.text('Liquidités'), findsOneWidget);
    expect(find.text('3,73$nnbsp%'), findsOneWidget); // Apple 1 870 / 50 145

    // Apple: 10 shares worth 1 870 € for 1 800 € paid; Nvidia 1,5 rule.
    expect(find.text('Apple'), findsNWidgets(2));
    expect(find.text('10 actions'), findsOneWidget);
    expect(find.text('2 actions'), findsOneWidget);
    expect(find.text('1${nnbsp}870,00$nbsp€'), findsOneWidget);
    expect(find.text('+3,89$nnbsp%'), findsOneWidget);
    expect(find.text('+41,67$nnbsp%'), findsOneWidget); // Nvidia 255 / 180
  });

  testWidgets('the chart: periods, money put in, a benchmark on demand', (
    tester,
  ) async {
    await show(
      tester,
      () async => overview(fills: invested, cash: eur('48020')),
    );
    expect(find.text('Argent versé'), findsOneWidget);
    expect(find.text('ETF Monde'), findsOneWidget, reason: 'the chip only');
    expect(
      find.bySemanticsLabel(
        RegExp('^Valeur du portefeuille sur toute la période'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilterChip, 'ETF Monde'));
    await tester.pumpAndSettle();
    expect(find.text('ETF Monde'), findsNWidgets(2), reason: 'chip + legend');
    await tester.tap(find.widgetWithText(FilterChip, 'ETF Monde'));
    await tester.pumpAndSettle();
    expect(find.text('ETF Monde'), findsOneWidget);

    await tester.tap(find.text('1S'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('^Valeur du portefeuille sur 1 semaine')),
      findsOneWidget,
    );
  });

  testWidgets('a new wallet: no positions, the chart starts today', (
    tester,
  ) async {
    await show(tester, () async => overview());
    expect(find.text('Aucune position pour l\'instant.'), findsOneWidget);
    expect(find.textContaining('La courbe démarre le'), findsNothing);
    expect(
      find.text('0,00$nbsp€ (0,00$nnbsp%) depuis le début'),
      findsOneWidget,
    );
    expect(find.textContaining('Cours du'), findsNothing);
  });

  testWidgets('pending orders: each opens its order screen', (tester) async {
    await show(
      tester,
      () async => overview(
        pending: [
          Order(
            id: 'o1',
            assetId: 'nvidia',
            side: Side.buy,
            type: OrderType.limit,
            size: QuantitySize(Quantity.whole(3)),
            limitPrice: Price(d('140'), Currency.usd),
            createdAt: day(10, 7),
          ),
        ],
      ),
    );
    expect(find.text('Ordres en attente'), findsOneWidget);
    expect(find.text('Achat · Nvidia'), findsOneWidget);
    expect(find.text('3 actions · À cours limité'), findsOneWidget);
    await tester.tap(find.text('Achat · Nvidia'));
    await tester.pumpAndSettle();
    expect(find.text('order o1'), findsOneWidget);
  });

  testWidgets('no pending order, no card', (tester) async {
    await show(tester, () async => overview());
    expect(find.text('Ordres en attente'), findsNothing);
  });

  testWidgets('pulling to refresh catches the live wallet up first', (
    tester,
  ) async {
    await show(tester, () async => overview());
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(catchUp.runs, 1);
  });

  testWidgets('an error offers a retry', (tester) async {
    await show(tester, () => Future.error(const NetworkFailure()));
    expect(
      find.text('Impossible de joindre le serveur. Vérifie ta connexion.'),
      findsOneWidget,
    );
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
