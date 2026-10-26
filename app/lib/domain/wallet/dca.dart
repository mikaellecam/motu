import 'dart:math' as math;

import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../livret/livret_interest.dart';
import '../market/market_calendar.dart';
import '../market/price_bar.dart';
import 'order.dart';

/// DCA and "what if the same money had gone elsewhere" runs (BRIEF §4.10,
/// §7.12): the DCA simulator, its lump-sum and Livret comparisons, and the
/// trip summary's counterfactuals all invest a list of dated [Flow]s.

enum DcaFrequency { monthly, weekly }

/// Money put in on a date.
final class Flow {
  const Flow(this.date, this.amount);
  final DateTime date;

  /// In EUR.
  final Money amount;
}

/// A standing instruction to buy [amount] of an asset on a schedule
/// (BRIEF §6.1 `dca_plans`).
final class DcaPlan {
  const DcaPlan({
    required this.id,
    required this.assetId,
    required this.amount,
    required this.frequency,
    required this.start,
    this.active = true,
  });

  final String id;
  final String assetId;

  /// In EUR, per purchase.
  final Money amount;
  final DcaFrequency frequency;

  /// First scheduled date; later ones follow [frequency] (see [dcaSchedule]).
  final DateTime start;
  final bool active;
}

/// Purchase dates from [start] to [end]: monthly on the start day of the
/// month (the last day in shorter months), or weekly on the start weekday.
/// A non-trading date rolls to the next trading day of [exchange]; a date
/// that rolls past [end] is dropped.
List<DateTime> dcaSchedule({
  required DateTime start,
  required DateTime end,
  required DcaFrequency frequency,
  required MarketCalendar calendar,
  required Exchange exchange,
}) {
  final dates = <DateTime>[];
  for (var i = 0; ; i++) {
    final scheduled = switch (frequency) {
      DcaFrequency.monthly => _sameDayOfMonth(start, i),
      DcaFrequency.weekly => DateTime.utc(
        start.year,
        start.month,
        start.day + 7 * i,
      ),
    };
    if (scheduled.isAfter(end)) return dates;
    final rolled = calendar.onOrAfter(exchange, scheduled);
    if (!rolled.isAfter(end)) dates.add(rolled);
  }
}

/// The day a plan set up in a wallet at [walletDay] makes its first purchase
/// (BRIEF §4.5): the first session of [exchange] after the wallet's day that
/// opens after [placedAt], so its open price was not known when the plan was
/// set up. [placedAt] is the real time for the live wallet and a trip at
/// today; null for any other trip, whose day is seen after its close.
DateTime firstPurchaseDay({
  required MarketCalendar calendar,
  required Exchange exchange,
  required DateTime walletDay,
  DateTime? placedAt,
}) {
  var day = calendar.nextTradingDay(exchange, walletDay);
  while (placedAt != null &&
      !calendar.openAt(exchange, day).isAfter(placedAt)) {
    day = calendar.nextTradingDay(exchange, day);
  }
  return day;
}

/// [plan]'s first purchase after [after] (the wallet's day): its start, then
/// its [dcaSchedule].
DateTime nextPurchaseDay(
  DcaPlan plan, {
  required DateTime after,
  required MarketCalendar calendar,
  required Exchange exchange,
}) {
  final from = plan.start.isAfter(after) ? plan.start : after;
  // A month, plus the longest closure a date can roll over.
  return dcaSchedule(
    start: plan.start,
    end: from.add(const Duration(days: 45)),
    frequency: plan.frequency,
    calendar: calendar,
    exchange: exchange,
  ).firstWhere((day) => day.isAfter(after));
}

DateTime _sameDayOfMonth(DateTime start, int monthsLater) {
  final lastDay = DateTime.utc(
    start.year,
    start.month + monthsLater + 1,
    0,
  ).day;
  return DateTime.utc(
    start.year,
    start.month + monthsLater,
    math.min(start.day, lastDay),
  );
}

/// One buy of a run.
final class Purchase {
  const Purchase({
    required this.date,
    required this.amount,
    required this.fees,
    required this.quantity,
    required this.price,
  });

  final DateTime date;

  /// The money put in, fees included.
  final Money amount;
  final Money fees;
  final Quantity quantity;

  /// The close it was bought at.
  final Price price;
}

/// A run's value on a date next to the money put in so far: one point of the
/// "value vs invested" chart.
final class ValuePoint {
  const ValuePoint(this.date, this.value, this.invested);
  final DateTime date;

  /// In EUR.
  final Decimal value;
  final Money invested;
}

final class InvestmentRun {
  const InvestmentRun({
    required this.purchases,
    required this.invested,
    required this.quantity,
    required this.finalValue,
    required this.series,
  });

  final List<Purchase> purchases;

  /// Money put in, fees included.
  final Money invested;
  final Quantity quantity;

  /// In EUR, at the last close on or before the end.
  final Decimal finalValue;

  /// One point per bar from the first purchase to the end.
  final List<ValuePoint> series;

  Decimal get gain => finalValue - invested.amount;

  /// Null when nothing was invested.
  Decimal? get gainRatio =>
      invested.isZero ? null : ratio(gain, invested.amount);
}

