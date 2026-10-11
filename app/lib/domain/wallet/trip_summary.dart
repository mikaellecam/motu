import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../analytics/returns.dart';
import '../companion/rules.dart';
import 'dca.dart';
import 'order.dart';
import 'position.dart';
import 'stop_decision.dart';

/// The end-of-trip summary (BRIEF §4.5): « Ta pire décision », the journal
/// replayed with what happened next, and the glossary terms met.

/// One row of the trip journal (BRIEF §4.13).
final class JournalEntry {
  const JournalEntry({
    required this.date,
    required this.decision,
    this.eventId,
    this.reason,
  });

  final DateTime date;

  /// A [StopDecision] id for the answer to a stop.
  final String decision;

  /// The stop that asked for the decision, if any.
  final String? eventId;
  final String? reason;

  /// « Vendre la moitié » or « Tout vendre ».
  bool get isSell =>
      decision == StopDecision.sellHalf.id ||
      decision == StopDecision.sellAll.id;

  /// A trip order written with a reason (BRIEF §4.13): its decision is the
  /// order's side and its event the order.
  bool get isOrder => decision == 'buy' || decision == 'sell';

  /// A decision to sell, from a stop or an order (« Ta pire décision »).
  bool get sells => isSell || decision == 'sell';
}

/// [series] had every position been sold at the close of [date] and kept
/// as cash: the values up to the day before, that day's value less [fees],
/// then that cash plus the later flows. A Livret A keeps earning (decided
/// 2026-10-11): [livretInterest] is what it has earned in all by a day, and
/// what it earns after the sale is added. A day without a value sells at the
/// last one before it; a day before the series changes nothing.
List<DailyValue> soldEverythingOn(
  DateTime date,
  List<DailyValue> series, {
  required Money fees,
  Decimal Function(DateTime day)? livretInterest,
}) {
  final sale = series.lastIndexWhere((v) => !v.date.isAfter(date));
  if (sale < 0) return series;
  var cash = series[sale].value - fees;
  final earned = livretInterest ?? (_) => Decimal.zero;
  final atSale = earned(series[sale].date);
  return [
    ...series.take(sale),
    DailyValue(date: series[sale].date, value: cash, flow: series[sale].flow),
    for (final v in series.skip(sale + 1))
      DailyValue(
        date: v.date,
        value:
            (cash += v.flow) +
            Money.book(earned(v.date) - atSale, Currency.eur),
        flow: v.flow,
      ),
  ];
}

/// « Ta pire décision » (decided 2026-10-11): among the days of [fees] (the
/// days the journal sold, with what selling everything would have cost
/// then), the one whose [soldEverythingOn] series ends lowest, the earliest
/// on a tie. Null without a day or a series.
({DateTime date, List<DailyValue> series})? worstSell(
  List<DailyValue> series,
  Map<DateTime, Money> fees, {
  Decimal Function(DateTime day)? livretInterest,
}) {
  if (series.isEmpty) return null;
  ({DateTime date, List<DailyValue> series})? worst;
  for (final date in [...fees.keys]..sort()) {
    final sold = soldEverythingOn(
      date,
      series,
      fees: fees[date]!,
      livretInterest: livretInterest,
    );
    if (worst == null || sold.last.value < worst.series.last.value) {
      worst = (date: date, series: sold);
    }
  }
  return worst;
}

/// What selling every open position of [positions] at [prices] would cost
/// (BRIEF §4.6): the fixed fee each, plus the FX fee off the euro.
/// [fxRate] gives EUR per unit of a currency. A position is never charged
/// more than it is worth.
Money sellAllFees(
  Map<String, Position> positions, {
  required Map<String, Price> prices,
  required Decimal Function(Currency currency) fxRate,
  required TradingRules rules,
}) {
  var total = const Money.zero(Currency.eur);
  for (final p in positions.values.where((p) => p.isOpen)) {
    final price = prices[p.assetId];
    if (price == null) throw ArgumentError('No price for ${p.assetId}');
    final notional = Money.book(
      price.times(p.quantity) * fxRate(price.currency),
      Currency.eur,
    );
    final fees = orderFees(notional, price.currency, rules);
    total += fees < notional ? fees : notional;
  }
  return total;
}

/// The fills [entry] led to: the sells a stop placed (`stopSells`), or the
/// trip order it names.
Iterable<Fill> filledBy(JournalEntry entry, List<Fill> fills) => fills.where(
  (f) => entry.isOrder
      ? f.orderId == entry.eventId
      : entry.isSell &&
            f.side == Side.sell &&
            f.orderId == stopSellId(f.assetId, entry.date),
);

/// What happened after [entry] (BRIEF §4.13, decided 2026-10-11): for a
/// stop's sell or a trip order, how the shares it traded moved from their
/// fill to [endPrices] (EUR per share at the end of the trip); for « Garder », the time-weighted
/// return of [series] from that day on. Null for any other entry, or when
/// nothing followed (a sell not filled yet, a decision on the last day).
Decimal? movedAfter(
  JournalEntry entry, {
  required List<DailyValue> series,
  required List<Fill> fills,
  required Map<String, Decimal> endPrices,
}) {
  if (entry.isSell || entry.isOrder) {
    var then = Decimal.zero;
    var now = Decimal.zero;
    for (final f in filledBy(entry, fills)) {
      final end = endPrices[f.assetId];
      if (end == null) return null;
      then += f.price.times(f.quantity) * f.fxRate;
      now += end * f.quantity.toDecimal();
    }
    return simpleReturn(then, now);
  }
  if (entry.decision == StopDecision.hold.id) {
    final after = [
      for (final v in series)
        if (!v.date.isBefore(entry.date)) v,
    ];
    return after.length < 2 ? null : timeWeightedReturn(after);
  }
  return null;
}

/// The glossary terms the companion's [moments] of a trip linked to, in the
/// order they first came up, once each (decided 2026-10-11).
List<String> termsMet(List<CompanionLogEntry> moments) => {
  for (final m in [...moments]..sort((a, b) => a.firedAt.compareTo(b.firedAt)))
    ...m.rule.glossary,
}.toList();

/// A comparison run's [points] as daily values, to compute its
/// time-weighted return: each point's flow is the money put in since the
/// previous one.
List<DailyValue> asDailyValues(List<ValuePoint> points) {
  final days = <DailyValue>[];
  var before = const Money.zero(Currency.eur);
  for (final p in points) {
    days.add(
      DailyValue(
        date: p.date,
        value: Money.book(p.value, Currency.eur),
        flow: p.invested - before,
      ),
    );
    before = p.invested;
  }
  return days;
}
