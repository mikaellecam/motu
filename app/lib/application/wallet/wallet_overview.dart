import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../domain/analytics/returns.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/price_bar.dart';
import '../../domain/wallet/dca.dart';
import '../../domain/wallet/order.dart';
import '../../domain/wallet/trip_engine.dart';
import '../../domain/wallet/valuation.dart';
import '../../domain/wallet/wallet.dart';

/// A price to value an asset with, and when it was observed (a live quote,
/// or the close of its bar).
final class ObservedPrice {
  const ObservedPrice(this.price, this.observedAt);
  final PriceAsOf price;
  final DateTime observedAt;
}

/// One row of the positions list (BRIEF §4.7).
final class PositionView {
  const PositionView({
    required this.asset,
    required this.quantity,
    required this.value,
    required this.pnlRatio,
  });

  final Asset asset;
  final Quantity quantity;

  /// Market value in EUR, unrounded.
  final Decimal value;

  /// Unrealised P&L over cost; null when the cost is zero.
  final Decimal? pnlRatio;
}

/// Everything the wallet screen shows, as of the wallet's clock.
final class WalletOverview {
  const WalletOverview({
    required this.id,
    required this.kind,
    required this.name,
    this.difficulty,
    this.status = WalletStatus.active,
    this.stops = const StopConditions(),
    this.monthlyContribution = const Money.zero(Currency.eur),
    required this.rules,
    required this.asOf,
    required this.pricesAsOf,
    required this.total,
    required this.invested,
    required this.availableCash,
    required this.moneyIn,
    required this.change,
    required this.changeRatio,
    required this.allocation,
    required this.positions,
    required this.pendingOrders,
    required this.series,
  });

  final String id;
  final WalletKind kind;
  final String name;

  /// A trip's difficulty id; null for the live wallet.
  final String? difficulty;
  final WalletStatus status;

  /// A trip's automatic stops and monthly contribution.
  final StopConditions stops;
  final Money monthlyContribution;
  final TradingRules rules;
  final DateTime asOf;

  /// When the oldest price on screen was observed; null without positions.
  final DateTime? pricesAsOf;

  /// Cash + positions + Livret, in EUR.
  final Decimal total;

  /// Market value of the positions now (« Investi », decided 2026-10-09).
  final Decimal invested;

  /// Cash not held back by pending buys (« Liquidités disponibles »).
  final Money availableCash;

  /// Starting cash plus contributions so far.
  final Money moneyIn;

  /// [total] − [moneyIn].
  final Decimal change;

  /// Time-weighted when contributions came in (BRIEF §7.6), else the change
  /// over the money put in; null when nothing was put in.
  final Decimal? changeRatio;

  /// Positions largest first, then cash, then the Livret.
  final List<AllocationLine> allocation;

  /// Open positions, largest first.
  final List<PositionView> positions;

  /// Orders waiting to fill, oldest first, with their asset (M4-6).
  final List<({Order order, Asset asset})> pendingOrders;

  /// The stored daily values, today's being the current value.
  final List<DailyValue> series;
}

