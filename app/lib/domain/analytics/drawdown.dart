import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';

/// The deepest fall from a running peak (BRIEF §7.10).
final class Drawdown {
  const Drawdown(this.depth, {this.peakDate, this.troughDate});

  /// `trough / peak − 1`: zero or negative.
  final Decimal depth;

  /// Null when the series never fell.
  final DateTime? peakDate;
  final DateTime? troughDate;
}

/// Max drawdown of a dated [series], oldest first: prices or wallet values.
/// Empty, single-point or never-falling series: depth 0, no dates. Values are
/// only compared with a positive peak (a wallet worth 0 has no drawdown).
Drawdown maxDrawdown(Iterable<(DateTime, Decimal)> series) {
  Decimal? peak;
  DateTime? peakDate;
  var worst = Drawdown(Decimal.zero);
  for (final (date, value) in series) {
    if (peak == null || value > peak) {
      peak = value;
      peakDate = date;
      continue;
    }
    if (peak <= Decimal.zero) continue;
    final depth = ratio(value, peak) - Decimal.one;
    if (depth < worst.depth) {
      worst = Drawdown(depth, peakDate: peakDate, troughDate: date);
    }
  }
  return worst;
}
