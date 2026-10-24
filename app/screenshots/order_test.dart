import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/order/order_ticket.dart';
import 'package:finance_companion/application/order/order_tracker.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/presentation/features/order/order_screen.dart';
import 'package:finance_companion/presentation/features/order/order_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// The live wallet's 50 000 € of cash and Apple at its last close from the
// backfill (336,67 $ on 2026-10-07), the euro at 0,8547 $; Thursday morning,
// the Nasdaq still closed.

final _context = TicketContext(
  asset: Asset(
    id: 'apple',
    symbol: 'AAPL',
    name: 'Apple',
    type: AssetType.stock,
    exchange: Exchange.nasdaq,
    currency: Currency.usd,
    region: 'us',
    listingDate: DateTime.utc(1980, 12, 12),
  ),
  walletId: 'live',
  isTrip: false,
  finished: false,
  rules: TradingRules(
    fxFeeRate: Decimal.parse('0.0015'),
    fixedFee: const Money.zero(Currency.eur),
    fractionalShares: true,
  ),
  price: Price(Decimal.parse('336.67'), Currency.usd),
  fxRate: Decimal.parse('0.8547'),
  availableCash: const Money(5000000, Currency.eur),
  availableQuantity: const Quantity.zero(),
  positionValue: Decimal.zero,
  walletTotal: Decimal.fromInt(50000),
  threshold: Decimal.parse('0.40'),
  asOf: DateTime.utc(2026, 10, 8, 7),
  nextOpen: DateTime.utc(2026, 10, 8, 13, 30),
);

class _Ticket extends OrderTicket {
  _Ticket(this.context);
  final TicketContext context;

  @override
  Future<TicketState> build(String assetId, String walletId, Side side) async =>
      ticketState(context, TicketForm(side: side), orderId: 'o');
}

// Thursday 17:00 in Paris, the Nasdaq open but no connection: the order
// waits for Friday's open (BRIEF §14.1).
final _offline = TicketContext(
  asset: _context.asset,
  walletId: 'live',
  isTrip: false,
  finished: false,
  rules: _context.rules,
  price: _context.price,
  fxRate: _context.fxRate,
  availableCash: _context.availableCash,
  availableQuantity: _context.availableQuantity,
  positionValue: _context.positionValue,
  walletTotal: _context.walletTotal,
  threshold: _context.threshold,
  asOf: DateTime.utc(2026, 10, 8, 15),
  marketOpen: true,
  offline: true,
  nextOpen: DateTime.utc(2026, 10, 9, 13, 30),
);

class _Host extends StatelessWidget {
  const _Host();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showOrderSheet(
          context,
          assetId: 'apple',
          walletId: 'live',
          side: Side.buy,
        ),
        child: const SizedBox.square(dimension: 44),
      ),
    ),
  );
}

void main() {
  final overrides = [
    orderTicketProvider.overrideWith2((_) => _Ticket(_context)),
  ];

  Future<void> open(WidgetTester tester, String amount) async {
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), amount);
    await tester.pumpAndSettle();
  }

  screenshot(
    'm4-5-order-sheet',
    const _Host(),
    size: const Size(390, 900),
    overrides: overrides,
    act: (tester) => open(tester, '500'),
  );

  screenshot(
    'm4-5-order-coach',
    const _Host(),
    size: const Size(390, 900),
    overrides: overrides,
    act: (tester) => open(tester, '25000'),
  );

  // More than the 50 000 € of cash: the field says why, the button waits.
  screenshot(
    'm9-17-order-error',
    const _Host(),
    size: const Size(390, 900),
    overrides: overrides,
    act: (tester) => open(tester, '60000'),
  );

  screenshot(
    'm9-4-order-offline',
    const _Host(),
    size: const Size(390, 900),
    overrides: [orderTicketProvider.overrideWith2((_) => _Ticket(_offline))],
    act: (tester) => open(tester, '500'),
  );

  // The 500 € sent on Wednesday evening: waiting for Thursday's open, then
  // filled at its 336,40 $ open: 1,739002 share, 0,75 € of FX fee.
  final order = Order(
    id: 'o',
    assetId: 'apple',
    side: Side.buy,
    type: OrderType.market,
    size: AmountSize(const Money(50000, Currency.eur)),
    createdAt: DateTime.utc(2026, 10, 7, 21),
  );
  OrderView view({Fill? fill}) => OrderView(
    detail: OrderDetail(
      order: order,
      walletId: 'live',
      status: fill == null ? OrderStatus.pending : OrderStatus.filled,
      fill: fill,
    ),
    asset: _context.asset,
    trip: false,
    opensAt: DateTime.utc(2026, 10, 8, 13, 30),
    opened: fill != null,
  );

  screenshot(
    'm4-6-order-pending',
    const OrderScreen(orderId: 'o'),
    overrides: [orderTrackerProvider.overrideWith2((_) => _Tracker(view()))],
  );

  screenshot(
    'm4-6-order-filled',
    const OrderScreen(orderId: 'o'),
    overrides: [
      orderTrackerProvider.overrideWith2(
        (_) => _Tracker(
          view(
            fill: Fill(
              orderId: 'o',
              assetId: 'apple',
              side: Side.buy,
              date: DateTime.utc(2026, 10, 8),
              quantity: Quantity.truncate(Decimal.parse('1.739002')),
              price: Price(Decimal.parse('336.40'), Currency.usd),
              fxRate: Decimal.parse('0.8547'),
              fees: const Money(75, Currency.eur),
            ),
          ),
        ),
      ),
    ],
  );
}

class _Tracker extends OrderTracker {
  _Tracker(this.view);
  final OrderView view;

  @override
  Future<OrderView> build(String orderId) async => view;
}
