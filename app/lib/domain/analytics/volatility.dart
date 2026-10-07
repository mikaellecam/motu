import 'dart:math' as math;

import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';

/// Below this many daily returns the estimate means little: no volatility
/// ("pas assez de données").
const minVolatilityReturns = 20;

const tradingDaysPerYear = 252;

/// Annualised volatility of a series of daily [closes], oldest first
/// (BRIEF §7.7): sample standard deviation of daily log returns × √252.
/// Null under [minVolatilityReturns] returns.
///
/// Logarithms and square roots have no exact decimal form, so this statistic
/// is computed in `double`. It describes how much a price moved; it never
/// feeds back into an amount of money (ADR-003).
Decimal? annualisedVolatility(List<Decimal> closes) {
  if (closes.any((close) => close <= Decimal.zero)) {
    throw ArgumentError('Closes must be positive');
  }
  final n = closes.length - 1;
  if (n < minVolatilityReturns) return null;

  final returns = [
    for (var i = 1; i < closes.length; i++)
      math.log((closes[i] / closes[i - 1]).toDouble()),
  ];
  final mean = returns.reduce((a, b) => a + b) / n;
  final variance =
      returns.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) /
      (n - 1);
  final annualised = math.sqrt(variance) * math.sqrt(tradingDaysPerYear);
  return Decimal.parse(annualised.toStringAsFixed(ratioScale));
}
