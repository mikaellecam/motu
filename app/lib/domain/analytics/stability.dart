import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../market/asset.dart';
import 'drawdown.dart';
import 'risk.dart';
import 'volatility.dart';

/// « Stabilité passée » (BRIEF §4.8): out of 100, how little an asset's price
/// moved in the past. Higher means it moved less, not that it is better. Each
/// part is rounded half-even to a whole point and [total] is their sum, so the
/// rows on screen add up to it.
final class PastStability {
  const PastStability({
    required this.movementPoints,
    required this.volatility,
    required this.band,
    required this.fallPoints,
    required this.worstFall,
    required this.basketPoints,
    required this.type,
    required this.historyPoints,
    required this.historyYears,
    required this.since,
  });

  int get total => movementPoints + fallPoints + basketPoints + historyPoints;

  /// 0–40, from the annualised [volatility] of the last year of closes and
  /// its risk [band] (§7.8).
  final int movementPoints;
  final Decimal volatility;
  final int band;

  /// 0–30, from the deepest fall over the last five years.
  final int fallPoints;
  final Drawdown worstFall;

  /// 15 for an ETF (a basket), 0 for a stock (one company).
  final int basketPoints;
  final AssetType type;

  /// 0–15, from the full years of closes since the asset's first one.
  final int historyPoints;
  final int historyYears;
  final DateTime since;
}

/// 40 at 0 % volatility, one point less per point of volatility, 0 from 40 %
/// (where risk band 5 begins).
int movementPoints(Decimal volatility) =>
    _points(Decimal.fromInt(40) - volatility.shift(2), max: 40);

/// 30 without a fall, one point less per 2 % fallen, 0 from −60 %.
int fallPoints(Decimal depth) => _points(
  Decimal.fromInt(30) + depth.shift(2) * Decimal.parse('0.5'),
  max: 30,
);

/// 1,5 point per full year of closes, 15 from ten years.
int historyPoints(int years) =>
    _points(Decimal.fromInt(years) * Decimal.parse('1.5'), max: 15);

int _points(Decimal value, {required int max}) {
  final whole = roundHalfEven(value, 0).toBigInt().toInt();
  return whole.clamp(0, max);
}

/// The score of an asset of [type], first quoted on [listed], from its dated
/// [closes] (oldest first), as of [asOf]: closes after its day are left out.
/// Null under a year of closes (none on or before the same day a year back)
/// or under 20 daily returns in that year: the movements cannot be measured.
/// Throws [ArgumentError] on a close of zero or less.
PastStability? pastStability({
  required List<(DateTime, Decimal)> closes,
  required AssetType type,
  required DateTime listed,
  required DateTime asOf,
}) {
  final day = _day(asOf);
  final known = [
    for (final c in closes)
      if (!c.$1.isAfter(day)) c,
  ];
  final yearAgo = _yearsBefore(day, 1);
  if (!known.any((c) => !c.$1.isAfter(yearAgo))) return null;
  final volatility = annualisedVolatility([
    for (final (date, close) in known)
      if (date.isAfter(yearAgo)) close,
  ]);
  if (volatility == null) return null;

  // Like the five-year chart: from the last close on or before its start.
  final opening = known.lastIndexWhere(
    (c) => !c.$1.isAfter(_yearsBefore(day, 5)),
  );
  final worstFall = maxDrawdown(known.sublist(opening < 0 ? 0 : opening));

  final since = _day(listed);
  final passed =
      day.month > since.month ||
      (day.month == since.month && day.day >= since.day);
  final years = day.year - since.year - (passed ? 0 : 1);
  final historyYears = years < 0 ? 0 : years;

  return PastStability(
    movementPoints: movementPoints(volatility),
    volatility: volatility,
    band: riskBand(volatility)!,
    fallPoints: fallPoints(worstFall.depth),
    worstFall: worstFall,
    basketPoints: type == AssetType.etf ? 15 : 0,
    type: type,
    historyPoints: historyPoints(historyYears),
    historyYears: historyYears,
    since: since,
  );
}

DateTime _day(DateTime t) {
  final utc = t.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// [years] before [day], on 28 February for a 29th.
DateTime _yearsBefore(DateTime day, int years) => DateTime.utc(
  day.year - years,
  day.month,
  day.month == 2 && day.day == 29 ? 28 : day.day,
);
