import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/order/order_tracker.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/l10n/formats.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/order_matcher.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/order/order_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const nnbsp = '\u202f';
const nbsp = '\u00a0';

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

final sentAt = DateTime.utc(2026, 10, 7, 21);
final opensAt = DateTime.utc(2026, 10, 8, 13, 30);

Order market({DateTime? at}) => Order(
  id: 'o1',
  assetId: 'apple',
  side: Side.buy,
  type: OrderType.market,
  size: AmountSize(const Money(50000, Currency.eur)),
  createdAt: at ?? sentAt,
);

OrderView view(
  Order order, {
  OrderStatus status = OrderStatus.pending,
  CancelReason? reason,
  Fill? fill,
  bool trip = false,
  DateTime? opens,
  bool opened = false,
}) => OrderView(
  detail: OrderDetail(
    order: order,
    walletId: trip ? 'trip' : 'live',
    status: status,
    cancelReason: reason,
    fill: fill,
  ),
  asset: apple,
  trip: trip,
  opensAt: opens,
  opened: opened,
);

/// Serves [view]; « Annuler l'ordre » lands on [afterCancel].
class FakeTracker extends OrderTracker {
  FakeTracker(this.initial, {this.afterCancel});
  final OrderView initial;
  final OrderView? afterCancel;
  var cancels = 0;

  @override
  Future<OrderView> build(String orderId) async => initial;

  @override
  Future<void> cancel() async {
    cancels++;
    if (afterCancel case final v?) state = AsyncData(v);
  }
}

class FailingTracker extends OrderTracker {
  @override
  Future<OrderView> build(String orderId) =>
      Future.error(const NotFoundFailure());
}

Future<void> show(WidgetTester tester, OrderTracker tracker) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [orderTrackerProvider.overrideWith2((_) => tracker)],
      child: MainApp.screen(const OrderScreen(orderId: 'o1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final formats = Formats('fr');
  String at(DateTime t) =>
      'Le ${formats.date(t.toLocal())} à ${formats.time(t.toLocal())}';

  testWidgets('sent after the close: it waits for the market to open', (
    tester,
  ) async {
    await show(tester, FakeTracker(view(market(), opens: opensAt)));
    expect(find.text('Ton ordre'), findsOneWidget);
    expect(find.text('Achat · Apple'), findsOneWidget);
    expect(find.text('500,00$nbsp€ · Au marché'), findsOneWidget);
    expect(find.text('Envoyé'), findsOneWidget);
    expect(find.text(at(sentAt)), findsOneWidget);
    expect(find.text('Ouverture du marché'), findsOneWidget);
    expect(find.text(at(opensAt)), findsOneWidget);
    expect(find.text('Exécuté'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Fait\n')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^En cours\n')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^À venir\n')), findsOneWidget);
    expect(find.text('Annuler l\'ordre'), findsOneWidget);
  });

  testWidgets('once the market opened, the outcome comes after the close', (
    tester,
  ) async {
    await show(
      tester,
      FakeTracker(view(market(), opens: opensAt, opened: true)),
    );
    expect(
      find.text(
        'Le marché a ouvert$nnbsp: le résultat de l\'ordre apparaît après '
        'la clôture.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('^Fait\n')), findsNWidgets(2));
    expect(find.bySemanticsLabel(RegExp('^En cours\n')), findsOneWidget);
  });

  testWidgets('filled at the quote: sent, then executed with its fees', (
    tester,
  ) async {
    final placed = DateTime.utc(2026, 10, 7, 15);
    await show(
      tester,
      FakeTracker(
        view(
          market(at: placed),
          status: OrderStatus.filled,
          fill: Fill(
            orderId: 'o1',
            assetId: 'apple',
            side: Side.buy,
            date: DateTime.utc(2026, 10, 7),
            quantity: Quantity.whole(4),
            price: Price(Decimal.parse('125'), Currency.usd),
            fxRate: Decimal.parse('0.9'),
            fees: const Money(68, Currency.eur),
          ),
        ),
      ),
    );
    expect(find.text('Ouverture du marché'), findsNothing);
    expect(
      find.text(
        '4 actions à 125,00$nbsp\$, le ${formats.date(DateTime.utc(2026, 10, 7))}'
        '\nFrais$nnbsp: 0,68$nbsp€',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('^Fait\n')), findsNWidgets(2));
    expect(find.text('Annuler l\'ordre'), findsNothing);
  });

  testWidgets('a trip limit order the matcher cancelled says why', (
    tester,
  ) async {
    final limit = Order(
      id: 'o1',
      assetId: 'apple',
      side: Side.sell,
      type: OrderType.limit,
      size: QuantitySize(Quantity.whole(3)),
      limitPrice: Price(Decimal.parse('130'), Currency.usd),
      createdAt: DateTime.utc(2008, 9, 15),
    );
    await show(
      tester,
      FakeTracker(
        view(
          limit,
          trip: true,
          status: OrderStatus.cancelled,
          reason: CancelReason.insufficientQuantity,
        ),
      ),
    );
    expect(find.text('Vente · Apple'), findsOneWidget);
    expect(find.text('3 actions · À cours limité'), findsOneWidget);
    expect(
      find.text('Le ${formats.date(DateTime.utc(2008, 9, 15))}'),
      findsOneWidget,
    );
    expect(find.text('En attente du cours'), findsOneWidget);
    expect(
      find.text('S\'exécute quand le cours monte à 130,00$nbsp\$ ou plus.'),
      findsOneWidget,
    );
    expect(find.text('Annulé'), findsOneWidget);
    expect(
      find.text(
        'Tu ne détenais plus assez de parts quand il s\'est déclenché.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('^Fait\n')), findsNWidgets(3));
  });

  testWidgets('a trip market order goes when the trip moves on', (
    tester,
  ) async {
    await show(tester, FakeTracker(view(market(), trip: true)));
    expect(find.text('Prochain jour de cotation du voyage'), findsOneWidget);
    expect(find.text('Il part quand le voyage avance.'), findsOneWidget);
  });

  testWidgets('« Annuler l\'ordre » asks first, then cancels', (tester) async {
    final tracker = FakeTracker(
      view(market(), opens: opensAt),
      afterCancel: view(
        market(),
        opens: opensAt,
        status: OrderStatus.cancelled,
        reason: CancelReason.byUser,
      ),
    );
    await show(tester, tracker);

    await tester.tap(find.text('Annuler l\'ordre'));
    await tester.pumpAndSettle();
    expect(find.text('Annuler cet ordre$nnbsp?'), findsOneWidget);
    await tester.tap(find.text('Garder l\'ordre'));
    await tester.pumpAndSettle();
    expect(tracker.cancels, 0);

    await tester.tap(find.text('Annuler l\'ordre'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Annuler l\'ordre'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tracker.cancels, 1);
    expect(find.text('Annulé'), findsOneWidget);
    expect(find.text('Tu l\'as annulé.'), findsOneWidget);
    // Cancelled before the open: that step was never reached.
    expect(find.bySemanticsLabel(RegExp('^À venir\n')), findsOneWidget);
    expect(find.text('Annuler l\'ordre'), findsNothing);
  });

  testWidgets('an unknown order offers a retry', (tester) async {
    await show(tester, FailingTracker());
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester, FakeTracker(view(market(), opens: opensAt)));
    await expectAccessible(tester);
  });
}