DateTime _day(DateTime t) {
  final utc = t.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// Builds the overview of [wallet] at [asOf]. [prices] must cover every open
/// position and every pending order's asset, [fxRates] (EUR per unit) every
/// non-EUR currency among them; [livret] is the Livret balance with accrued
/// interest.
WalletOverview buildOverview({
  required WalletState wallet,
  required DateTime asOf,
  required Map<String, Asset> assets,
  required Map<String, ObservedPrice> prices,
  required Map<Currency, Decimal> fxRates,
  required Decimal livret,
}) {
  final day = _day(asOf);
  Decimal rateOf(Currency currency) =>
      currency == Currency.eur ? Decimal.one : fxRates[currency]!;

  final valuation = valueWallet(
    cash: wallet.cash,
    positions: wallet.positions,
    prices: {for (final e in prices.entries) e.key: e.value.price},
    fxRates: fxRates,
    livret: livret,
  );
  final total = valuation.total;

  var reserved = const Money.zero(Currency.eur);
  for (final order in wallet.pendingOrders) {
    final price = prices[order.assetId];
    if (price == null) {
      throw ArgumentError('No price for pending order ${order.id}');
    }
    reserved += cashToReserve(
      order,
      rules: wallet.params.rules,
      referencePrice: price.price.price,
      fxRate: rateOf(price.price.price.currency),
    );
  }

  final stored = [
    for (final v in wallet.values)
      if (!v.date.isAfter(day)) v,
  ];
  final now = Money.book(total, Currency.eur);
  final series = stored.isNotEmpty && stored.last.date == day
      ? [
          ...stored.take(stored.length - 1),
          DailyValue(date: day, value: now, flow: stored.last.flow),
        ]
      : [
          ...stored,
          DailyValue(
            date: day,
            value: now,
            flow: const Money.zero(Currency.eur),
          ),
        ];
  final moneyIn = series.fold(
    const Money.zero(Currency.eur),
    (sum, v) => sum + v.flow,
  );
  final contributed = series.skip(1).any((v) => !v.flow.isZero);

  final holdings = [...valuation.holdings]
    ..sort((a, b) => b.marketValue.compareTo(a.marketValue));
  final lines = valuation.allocation;
  final positionLines = lines.whereType<PositionLine>().toList()
    ..sort((a, b) => b.weight.compareTo(a.weight));

  return WalletOverview(
    id: wallet.id,
    kind: wallet.kind,
    name: wallet.name,
    difficulty: wallet.params.difficulty,
    status: wallet.status,
    stops: wallet.params.stops,
    monthlyContribution: wallet.params.monthlyContribution,
    rules: wallet.params.rules,
    asOf: asOf,
    pricesAsOf: holdings.isEmpty
        ? null
        : holdings
              .map((h) => prices[h.position.assetId]!.observedAt)
              .reduce((a, b) => a.isBefore(b) ? a : b),
    total: total,
    invested: holdings.fold(Decimal.zero, (sum, h) => sum + h.marketValue),
    availableCash: wallet.cash - reserved,
    moneyIn: moneyIn,
    change: total - moneyIn.amount,
    changeRatio: contributed
        ? timeWeightedReturn(series)
        : simpleReturn(moneyIn.amount, total),
    allocation: [...positionLines, ...lines.where((l) => l is! PositionLine)],
    positions: [
      for (final h in holdings)
        PositionView(
          asset: assets[h.position.assetId]!,
          quantity: h.position.quantity,
          value: h.marketValue,
          pnlRatio: h.unrealisedPnlRatio,
        ),
    ],
    pendingOrders: [
      for (final order in wallet.pendingOrders)
        (order: order, asset: assets[order.assetId]!),
    ],
    series: series,
  );
}

enum ChartPeriod { week, month, quarter, year, all }

enum Benchmark { world, livret }

/// The catalogue id of the « ETF Monde » benchmark (ADR-004).
const worldAssetId = 'world';

/// Points of the wallet chart over a period: the value, the money put in so
/// far (dashed baseline) and, when one is chosen, a benchmark that received
/// the same money on the same days.
final class ChartData {
  const ChartData({
    required this.dates,
    required this.values,
    required this.moneyIn,
    this.benchmark,
  });

  final List<DateTime> dates;
  final List<Decimal> values;
  final List<Decimal> moneyIn;
  final List<Decimal>? benchmark;
}

/// Money that came into the wallet from outside: the starting cash and the
/// contributions.
List<Flow> externalFlows(List<DailyValue> series) => [
  for (final v in series)
    if (!v.flow.isZero) Flow(v.date, v.flow),
];

/// The chart of [series] over [period], counted back from its last day. It
/// opens on the last day before the period, so the line starts where the
/// period started even when a day is missing. [benchmark] points are matched
/// to each day by the last one on or before it; before its first point the
/// money put in stands in (not invested yet).
ChartData chartFor(
  List<DailyValue> series,
  ChartPeriod period, {
  List<ValuePoint>? benchmark,
}) {
  if (series.isEmpty) {
    return const ChartData(dates: [], values: [], moneyIn: []);
  }
  final last = series.last.date;
  final start = switch (period) {
    ChartPeriod.week => last.subtract(const Duration(days: 7)),
    ChartPeriod.month => _monthsBefore(last, 1),
    ChartPeriod.quarter => _monthsBefore(last, 3),
    ChartPeriod.year => _monthsBefore(last, 12),
    ChartPeriod.all => series.first.date,
  };
  final dates = <DateTime>[];
  final values = <Decimal>[];
  final moneyIn = <Decimal>[];
  final matched = benchmark == null ? null : <Decimal>[];
  var putIn = Decimal.zero;
  var next = 0;
  Decimal? reference;
  final opening = series.lastIndexWhere((v) => !v.date.isAfter(start));
  for (var i = 0; i < series.length; i++) {
    final v = series[i];
    putIn += v.flow.amount;
    if (benchmark != null) {
      while (next < benchmark.length && !benchmark[next].date.isAfter(v.date)) {
        reference = benchmark[next++].value;
      }
    }
    if (i < opening) continue;
    dates.add(v.date);
    values.add(v.value.amount);
    moneyIn.add(putIn);
    matched?.add(reference ?? putIn);
  }
  return ChartData(
    dates: dates,
    values: values,
    moneyIn: moneyIn,
    benchmark: matched,
  );
}

/// [months] calendar months before [day], on the same day of the month or
/// the month's last day when it is shorter.
DateTime _monthsBefore(DateTime day, int months) {
  final lastDay = DateTime.utc(day.year, day.month - months + 1, 0).day;
  return DateTime.utc(
    day.year,
    day.month - months,
    day.day <= lastDay ? day.day : lastDay,
  );
}
