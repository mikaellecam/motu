import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';

/// A wallet's end-of-day value and the external flow (contribution or
/// withdrawal) credited that day: one row of `wallet_values` (BRIEF §6.1).
/// The first day's flow is the starting cash.
final class DailyValue {
  const DailyValue({
    required this.date,
    required this.value,
    required this.flow,
  });

  final DateTime date;
  final Money value;
  final Money flow;
}

/// (end − start) / start; null when [start] is zero.
Decimal? simpleReturn(Decimal start, Decimal end) =>
    start == Decimal.zero ? null : ratio(end - start, start);

/// Time-weighted return over [days] (BRIEF §7.6): the product of daily
/// growth factors `(V_t − F_t) / V_{t−1}`, minus 1. Contributions move the
/// value but not the return. A day following a zero value has no defined
/// growth and is skipped. Empty or single day: 0.
Decimal timeWeightedReturn(List<DailyValue> days) {
  var growth = Decimal.one;
  for (var i = 1; i < days.length; i++) {
    final previous = days[i - 1];
    final today = days[i];
    if (!today.date.isAfter(previous.date)) {
      throw ArgumentError('Daily values out of date order at ${today.date}');
    }
    if (previous.value.isZero) continue;
    final factor = ratio(
      (today.value - today.flow).amount,
      previous.value.amount,
    );
    // Keep the scale bounded over thousands of days.
    growth = (growth * factor).truncate(scale: ratioScale);
  }
  return growth - Decimal.one;
}
