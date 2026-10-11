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
    this.orderId,
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

  /// The order it filled; null when not known.
  final String? orderId;

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

/// The EUR rate the shares of [assetId] still held were bought at, on
/// average: their notional in EUR over their notional in the quote currency.
/// A sell keeps it, like the average cost. Fees are left out: they are not a
/// currency move. Null when no share is held.
Decimal? averagePurchaseRate(Iterable<Fill> fills, String assetId) {
  var local = Decimal.zero;
  var eur = Decimal.zero;
  var held = const Quantity.zero();
  for (final fill in fills) {
    if (fill.assetId != assetId) continue;
    final notional = fill.price.times(fill.quantity);
    switch (fill.side) {
      case Side.buy:
        local += notional;
        eur += notional * fill.fxRate;
        held += fill.quantity;
      case Side.sell:
        final left = held - fill.quantity;
        local = ratio(local * left.toDecimal(), held.toDecimal());
        eur = ratio(eur * left.toDecimal(), held.toDecimal());
        held = left;
    }
  }
  return held.isPositive && local > Decimal.zero ? ratio(eur, local) : null;
}

/// Of a holding's unrealised P&L in EUR, the part the currency made: its
/// value now minus its value at [averageRate] (BRIEF §4.8). Zero for an EUR
/// price (rates of 1).
Decimal currencyEffect({
  required Quantity quantity,
  required Price price,
  required Decimal fxNow,
  required Decimal averageRate,
}) => price.times(quantity) * (fxNow - averageRate);
