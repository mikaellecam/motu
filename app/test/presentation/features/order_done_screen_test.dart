import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/order/order_ticket.dart';
import 'package:finance_companion/application/order/order_tracker.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/core/l10n/formats.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:finance_companion/domain/learning/path.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/node/mission_player.dart';
import 'package:finance_companion/presentation/features/order/order_done_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';

const nnbsp = ' ';

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

final opensAt = DateTime.utc(2026, 10, 8, 13, 30);

Order buy({OrderType type = OrderType.market}) => Order(
  id: 'o1',
  assetId: 'apple',
  side: Side.buy,
  type: type,
  size: AmountSize(const Money(50000, Currency.eur)),
  limitPrice: type == OrderType.limit
      ? Price(Decimal.fromInt(150), Currency.usd)
      : null,
  createdAt: DateTime.utc(2026, 10, 7, 21),
);

final fill = Fill(
  orderId: 'o1',
  assetId: 'apple',
  side: Side.buy,
  date: DateTime.utc(2026, 10, 7),
  quantity: Quantity.whole(2),
  price: Price(Decimal.parse('101.5'), Currency.usd),
  fxRate: Decimal.parse('0.8547'),
  fees: const Money.zero(Currency.eur),
);

OrderView view({Order? order, bool filled = false, DateTime? opens}) =>
    OrderView(
      detail: OrderDetail(
        order: order ?? buy(),
        walletId: 'live',
        status: filled ? OrderStatus.filled : OrderStatus.pending,
        fill: filled ? fill : null,
      ),
      asset: apple,
      trip: false,
      opensAt: opens,
    );

class FakeTracker extends OrderTracker {
  FakeTracker(this.view);
  final OrderView view;

  @override
  Future<OrderView> build(String orderId) async => view;
}

NodeContent node(String id, String title, NodeType type) => NodeContent(
  id: id,
  type: type,
  title: Localized(title, title),
  status: ContentStatus.published,
);

/// The first three lessons, the mission third.
final path = IslandPathView(const Localized('Actions & ETF', 'Stocks & ETFs'), [
  PathNode(
    node('ae.livret-vs-etf', 'Livret ou ETF ?', NodeType.predictReveal),
    NodeState.done,
  ),
  PathNode(
    node('ae.fees-toy', 'Le jouet des frais', NodeType.toy),
    NodeState.done,
  ),
  PathNode(
    node('ae.mission-first-etf', 'Ton premier ETF', NodeType.mission),
    NodeState.done,
  ),
]);

