import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/stop_decision.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Position held(String id, String qty) => Position(
  assetId: id,
  quantity: Quantity.truncate(Decimal.parse(qty)),
  costBasis: Decimal.fromInt(100),
  realisedPnl: Decimal.zero,
);

void main() {
  final date = DateTime.utc(2008, 10, 3);
  final positions = {
    'apple': held('apple', '10'),
    'ko': held('ko', '3'),
    'gone': held('gone', '0'),
  };
  const drawdown = DrawdownStop(
    value: Money(840000, Currency.eur),
    threshold: Money(850000, Currency.eur),
  );
  final appleDrop = PositionLossStop('apple', Decimal.parse('-0.22'));

  List<(String, Quantity)> sells(
    StopDecision d,
    List<StopReason> reasons, {
    bool fractional = true,
  }) => [
    for (final o in stopSells(
      d,
      reasons: reasons,
      positions: positions,
      date: date,
      fractional: fractional,
    ))
      (o.assetId, (o.size as QuantitySize).quantity),
  ];

  test('a portfolio drop sells every open position', () {
    expect(sells(StopDecision.sellAll, const [drawdown]), [
      ('apple', Quantity.whole(10)),
      ('ko', Quantity.whole(3)),
    ]);
    expect(sells(StopDecision.sellHalf, const [drawdown]), [
      ('apple', Quantity.whole(5)),
      ('ko', const Quantity.micros(1500000)),
    ]);
  });

  test('a position drop sells that position only', () {
    expect(sells(StopDecision.sellAll, [appleDrop]), [
      ('apple', Quantity.whole(10)),
    ]);
  });

  test('whole shares: half rounds down, and 1 share is left alone', () {
    expect(sells(StopDecision.sellHalf, const [drawdown], fractional: false), [
      ('apple', Quantity.whole(5)),
      ('ko', Quantity.whole(1)),
    ]);
    final one = stopSells(
      StopDecision.sellHalf,
      reasons: const [drawdown],
      positions: {'x': held('x', '1')},
      date: date,
      fractional: false,
    );
    expect(one, isEmpty);
  });

  test('holding or continuing sells nothing; sells are market orders', () {
    expect(sells(StopDecision.hold, const [drawdown]), isEmpty);
    expect(sells(StopDecision.carryOn, const [OrderFilledStop('o1')]), isEmpty);
    final order = stopSells(
      StopDecision.sellAll,
      reasons: const [drawdown],
      positions: {'apple': held('apple', '2')},
      date: date,
      fractional: true,
    ).single;
    expect(order.type, OrderType.market);
    expect(order.side, Side.sell);
    expect(order.createdAt, date);
    expect(order.id, 'stop-apple-2008-10-03');
  });

  test('which stops ask about selling', () {
    expect(isDropStop(const [drawdown]), isTrue);
    expect(isDropStop([appleDrop]), isTrue);
    expect(
      isDropStop(const [
        OrderFilledStop('o1'),
        ContributionStop(Money(20000, Currency.eur)),
      ]),
      isFalse,
    );
  });
}
