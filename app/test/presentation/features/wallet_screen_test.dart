import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/companion/companion.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/dca_plans.dart';
import 'package:finance_companion/application/wallet/live_catch_up.dart';
import 'package:finance_companion/application/wallet/livret_line.dart';
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
import 'package:finance_companion/presentation/features/wallet/wallet_island_band.dart';
import 'package:finance_companion/presentation/features/wallet/wallet_screen.dart';
import 'package:finance_companion/core/widgets/chunky.dart';
import 'package:finance_companion/presentation/features/map/living_island.dart';
import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../fakes/no_lessons.dart';
import '../../helpers.dart';

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
  List<PlanView> plans = const [],
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
    plans: plans,
  );
}

/// « Arrêter » only records.
class FakePlanActions extends PlanActions {
  final stopped = <String>[];

  @override
  Future<void> stop(String planId) async => stopped.add(planId);
}

late FakePlanActions planActions;

/// Counts the catch-ups asked for.
class FakeCatchUp extends LiveCatchUp {
  var runs = 0;

  @override
  FutureOr<TripAdvance?> build() => null;

  @override
  Future<bool> run() async {
    runs++;
    return true;
  }
}

late FakeCatchUp catchUp;

Future<void> show(
  WidgetTester tester,
  Future<WalletOverview> Function() o,
) async {
  catchUp = FakeCatchUp();
  planActions = FakePlanActions();
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The Livret and companion cards have their own tests.
        livretLineProvider.overrideWith(
          (ref, id) async => throw const NotFoundFailure(),
        ),
        walletMomentProvider.overrideWith((ref, args) async => null),
        cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
        walletOverviewProvider.overrideWith((ref, id) => o()),
        // No lesson done: the wallet's island stands all grown (M13-1).
        islandPathProvider(actionsEtfIsland)
            .overrideWith((ref) async => noLessonsDone),
        liveCatchUpProvider.overrideWith(() => catchUp),
        planActionsProvider.overrideWith2((_) => planActions),
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
            GoRoute(
              path: '/asset/:id',
              builder: (_, state) => Text(
                'asset ${state.pathParameters['id']} '
                '${state.uri.queryParameters['wallet']}',
              ),
            ),
            GoRoute(
              path: '/explore',
              builder: (_, state) =>
                  Text('explore ${state.uri.queryParameters['wallet']}'),
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

    await tester.tap(find.widgetWithText(ChunkyChip, 'ETF Monde'));
    await tester.pumpAndSettle();
    expect(find.text('ETF Monde'), findsNWidgets(2), reason: 'chip + legend');
    await tester.tap(find.widgetWithText(ChunkyChip, 'ETF Monde'));
    await tester.pumpAndSettle();
    expect(find.text('ETF Monde'), findsOneWidget);

    await tester.tap(find.text('1S'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('^Valeur du portefeuille sur 1 semaine')),
      findsOneWidget,
    );
  });

  testWidgets('the chart\'s dates stay inside its card; the compare chips '
      'share one row, at 390 px and at 130 % text (M13-20)', (tester) async {
    for (final scale in [1.0, 1.3]) {
      textAt(tester, scale);
      await show(
        tester,
        () async => overview(fills: invested, cash: eur('48020')),
      );
      final chart = find.byType(LineChart);
      final card = tester.getRect(
        find.ancestor(of: chart, matching: find.byType(Card)).first,
      );
      final dates = find.descendant(of: chart, matching: find.byType(Text));
      expect(dates, findsWidgets);
      for (final date in dates.evaluate()) {
        final rect = tester.getRect(find.byWidget(date.widget));
        expect(rect.left, greaterThanOrEqualTo(card.left), reason: '$scale');
        expect(rect.right, lessThanOrEqualTo(card.right), reason: '$scale');
      }
      final world = tester.getRect(
        find.widgetWithText(ChunkyChip, 'ETF Monde'),
      );
      final livret = tester.getRect(
        find.widgetWithText(ChunkyChip, 'Livret A'),
      );
      expect(livret.top, world.top, reason: 'one row at $scale');
      expect(livret.right, lessThanOrEqualTo(card.right), reason: '$scale');
    }
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

  testWidgets('the island: a building per position, each opens its asset '
      '(M11-4)', (tester) async {
    await show(
      tester,
      () async => overview(fills: invested, cash: eur('48020')),
    );
    expect(
      find.text('Touche un immeuble pour ouvrir sa ligne'),
      findsOneWidget,
    );
    expect(find.byType(BarePlot), findsNothing);
    for (final name in ['Apple', 'Nvidia']) {
      final building = find.bySemanticsLabel(name);
      expect(building, findsOneWidget, reason: name);
      expect(
        tester.getSemantics(building),
        matchesSemantics(label: name, isButton: true, hasTapAction: true),
        reason: name,
      );
      // On screen, zoomed with the island.
      final size = tester.getRect(building).size;
      expect(size.width, greaterThanOrEqualTo(44), reason: name);
      expect(size.height, greaterThanOrEqualTo(44), reason: name);
    }
    // All grown, though no lesson is done (M13-1); its buildings follow
    // the wallet in stages (BRIEF §10.5).
    expect(find.byType(StagedIsland), findsOneWidget);
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<ArchipelagoPainter>()
        .single;
    expect(painter.grown, 1);
    expect(painter.buildings, hasLength(2));
    await tester.tap(find.bySemanticsLabel('Nvidia'));
    await tester.pumpAndSettle();
    expect(find.text('asset nvidia live'), findsOneWidget);
  });

  testWidgets('before the first buy: the bare island, a plot, and the way '
      'to the assets (M11-4)', (tester) async {
    await show(tester, () async => overview());
    expect(find.text('Ton île attend son premier immeuble'), findsOneWidget);
    expect(find.byType(BarePlot), findsOneWidget);
    expect(
      find.text('Ton premier achat posera la première pierre de ton île.'),
      findsOneWidget,
    );
    final explore = find.widgetWithText(ChunkyButton, 'Explorer les actifs');
    await tester.ensureVisible(explore);
    await tester.pumpAndSettle();
    await tester.tap(explore);
    await tester.pumpAndSettle();
    expect(find.text('explore live'), findsOneWidget);
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

  PlanView plan(String id, String asset, String amount, DcaFrequency f) =>
      PlanView(
        plan: DcaPlan(
          id: id,
          assetId: asset,
          amount: eur(amount),
          frequency: f,
          start: day(10, 9),
        ),
        asset: stock(asset, asset == 'apple' ? 'Apple' : 'Nvidia'),
        next: f == DcaFrequency.weekly ? day(10, 16) : day(11, 9),
      );

  testWidgets('« Versements programmés »: each plan, its next purchase, and '
      '« Arrêter » once confirmed', (tester) async {
    await show(
      tester,
      () async => overview(
        plans: [
          plan('live-1', 'apple', '100', DcaFrequency.monthly),
          plan('live-2', 'nvidia', '25.5', DcaFrequency.weekly),
        ],
      ),
    );
    expect(find.text('Versements programmés'), findsOneWidget);
    expect(find.text('100,00$nbsp€ chaque mois'), findsOneWidget);
    expect(find.text('Prochain achat$nnbsp: le 9 novembre'), findsOne);
    expect(find.text('25,50$nbsp€ chaque semaine'), findsOneWidget);
    expect(find.text('Prochain achat$nnbsp: le 16 octobre'), findsOne);

    // Kept: nothing changes.
    await tester.tap(find.widgetWithText(TextButton, 'Arrêter').last);
    await tester.pumpAndSettle();
    expect(find.text('Arrêter ce versement$nnbsp?'), findsOneWidget);
    expect(
      find.text(
        'Les prochains achats de Nvidia n\'auront pas lieu. Ceux déjà faits '
        'restent dans ton portefeuille.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Garder le versement'));
    await tester.pumpAndSettle();
    expect(planActions.stopped, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Arrêter').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChunkyButton, 'Arrêter'));
    await tester.pumpAndSettle();
    expect(planActions.stopped, ['live-2']);
  });

  testWidgets('no plan, no section', (tester) async {
    await show(tester, () async => overview());
    expect(find.text('Versements programmés'), findsNothing);
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

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(
      tester,
      () async => overview(
        fills: invested,
        cash: eur('48020'),
        plans: [plan('live-1', 'apple', '100', DcaFrequency.monthly)],
      ),
    );
    await expectAccessible(tester);
  });
}