Future<void> show(WidgetTester tester, OrderDone done, OrderView view) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderTrackerProvider.overrideWith2((_) => FakeTracker(view)),
        walletIslandProvider.overrideWith(
          (ref, id) async => islandBuildings(
            held: const {},
            pending: {'apple': Decimal.fromInt(500)},
          ),
        ),
        islandPathProvider(actionsEtfIsland).overrideWith((ref) async => path),
      ],
      child: MainApp(
        router: GoRouter(
          initialLocation: '/done',
          routes: [
            GoRoute(
              path: '/done',
              builder: (_, _) => OrderDoneScreen(
                walletId: WalletRepository.liveWalletId,
                done: done,
              ),
            ),
            // Where the buttons lead, as the address they were sent to.
            GoRoute(path: '/', builder: (_, _) => const Text('map')),
            GoRoute(
              path: '/wallet/:walletId',
              builder: (_, state) =>
                  Text('wallet ${state.pathParameters['walletId']}'),
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
  final formats = Formats('fr');
  // Once the app has loaded its locale data.
  String day() => formats.date(opensAt.toLocal());
  String time() => formats.time(opensAt.toLocal());

  testWidgets('a buy waiting for the opening: its building in construction', (
    tester,
  ) async {
    await show(
      tester,
      OrderDone(
        OrderSent('o1', side: Side.buy, opensAt: opensAt),
        built: false,
      ),
      view(opens: opensAt),
    );
    expect(find.text('Ordre programmé'), findsOneWidget);
    expect(find.text('Ton immeuble Apple est en chantier'), findsOneWidget);
    expect(
      find.text(
        'Le Nasdaq est fermé. Ton ordre partira à l\'ouverture, '
        'le ${day()} à ${time()}.',
      ),
      findsOneWidget,
    );
    // Its steps, as on the order screen.
    for (final step in ['Envoyé', 'Ouverture du marché', 'Exécuté']) {
      expect(find.text(step), findsOneWidget, reason: step);
    }
    expect(find.bySemanticsLabel(RegExp('^Fait\n')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^En cours\n')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^À venir\n')), findsOneWidget);
    // No mission completed: no card.
    expect(find.byType(MissionCard), findsNothing);

    await tester.tap(find.text('Voir l\'ordre'));
    await tester.pumpAndSettle();
    expect(find.text('order live/o1'), findsOneWidget);
  });

  testWidgets('a buy filled at once: its building built, at what price', (
    tester,
  ) async {
    await show(
      tester,
      OrderDone(OrderExecuted('o1', fill), built: true),
      view(filled: true),
    );
    expect(find.text('Ordre exécuté'), findsOneWidget);
    expect(find.text('Ton immeuble Apple est construit'), findsOneWidget);
    expect(
      find.text(
        'Marché ouvert$nnbsp: ton achat est passé au dernier cours, à '
        '${formats.price(fill.price)}.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ouverture du marché'), findsNothing);
  });

  testWidgets('why it waits: offline, in a trip, for its price', (
    tester,
  ) async {
    final cases = [
      (
        OrderSent('o1', side: Side.buy, opensAt: opensAt, offline: true),
        () =>
            'Pas de cours à jour$nnbsp: ton ordre partira à la prochaine '
            'ouverture, le ${day()} à ${time()}.',
      ),
      (
        const OrderSent('o1', side: Side.buy, trip: true),
        () => 'Ton ordre partira au prochain jour de cotation du voyage.',
      ),
      (
        const OrderSent('o1', side: Side.buy),
        () => 'Ordre envoyé$nnbsp: il attend que le cours atteigne ton prix.',
      ),
    ];
    for (final (outcome, line) in cases) {
      await show(
        tester,
        OrderDone(outcome, built: false),
        view(order: buy(type: OrderType.limit)),
      );
      expect(find.text(line()), findsOneWidget, reason: line());
    }
  });

  testWidgets('the mission it completed, with its step on the island', (
    tester,
  ) async {
    await show(
      tester,
      OrderDone(
        OrderExecuted('o1', fill),
        built: true,
        missions: const ['ae.mission-first-etf'],
      ),
      view(filled: true),
    );
    expect(find.byType(MissionCard), findsOneWidget);
    expect(
      find.text('Mission accomplie$nnbsp: Ton premier ETF'),
      findsOneWidget,
    );
    expect(find.text('L\'étape 3 de l\'île est terminée'), findsOneWidget);
  });

  testWidgets('« Retour à l\'île » and « Mon portefeuille »', (tester) async {
    final done = OrderDone(
      OrderSent('o1', side: Side.buy, opensAt: opensAt),
      built: false,
    );
    await show(tester, done, view(opens: opensAt));
    await tester.tap(find.text('Retour à l\'île'));
    await tester.pumpAndSettle();
    expect(find.text('map'), findsOneWidget);

    await show(tester, done, view(opens: opensAt));
    await tester.tap(find.text('Mon portefeuille'));
    await tester.pumpAndSettle();
    expect(find.text('wallet live'), findsOneWidget);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(
      tester,
      OrderDone(
        OrderExecuted('o1', fill),
        built: true,
        missions: const ['ae.mission-first-etf'],
      ),
      view(filled: true),
    );
    await expectAccessible(tester);
  });
}
