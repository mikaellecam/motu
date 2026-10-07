import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import 'returns.dart';

/// "Pourquoi ça bouge ?": an asset's move over a period, in EUR, split into
/// what the market did, what the currency did, and the rest (BRIEF §7.9).
final class MoveDecomposition {
  const MoveDecomposition({
    required this.local,
    required this.total,
    required this.market,
    required this.currency,
    required this.specific,
  });

  /// The asset's return in its quote currency.
  final Decimal local;

  /// The return seen by a EUR investor: `(1 + local)(1 + currency) − 1`.
  final Decimal total;

  /// The benchmark's (world ETF) return in its own currency.
  final Decimal market;

  /// Change in the EUR value of one unit of the quote currency; 0 for EUR.
  final Decimal currency;

  /// Everything else: `total − market − currency`.
  ///
  /// A residual, not a measured effect. It contains what is specific to the
  /// asset (its move beyond the market) *and* the cross term
  /// `local × currency` that compounding creates: a −20 % stock with a +10 %
  /// dollar loses 12 % in EUR, not 10 %. Splitting that cross term between
  /// the components would need a convention; the brief keeps it here, so the
  /// three parts always add up to [total] exactly. Documented approximation.
  final Decimal specific;
}

/// Decomposes the move of an asset from [assetStart] to [assetEnd] against a
/// benchmark over the same dates. [fxStart] and [fxEnd] are EUR per unit of
/// the asset's currency at each date, required unless the asset is in EUR
/// (where the currency component is 0 whatever is passed). Null when a start
/// value is zero, since no return is defined then.
MoveDecomposition? decomposeMove({
  required Price assetStart,
  required Price assetEnd,
  required Price benchmarkStart,
  required Price benchmarkEnd,
  Decimal? fxStart,
  Decimal? fxEnd,
}) {
  if (assetStart.currency != assetEnd.currency) {
    throw CurrencyMismatchError(assetStart.currency, assetEnd.currency);
  }
  if (benchmarkStart.currency != benchmarkEnd.currency) {
    throw CurrencyMismatchError(benchmarkStart.currency, benchmarkEnd.currency);
  }
  final inEur = assetStart.currency == Currency.eur;
  if (!inEur && (fxStart == null || fxEnd == null)) {
    throw ArgumentError(
      'EUR rates are required for ${assetStart.currency.code}',
    );
  }

  final local = simpleReturn(assetStart.value, assetEnd.value);
  final market = simpleReturn(benchmarkStart.value, benchmarkEnd.value);
  final currency = inEur ? Decimal.zero : simpleReturn(fxStart!, fxEnd!);
  if (local == null || market == null || currency == null) return null;

  final total = (Decimal.one + local) * (Decimal.one + currency) - Decimal.one;
  return MoveDecomposition(
    local: local,
    total: total,
    market: market,
    currency: currency,
    specific: total - market - currency,
  );
}
