import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../market/price_bar.dart';
import 'order.dart';
import 'position.dart';

/// What happened to a pending order on one bar or quote.
sealed class MatchResult {
  const MatchResult();
}

/// The price did not reach the order's trigger: it stays pending.
final class Unfilled extends MatchResult {
  const Unfilled();
}

final class Filled extends MatchResult {
  const Filled(this.fill);
  final Fill fill;
}

/// The order triggered but cannot execute as asked; no partial fills
/// (decided 2026-10-07).
final class Cancelled extends MatchResult {
  const Cancelled(this.reason);
  final CancelReason reason;
}

enum CancelReason {
  /// The buy costs more than the cash it may spend.
  insufficientCash,

  /// The sell needs more shares than are held.
  insufficientQuantity,

  /// The amount buys or sells no share at the fill price (whole-share
  /// wallets).
  amountBelowOneShare,

  /// The sell's fees would take all its proceeds.
  proceedsBelowFees,

  /// The user cancelled it while it was pending (M4-6).
  byUser,
}

/// Applies [order] to the daily [bar] of a session that started after the
/// order was placed (BRIEF §4.6). The caller picks the bars: after the close
/// of the trip day it was placed on, or from the next session for a live
/// order placed while the market was closed.
///
/// - market: fills at the open;
/// - limit buy: when low ≤ limit, at min(open, limit); limit sell: when
///   high ≥ limit, at max(open, limit);
/// - stop sell: when low ≤ stop, at min(open, stop), so a gap through the
///   stop fills below it; stop buy: when high ≥ stop, at max(open, stop).
///
/// [fxRate] is EUR per unit on the bar's date; [spendableCash] is the wallet
/// cash minus what *other* pending buys reserve; [heldQuantity] is the
/// position before this order.
MatchResult matchOnBar(
  Order order,
  PriceBar bar, {
  required TradingRules rules,
  required Decimal fxRate,
  required Money spendableCash,
  required Quantity heldQuantity,
}) {
  final open = Price(bar.open, bar.currency);
  final high = Price(bar.high, bar.currency);
  final low = Price(bar.low, bar.currency);
  final Price? fillPrice = switch ((order.type, order.side)) {
    (OrderType.market, _) => open,
    (OrderType.limit, Side.buy) => _ifReached(
      low <= order.limitPrice!,
      () => _min(open, order.limitPrice!),
    ),
    (OrderType.limit, Side.sell) => _ifReached(
      high >= order.limitPrice!,
      () => _max(open, order.limitPrice!),
    ),
    (OrderType.stop, Side.sell) => _ifReached(
      low <= order.stopPrice!,
      () => _min(open, order.stopPrice!),
    ),
    (OrderType.stop, Side.buy) => _ifReached(
      high >= order.stopPrice!,
      () => _max(open, order.stopPrice!),
    ),
  };
  if (fillPrice == null) return const Unfilled();
  return _execute(
    order,
    fillPrice,
    bar.date,
    rules: rules,
    fxRate: fxRate,
    spendableCash: spendableCash,
    heldQuantity: heldQuantity,
  );
}

/// A live market order placed while its market is open fills at the latest
/// [quote] (delayed quotes are fine), timestamped [at].
MatchResult fillAtQuote(
  Order order,
  Price quote, {
  required DateTime at,
  required TradingRules rules,
  required Decimal fxRate,
  required Money spendableCash,
  required Quantity heldQuantity,
}) {
  if (order.type != OrderType.market) {
    throw ArgumentError.value(order.type, 'order.type', 'Only market orders');
  }
  return _execute(
    order,
    quote,
    at,
    rules: rules,
    fxRate: fxRate,
    spendableCash: spendableCash,
    heldQuantity: heldQuantity,
  );
}

Price? _ifReached(bool reached, Price Function() price) =>
    reached ? price() : null;

Price _min(Price a, Price b) => a <= b ? a : b;
Price _max(Price a, Price b) => a >= b ? a : b;

MatchResult _execute(
  Order order,
  Price price,
  DateTime date, {
  required TradingRules rules,
  required Decimal fxRate,
  required Money spendableCash,
  required Quantity heldQuantity,
}) {
  final quantity = quantityAt(order, price, fxRate, rules);
  if (quantity.isZero) return const Cancelled(CancelReason.amountBelowOneShare);

  final notional = Money.book(price.times(quantity) * fxRate, Currency.eur);
  final fill = Fill(
    assetId: order.assetId,
    side: order.side,
    date: date,
    quantity: quantity,
    price: price,
    fxRate: fxRate,
    fees: orderFees(notional, price.currency, rules),
    orderId: order.id,
  );
  switch (order.side) {
    case Side.buy when -fill.cashFlow > spendableCash:
      return const Cancelled(CancelReason.insufficientCash);
    case Side.sell when quantity > heldQuantity:
      return const Cancelled(CancelReason.insufficientQuantity);
    case Side.sell when fill.notional <= fill.fees:
      return const Cancelled(CancelReason.proceedsBelowFees);
    case _:
      return Filled(fill);
  }
}
