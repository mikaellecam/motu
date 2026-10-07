import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../wallet/valuation.dart';

/// Upper bounds of risk bands 1 to 4 on 1-year annualised volatility
/// (BRIEF §7.8); above the last one is band 5.
final defaultRiskThresholds = [
  for (final t in ['0.08', '0.15', '0.25', '0.40']) Decimal.parse(t),
];

/// Risk band 1–5 for an annualised [volatility]; null when the volatility is
/// unknown (too little history).
int? riskBand(Decimal? volatility, {List<Decimal>? thresholds}) {
  if (volatility == null) return null;
  final limits = thresholds ?? defaultRiskThresholds;
  for (var i = 0; i < limits.length; i++) {
    if (volatility < limits[i]) return i + 1;
  }
  return limits.length + 1;
}

/// Weight of the largest position in the wallet (BRIEF §7.11); cash and the
/// Livret are not positions. Null without positions.
Decimal? concentration(Iterable<AllocationLine> lines) {
  Decimal? largest;
  for (final line in lines.whereType<PositionLine>()) {
    if (largest == null || line.weight > largest) largest = line.weight;
  }
  return largest;
}

/// Effective number of positions, `1 / Σ w²`, with weights taken among
/// positions only (so they sum to 1): two equal positions count as 2 however
/// much cash sits beside them. Null without invested positions.
Decimal? effectivePositions(Iterable<AllocationLine> lines) {
  final weights = [for (final l in lines.whereType<PositionLine>()) l.weight];
  final sum = weights.fold(Decimal.zero, (a, w) => a + w);
  final sumOfSquares = weights.fold(Decimal.zero, (a, w) => a + w * w);
  if (sumOfSquares == Decimal.zero) return null;
  return ratio(sum * sum, sumOfSquares);
}
