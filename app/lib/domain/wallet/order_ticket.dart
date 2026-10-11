import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import 'order.dart';
import 'position.dart';

/// What the order sheet shows while an order is being written (BRIEF §4.6):
/// what it would do, the largest buy, half a position, and the asset's
/// weight before and after (the pre-trade coach).

/// An order priced at its reference: the shares, their value in euros, the
/// fees, and the total (paid for a buy, received for a sell).
final class OrderEstimate {
  const OrderEstimate({
    required this.quantity,
    required this.notional,
    required this.fees,
    required this.total,
  });

  final Quantity quantity;
  final Money notional;
  final Money fees;
  final Money total;
}

/// [order] priced at its limit or stop, or at [referencePrice] for a market
/// order; null when it cannot be priced or trades no share.
OrderEstimate? estimateOrder(
  Order order, {
  required Price? referencePrice,
  required Decimal fxRate,
  required TradingRules rules,
}) {
  final price = estimatePrice(order, referencePrice);
  if (price == null || price.value <= Decimal.zero) return null;
  final positive = switch (order.size) {
    AmountSize(:final amount) => amount.isPositive,
    QuantitySize(:final quantity) => quantity.isPositive,
  };
  if (!positive) return null;
  final quantity = quantityAt(order, price, fxRate, rules);
  if (!quantity.isPositive) return null;
  final notional = Money.book(price.times(quantity) * fxRate, Currency.eur);
  final fees = orderFees(notional, price.currency, rules);
  return OrderEstimate(
    quantity: quantity,
    notional: notional,
    fees: fees,
    total: order.side == Side.buy ? notional + fees : notional - fees,
  );
}

/// The largest € amount a buy can spend from [cash] once its fees are added
/// (« Max »), to the cent, never below zero.
Money maxBuyAmount(
  Money cash, {
  required Currency assetCurrency,
  required TradingRules rules,
}) {
  final rate = assetCurrency == Currency.eur ? Decimal.zero : rules.fxFeeRate;
  final room = cash.amount - rules.fixedFee.amount;
  if (room <= Decimal.zero) return const Money.zero(Currency.eur);
  var amount = Money(
    (ratio(room, Decimal.one + rate) * Decimal.fromInt(100))
        .floor()
        .toBigInt()
        .toInt(),
    Currency.eur,
  );
  // Fees are booked half-even: step back while they push the total over.
  while (amount.isPositive &&
      amount + orderFees(amount, assetCurrency, rules) > cash) {
    amount = Money(amount.minorUnits - 1, Currency.eur);
  }
  return amount;
}

/// Half of [held], down to whole shares when the wallet is not [fractional].
Quantity halfOf(Quantity held, {required bool fractional}) {
  final half = Quantity.micros(held.micros ~/ 2);
  return fractional ? half : Quantity.whole(half.micros ~/ 1000000);
}

/// The asset's share of the wallet now and once the order is done: a buy
/// moves [notional] from cash into the position, a sell back, and the fees
/// leave the wallet. Null for an empty wallet.
({Decimal before, Decimal after})? weightChange({
  required Decimal positionValue,
  required Decimal walletTotal,
  required Side side,
  required Money notional,
  required Money fees,
}) {
  if (walletTotal <= Decimal.zero) return null;
  final after = walletTotal - fees.amount;
  final value = side == Side.buy
      ? positionValue + notional.amount
      : positionValue - notional.amount;
  return (
    before: ratio(positionValue, walletTotal),
    after: after <= Decimal.zero
        ? Decimal.zero
        : ratio(value < Decimal.zero ? Decimal.zero : value, after),
  );
}
