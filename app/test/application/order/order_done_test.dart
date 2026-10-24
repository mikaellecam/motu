import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/order/order_ticket.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:flutter_test/flutter_test.dart';

Fill fill(Side side) => Fill(
  assetId: 'world',
  side: side,
  date: DateTime.utc(2026, 10, 7),
  quantity: Quantity.whole(2),
  price: Price(Decimal.parse('101.5'), Currency.usd),
  fxRate: Decimal.parse('0.8547'),
  fees: const Money.zero(Currency.eur),
);

void main() {
  test('a pending buy: its building under construction', () {
    final sent = OrderSent(
      'o',
      side: Side.buy,
      opensAt: DateTime.utc(2026, 10, 8, 13, 30),
    );
    final done = orderDone(sent)!;
    expect((done.outcome, done.built), (sent, false));
    expect(done.missions, isEmpty);
    // In a trip, or waiting for its price, the same.
    for (final other in [
      const OrderSent('t', side: Side.buy, trip: true),
      const OrderSent('l', side: Side.buy),
    ]) {
      expect(orderDone(other)!.built, isFalse);
    }
  });

  test('a buy filled at once: its building built', () {
    final done = orderDone(OrderExecuted('o', fill(Side.buy)))!;
    expect(done.built, isTrue);
    expect(done.missions, isEmpty);
  });

  test('a sell opens no screen: it keeps its message', () {
    expect(orderDone(OrderExecuted('o', fill(Side.sell))), isNull);
    expect(orderDone(const OrderSent('o', side: Side.sell)), isNull);
    expect(
      orderDone(
        OrderSent(
          'o',
          side: Side.sell,
          opensAt: DateTime.utc(2026, 10, 8, 13, 30),
        ),
      ),
      isNull,
    );
  });

  test('a buy that completes missions shows each, in path order', () {
    final done = orderDone(
      OrderExecuted(
        'o',
        fill(Side.buy),
        missions: const ['ae.mission-first-etf', 'ae.mission-three-regions'],
      ),
    )!;
    expect(done.built, isTrue);
    expect(done.missions, ['ae.mission-first-etf', 'ae.mission-three-regions']);
  });
}
