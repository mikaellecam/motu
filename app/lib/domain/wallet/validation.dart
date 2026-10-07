import 'package:decimal/decimal.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import 'order.dart';
import 'position.dart';

/// Checks an order before it is placed (BRIEF §4.6). Returns every problem
/// found, each with a code and the params its copy needs; empty when valid.
///
/// | code                       | params            |
/// |----------------------------|-------------------|
/// | `amount_not_positive`      |                   |
/// | `quantity_not_positive`    |                   |
/// | `quantity_not_whole`       |                   |
/// | `limit_price_not_positive` |                   |
/// | `stop_price_not_positive`  |                   |
/// | `asset_unavailable`        |                   |
/// | `amount_below_one_share`   | `price`: Price    |
/// | `insufficient_cash`        | `cash`: Money     |
/// | `insufficient_quantity`    | `held`: Quantity  |
/// | `amount_below_fees`        | `fees`: Money     |
///
/// [referencePrice] is the last price known at `asOf`, null when the asset is
/// not available then. [availableCash] and [availableQuantity] already exclude
/// what pending orders reserve.
List<ValidationFailure> validateOrder(
  Order order, {
  required TradingRules rules,
  required Price? referencePrice,
  required Decimal fxRate,
  required Money availableCash,
  required Quantity availableQuantity,
}) {
  final failures = <ValidationFailure>[
    ...switch (order.size) {
      AmountSize(:final amount) when !amount.isPositive => [
        const ValidationFailure('amount_not_positive'),
      ],
      QuantitySize(:final quantity) when !quantity.isPositive => [
        const ValidationFailure('quantity_not_positive'),
      ],
      QuantitySize(:final quantity)
          when !rules.fractionalShares && !quantity.isWhole =>
        [const ValidationFailure('quantity_not_whole')],
      _ => const <ValidationFailure>[],
    },
    if (order.type == OrderType.limit && !_isPositive(order.limitPrice))
      const ValidationFailure('limit_price_not_positive'),
    if (order.type == OrderType.stop && !_isPositive(order.stopPrice))
      const ValidationFailure('stop_price_not_positive'),
    if (referencePrice == null) const ValidationFailure('asset_unavailable'),
  ];
  // The checks below estimate the order; they need a well-formed one.
  if (failures.isNotEmpty) return failures;

  final price = estimatePrice(order, referencePrice)!;
  final quantity = quantityAt(order, price, fxRate, rules);
  if (quantity.isZero) {
    return [
      ValidationFailure('amount_below_one_share', {'price': price}),
    ];
  }

  switch (order.side) {
    case Side.buy:
      final cost = cashToReserve(
        order,
        rules: rules,
        referencePrice: referencePrice!,
        fxRate: fxRate,
      );
      if (cost > availableCash) {
        failures.add(
          ValidationFailure('insufficient_cash', {'cash': availableCash}),
        );
      }
    case Side.sell:
      if (quantity > availableQuantity) {
        failures.add(
          ValidationFailure('insufficient_quantity', {
            'held': availableQuantity,
          }),
        );
      }
      final notional = Money.book(price.times(quantity) * fxRate, Currency.eur);
      final fees = orderFees(notional, price.currency, rules);
      if (notional <= fees) {
        failures.add(ValidationFailure('amount_below_fees', {'fees': fees}));
      }
  }
  return failures;
}

bool _isPositive(Price? price) => price != null && price.value > Decimal.zero;