/// Buys the asset of [bars] with each flow at the close of the flow's date,
/// or of the next bar when that date has none (BRIEF §7.12). Each amount
/// includes its fees: `quantity = (amount − fees) / (close × rate)`, where
/// the FX fee is a share of the notional actually bought. [fxRate] gives EUR
/// per unit of the asset currency on a date (1 for EUR assets). Flows after
/// the last bar on or before [end] are not invested.
///
/// Fractional shares only: whole-share wallets trade through orders.
InvestmentRun investFlows(
  List<Flow> flows, {
  required List<PriceBar> bars,
  required Decimal Function(DateTime date) fxRate,
  required TradingRules rules,
  required DateTime end,
}) {
  if (!rules.fractionalShares) {
    throw ArgumentError('investFlows needs fractional shares');
  }
  final days = [...bars.where((b) => !b.date.isAfter(end))]
    ..sort((a, b) => a.date.compareTo(b.date));
  final purchases = <Purchase>[];
  final series = <ValuePoint>[];
  var invested = const Money.zero(Currency.eur);
  var quantity = const Quantity.zero();
  var next = 0;

  for (final bar in days) {
    final close = Price(bar.close, bar.currency);
    final rate = fxRate(bar.date);
    while (next < flows.length && !flows[next].date.isAfter(bar.date)) {
      final purchase = _buy(flows[next++].amount, close, rate, bar.date, rules);
      purchases.add(purchase);
      invested += purchase.amount;
      quantity += purchase.quantity;
    }
    if (purchases.isNotEmpty) {
      series.add(ValuePoint(bar.date, close.times(quantity) * rate, invested));
    }
  }
  return InvestmentRun(
    purchases: purchases,
    invested: invested,
    quantity: quantity,
    finalValue: series.isEmpty ? Decimal.zero : series.last.value,
    series: series,
  );
}

Purchase _buy(
  Money amount,
  Price close,
  Decimal fxRate,
  DateTime date,
  TradingRules rules,
) {
  final afterFixed = amount - rules.fixedFee;
  // notional + notional × FX fee rate = what is left after the fixed fee.
  final notional = close.currency == Currency.eur
      ? afterFixed
      : Money.book(
          ratio(afterFixed.amount, Decimal.one + rules.fxFeeRate),
          Currency.eur,
        );
  if (!notional.isPositive) {
    throw ArgumentError('$amount does not cover the fees');
  }
  return Purchase(
    date: date,
    amount: amount,
    fees: amount - notional,
    quantity: Quantity.truncate(ratio(notional.amount, close.value * fxRate)),
    price: close,
  );
}

final class LivretRun {
  const LivretRun({
    required this.invested,
    required this.uninvested,
    required this.finalValue,
    required this.series,
  });

  final Money invested;

  /// Money that did not fit under the ceiling and stayed as cash at 0 %.
  final Money uninvested;

  /// Livret balance + accrued interest + [uninvested], in EUR.
  final Decimal finalValue;

  /// One point per requested date.
  final List<ValuePoint> series;

  /// True when the ceiling kept part of the money out (shown in the UI).
  bool get capped => uninvested.isPositive;
}

/// The same [flows] put on a Livret A (BRIEF §4.11), valued on each of
/// [dates]. A deposit stops at the ceiling valid on its date; the rest stays
/// as cash (decided 2026-10-07) until a ceiling rise makes room for it
/// (decided 2026-10-24).
LivretRun livretFlows(
  List<Flow> flows, {
  required List<LivretRate> rates,
  required List<LivretCeiling> ceilings,
  required List<DateTime> dates,
}) {
  if (dates.isEmpty) {
    return LivretRun(
      invested: const Money.zero(Currency.eur),
      uninvested: const Money.zero(Currency.eur),
      finalValue: Decimal.zero,
      series: const [],
    );
  }
  final first = flows.isEmpty || dates.first.isBefore(flows.first.date)
      ? dates.first
      : flows.first.date;
  var account = LivretAccount.empty(first);
  var invested = const Money.zero(Currency.eur);
  var cash = const Money.zero(Currency.eur);
  final series = <ValuePoint>[];
  // A ceiling rise is a flow of nothing: the cash kept out goes in with it.
  final events = [
    ...flows,
    for (final c in ceilings)
      if (c.validFrom.isAfter(first))
        Flow(c.validFrom, const Money.zero(Currency.eur)),
  ]..sort((a, b) => a.date.compareTo(b.date));
  var next = 0;

  for (final date in dates) {
    while (next < events.length && !events[next].date.isAfter(date)) {
      final flow = events[next++];
      account = account.advanceTo(flow.date, rates);
      final ceiling = ceilingAt(flow.date, ceilings);
      final room = account.balance < ceiling
          ? ceiling - account.balance
          : const Money.zero(Currency.eur);
      final available = cash + flow.amount;
      final deposit = available < room ? available : room;
      if (deposit.isPositive) {
        account = account.apply(LivretMovement(flow.date, deposit));
      }
      invested += flow.amount;
      cash = available - deposit;
    }
    account = account.advanceTo(date, rates);
    series.add(
      ValuePoint(
        date,
        account.balance.amount + account.accrued + cash.amount,
        invested,
      ),
    );
  }
  return LivretRun(
    invested: invested,
    uninvested: cash,
    finalValue: series.last.value,
    series: series,
  );
}
