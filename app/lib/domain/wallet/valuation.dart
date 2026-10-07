import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../market/price_bar.dart';
import 'position.dart';

/// An open position valued at a date (BRIEF §7.2, §7.4). Amounts in EUR.
final class Holding {
  Holding({required this.position, required this.price, required this.fxRate}) {
    if (price.price.currency == Currency.eur && fxRate != Decimal.one) {
      throw ArgumentError.value(fxRate, 'fxRate', 'EUR prices convert at 1');
    }
  }

  final Position position;
  final PriceAsOf price;

  /// EUR per unit of the price currency, dated on or before the valuation.
  final Decimal fxRate;

  Decimal get marketValue => price.price.times(position.quantity) * fxRate;

  Decimal get unrealisedPnl => marketValue - position.costBasis;

  /// Unrealised P&L over cost basis; null when the cost basis is zero.
  Decimal? get unrealisedPnlRatio => position.costBasis == Decimal.zero
      ? null
      : ratio(unrealisedPnl, position.costBasis);

  bool get stale => price.stale;
}

/// One line of the allocation bar (BRIEF §7.5). Cash and the Livret are lines.
sealed class AllocationLine {
  const AllocationLine(this.weight);

  /// Share of the wallet value, between 0 and 1.
  final Decimal weight;
}

final class PositionLine extends AllocationLine {
  const PositionLine(this.assetId, super.weight);
  final String assetId;
}

final class CashLine extends AllocationLine {
  const CashLine(super.weight);
}

final class LivretLine extends AllocationLine {
  const LivretLine(super.weight);
}

final class WalletValuation {
  const WalletValuation({
    required this.cash,
    required this.livret,
    required this.holdings,
  });

  final Money cash;

  /// Livret balance including accrued, not yet credited interest, in EUR.
  final Decimal livret;

  /// Open positions, in the order given.
  final List<Holding> holdings;

  Decimal get total => holdings.fold(
    cash.amount + livret,
    (sum, holding) => sum + holding.marketValue,
  );

  bool get hasStalePrice => holdings.any((h) => h.stale);

  /// Positions, then cash, then the Livret when it holds money. Empty when
  /// the wallet is worth nothing, since no weight is defined then.
  List<AllocationLine> get allocation {
    final total = this.total;
    if (total == Decimal.zero) return const [];
    return [
      for (final h in holdings)
        PositionLine(h.position.assetId, ratio(h.marketValue, total)),
      CashLine(ratio(cash.amount, total)),
      if (livret != Decimal.zero) LivretLine(ratio(livret, total)),
    ];
  }
}

/// Values a wallet at one date (BRIEF §7.3). [prices] must hold every open
/// position's price and [fxRates] (EUR per unit, EUR excluded) every non-EUR
/// currency among them: the caller resolves both as of the valuation date.
WalletValuation valueWallet({
  required Money cash,
  required Map<String, Position> positions,
  required Map<String, PriceAsOf> prices,
  required Map<Currency, Decimal> fxRates,
  Decimal? livret,
}) {
  if (cash.currency != Currency.eur) {
    throw CurrencyMismatchError(Currency.eur, cash.currency);
  }
  final holdings = [
    for (final position in positions.values.where((p) => p.isOpen))
      _hold(position, prices, fxRates),
  ];
  return WalletValuation(
    cash: cash,
    livret: livret ?? Decimal.zero,
    holdings: holdings,
  );
}

Holding _hold(
  Position position,
  Map<String, PriceAsOf> prices,
  Map<Currency, Decimal> fxRates,
) {
  final price = prices[position.assetId];
  if (price == null) {
    throw ArgumentError('No price for open position ${position.assetId}');
  }
  final currency = price.price.currency;
  final rate = currency == Currency.eur ? Decimal.one : fxRates[currency];
  if (rate == null) {
    throw ArgumentError('No EUR rate for ${currency.code}');
  }
  return Holding(position: position, price: price, fxRate: rate);
}
