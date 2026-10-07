import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';

enum Side { buy, sell }

/// An executed order as booked (BRIEF §6.1 `fills`, joined with its order's
/// asset and side).
final class Fill {
  const Fill({
    required this.assetId,
    required this.side,
    required this.date,
    required this.quantity,
    required this.price,
    required this.fxRate,
    required this.fees,
  });

  final String assetId;
  final Side side;
  final DateTime date;
  final Quantity quantity;

  /// Fill price, in the asset's quote currency.
  final Price price;

  /// EUR per unit of [price]'s currency on the fill date; 1 for EUR assets.
  final Decimal fxRate;

  /// All fees of the fill (FX + fixed), in EUR.
  final Money fees;

  /// Price × quantity in EUR, booked to the cent (ADR-003).
  Money get notional =>
      Money.book(price.times(quantity) * fxRate, Currency.eur);

  /// The fill's effect on cash: a buy pays notional + fees, a sell receives
  /// notional − fees.
  Money get cashFlow => switch (side) {
    Side.buy => -(notional + fees),
    Side.sell => notional - fees,
  };
}

/// Shares of one asset held in a wallet, at average cost (BRIEF §7.1).
/// Derived from fills on read, never stored.
final class Position {
  const Position({
    required this.assetId,
    required this.quantity,
    required this.costBasis,
    required this.realisedPnl,
  });

  final String assetId;
  final Quantity quantity;

  /// What the shares still held cost, fees included, in EUR.
  final Decimal costBasis;

  /// Gains and losses already realised by sells, in EUR.
  final Decimal realisedPnl;

  bool get isOpen => quantity.isPositive;

  /// EUR per share; null once the position is closed.
  Decimal? get averageCost =>
      isOpen ? ratio(costBasis, quantity.toDecimal()) : null;
}

/// [held] after [fill]: a buy adds its cost (notional + fees) to the cost
/// basis; a sell removes its share of it, so the average cost is unchanged,
/// and realises proceeds − average cost × quantity.
///
/// Throws [StateError] on a fill that cannot have been valid: a non-positive
/// quantity, or a sell above the quantity held.
Position applyFill(Position? held, Fill fill) {
  if (!fill.quantity.isPositive) {
    throw StateError('Fill of ${fill.quantity} for ${fill.assetId}');
  }
  final position =
      held ??
      Position(
        assetId: fill.assetId,
        quantity: const Quantity.zero(),
        costBasis: Decimal.zero,
        realisedPnl: Decimal.zero,
      );
  return switch (fill.side) {
    Side.buy => Position(
      assetId: fill.assetId,
      quantity: position.quantity + fill.quantity,
      costBasis: position.costBasis - fill.cashFlow.amount,
      realisedPnl: position.realisedPnl,
    ),
    Side.sell => _sell(position, fill),
  };
}

/// Positions from [fills], in date order (see [applyFill]). Throws
/// [StateError] on fills out of date order.
Map<String, Position> positionsFrom(Iterable<Fill> fills) {
  final positions = <String, Position>{};
  DateTime? previous;
  for (final fill in fills) {
    if (previous != null && fill.date.isBefore(previous)) {
      throw StateError('Fills out of date order at ${fill.date}');
    }
    previous = fill.date;
    positions[fill.assetId] = applyFill(positions[fill.assetId], fill);
  }
  return positions;
}

Position _sell(Position held, Fill fill) {
  if (fill.quantity > held.quantity) {
    throw StateError(
      'Sell of ${fill.quantity} ${fill.assetId} above ${held.quantity} held',
    );
  }
  // Multiply before dividing: one truncation, and none when the whole
  // position is sold.
  final soldCost = ratio(
    held.costBasis * fill.quantity.toDecimal(),
    held.quantity.toDecimal(),
  );
  return Position(
    assetId: held.assetId,
    quantity: held.quantity - fill.quantity,
    costBasis: held.costBasis - soldCost,
    realisedPnl: held.realisedPnl + fill.cashFlow.amount - soldCost,
  );
}
