import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import 'position.dart';

enum OrderType { market, limit, stop }

/// How much an order trades: a EUR amount or a number of shares (BRIEF §4.6).
sealed class OrderSize {
  const OrderSize();
}

/// The value of shares to trade, in EUR. Fees come on top of a buy and out of
/// a sell's proceeds.
final class AmountSize extends OrderSize {
  const AmountSize(this.amount);
  final Money amount;
}

final class QuantitySize extends OrderSize {
  const QuantitySize(this.quantity);
  final Quantity quantity;
}

/// A wallet's trading conditions (difficulty, BRIEF §4.5).
final class TradingRules {
  const TradingRules({
    required this.fxFeeRate,
    required this.fixedFee,
    required this.fractionalShares,
  });

  /// Charged on the EUR notional when the asset is not quoted in EUR.
  final Decimal fxFeeRate;

  /// Charged on every executed order.
  final Money fixedFee;

  /// False for whole-share wallets: quantities are whole, amounts are
  /// floored to whole shares.
  final bool fractionalShares;
}

/// An order as placed. Good till cancelled.
final class Order {
  const Order({
    required this.id,
    required this.assetId,
    required this.side,
    required this.type,
    required this.size,
    required this.createdAt,
    this.limitPrice,
    this.stopPrice,
  });

  final String id;
  final String assetId;
  final Side side;
  final OrderType type;
  final OrderSize size;

  /// Required for [OrderType.limit], in the asset's quote currency.
  final Price? limitPrice;

  /// Required for [OrderType.stop], in the asset's quote currency.
  final Price? stopPrice;

  /// When the order was placed: an instant (live) or the simulated day
  /// (trip).
  final DateTime createdAt;
}

/// Fees of an order with [notional] EUR in an asset quoted in [assetCurrency]
/// (BRIEF §4.6): FX fee (booked) when the asset is not in EUR, plus the
/// fixed fee.
Money orderFees(Money notional, Currency assetCurrency, TradingRules rules) {
  final fxFee = assetCurrency == Currency.eur
      ? const Money.zero(Currency.eur)
      : Money.book(notional.amount * rules.fxFeeRate, Currency.eur);
  return fxFee + rules.fixedFee;
}

/// Shares [order] trades at [price] with [fxRate] (EUR per unit): its
/// quantity, or for an amount `amount / (price × rate)`, truncated to 6
/// decimals and floored to whole shares when the wallet requires it.
Quantity quantityAt(
  Order order,
  Price price,
  Decimal fxRate,
  TradingRules rules,
) {
  switch (order.size) {
    case QuantitySize(:final quantity):
      return quantity;
    case AmountSize(:final amount):
      final shares = Quantity.truncate(
        ratio(amount.amount, price.value * fxRate),
      );
      if (rules.fractionalShares) return shares;
      return Quantity.whole(shares.toDecimal().floor().toBigInt().toInt());
  }
}

/// The price an order is estimated at before it executes: the last known
/// price for a market order, its limit or stop otherwise.
Price? estimatePrice(Order order, Price? lastPrice) => switch (order.type) {
  OrderType.market => lastPrice,
  OrderType.limit => order.limitPrice,
  OrderType.stop => order.stopPrice,
};

/// Cash a pending buy holds back from "Liquidités disponibles" (decided
/// 2026-10-07): an amount reserves amount + fees, which bounds what it can
/// cost; a quantity reserves its cost at the estimate price. Sells reserve no
/// cash.
Money cashToReserve(
  Order order, {
  required TradingRules rules,
  required Price referencePrice,
  required Decimal fxRate,
}) {
  if (order.side == Side.sell) return const Money.zero(Currency.eur);
  final currency = referencePrice.currency;
  final Money notional = switch (order.size) {
    AmountSize(:final amount) => amount,
    QuantitySize(:final quantity) => Money.book(
      estimatePrice(order, referencePrice)!.times(quantity) * fxRate,
      Currency.eur,
    ),
  };
  return notional + orderFees(notional, currency, rules);
}

/// Shares a pending sell holds back from the position. Buys reserve none.
Quantity quantityToReserve(
  Order order, {
  required TradingRules rules,
  required Price referencePrice,
  required Decimal fxRate,
}) => order.side == Side.buy
    ? const Quantity.zero()
    : quantityAt(order, estimatePrice(order, referencePrice)!, fxRate, rules);
