import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';

/// One adjusted daily bar (BRIEF §8.3). Prices are in the asset's quote
/// currency.
final class PriceBar {
  const PriceBar({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.currency,
  });

  /// The trading day, `DateTime.utc(y, m, d)`.
  final DateTime date;
  final Decimal open;
  final Decimal high;
  final Decimal low;
  final Decimal close;
  final int volume;
  final Currency currency;
}

/// The price used to value an asset at a date, and where it came from.
final class PriceAsOf {
  const PriceAsOf(this.price, this.date, {required this.stale});

  final Price price;

  /// Date of the bar the price was taken from.
  final DateTime date;

  /// True when the bar of the expected trading day was missing and an
  /// earlier close stands in for it (BRIEF §7.2).
  final bool stale;
}

/// The close to value an asset with at [asOf] (BRIEF §7.2). [expectedDate] is
/// the last trading day on or before [asOf] for the asset's exchange
/// (`MarketCalendar.onOrBefore`). Bars after [asOf] are never read. Null when
/// no bar exists on or before [asOf].
PriceAsOf? closeAsOf(
  Iterable<PriceBar> bars, {
  required DateTime asOf,
  required DateTime expectedDate,
}) {
  PriceBar? latest;
  for (final bar in bars) {
    if (bar.date.isAfter(asOf)) continue;
    if (latest == null || bar.date.isAfter(latest.date)) latest = bar;
  }
  if (latest == null) return null;
  return PriceAsOf(
    Price(latest.close, latest.currency),
    latest.date,
    stale: latest.date.isBefore(expectedDate),
  );
}
