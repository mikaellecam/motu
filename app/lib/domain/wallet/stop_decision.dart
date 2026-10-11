import '../../core/money/money.dart';
import 'order.dart';
import 'position.dart';
import 'trip_engine.dart';

/// The user's answer to an automatic stop (decided 2026-10-11): the drop
/// stops offer hold, sell half, sell all; the others only continue.
enum StopDecision {
  hold('hold'),
  sellHalf('sell_half'),
  sellAll('sell_all'),
  carryOn('continue');

  const StopDecision(this.id);

  /// Stored in the journal.
  final String id;
}

/// Whether [reasons] ask a question about selling: a portfolio or a
/// position drop.
bool isDropStop(List<StopReason> reasons) =>
    reasons.any((r) => r is DrawdownStop || r is PositionLossStop);

/// The market sells [decision] places on [date], filled at the next session:
/// every open position for a portfolio drop, the dropped positions only
/// otherwise. Half rounds down (to whole shares when [fractional] is off);
/// a position too small to halve is left alone.
List<Order> stopSells(
  StopDecision decision, {
  required List<StopReason> reasons,
  required Map<String, Position> positions,
  required DateTime date,
  required bool fractional,
}) {
  if (decision != StopDecision.sellHalf && decision != StopDecision.sellAll) {
    return const [];
  }
  final everything = reasons.any((r) => r is DrawdownStop);
  final dropped = {
    for (final r in reasons)
      if (r is PositionLossStop) r.assetId,
  };
  return [
    for (final p in positions.values)
      if (p.isOpen && (everything || dropped.contains(p.assetId)))
        if (_quantity(decision, p.quantity, fractional) case final q
            when q.isPositive)
          Order(
            id: stopSellId(p.assetId, date),
            assetId: p.assetId,
            side: Side.sell,
            type: OrderType.market,
            size: QuantitySize(q),
            createdAt: date,
          ),
  ];
}

/// The id of the sell of [assetId] a stop on [date] places.
String stopSellId(String assetId, DateTime date) =>
    'stop-$assetId-${date.toIso8601String().substring(0, 10)}';

Quantity _quantity(StopDecision decision, Quantity held, bool fractional) {
  if (decision == StopDecision.sellAll) return held;
  final half = Quantity.micros(held.micros ~/ 2);
  return fractional ? half : Quantity.whole(half.micros ~/ 1000000);
}
