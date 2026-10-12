import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/clock/simulation_clock.dart';
import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../domain/analytics/decomposition.dart';
import '../../domain/analytics/drawdown.dart';
import '../../domain/analytics/returns.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/price_bar.dart';
import '../../domain/market/quote.dart';
import '../../domain/wallet/position.dart';
import '../../domain/wallet/wallet.dart';
import '../explorer/explorer.dart';
import '../learning/ui_level.dart';
import '../providers.dart';
import '../wallet/wallet_overview.dart' show worldAssetId;
import '../wallet/wallet_providers.dart' show liveQuotes;

part 'asset_page.g.dart';

/// The wallet's shares of the asset, valued now (BRIEF §4.8).
final class AssetPosition {
  const AssetPosition({
    required this.quantity,
    required this.value,
    required this.pnl,
    required this.pnlRatio,
    required this.currencyEffect,
  });

  final Quantity quantity;

  /// In EUR, unrounded.
  final Decimal value;
  final Decimal pnl;
  final Decimal? pnlRatio;

  /// The part of [pnl] the currency made.
  final Decimal currencyEffect;
}

/// Everything the asset page shows, as of the wallet's clock.
final class AssetOverview {
  const AssetOverview({
    required this.asset,
    required this.walletId,
    required this.asOf,
    required this.price,
    required this.observedAt,
    required this.fxRate,
    required this.sessionChange,
    required this.yearChange,
    required this.volatility,
    required this.riskBand,
    required this.yearDrawdown,
    required this.fxYearChange,
    required this.uiLevel,
    required this.position,
    required this.bars,
    required this.benchmark,
    required this.buys,
    required this.fx,
    this.tradable = true,
  });

  final Asset asset;
  final String walletId;
  final DateTime asOf;

  /// The live quote, or the last close.
  final Price price;
  final DateTime observedAt;

  /// EUR per unit of the price's currency now.
  final Decimal fxRate;

  /// Since the previous session's close; null without one.
  final Decimal? sessionChange;
  final Decimal? yearChange;
  final Decimal? volatility;
  final int? riskBand;

  /// Over the last year of closes.
  final Drawdown yearDrawdown;

  /// Change in the EUR value of one unit of the currency over a year; null
  /// for an EUR asset.
  final Decimal? fxYearChange;
  final int uiLevel;

  /// Null when the wallet holds none.
  final AssetPosition? position;

  /// Up to five years of closes, none after [asOf].
  final List<PriceBar> bars;

  /// The world ETF over the same days.
  final List<PriceBar> benchmark;

  /// The wallet's buys of the asset.
  final List<Fill> buys;

  /// EUR per unit of the asset's currency on a day of the window.
  final Decimal Function(DateTime day) fx;

  /// The wallet takes orders: false once a trip is finished (M5-5).
  final bool tradable;
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

/// Builds the overview of [asset] in [wallet] at [asOf] from its [bars] (up
/// to five years), the world ETF's, the live [quote] if any, and [fx].
AssetOverview buildAssetOverview({
  required Asset asset,
  required WalletState wallet,
  required DateTime asOf,
  required List<PriceBar> bars,
  required List<PriceBar> benchmark,
  required Quote? quote,
  required DateTime? closeObservedAt,
  required Decimal Function(DateTime day) fx,
  required int uiLevel,
}) {
  final day = _day(asOf);
  final known = [
    for (final b in bars)
      if (!b.date.isAfter(day)) b,
  ];
  final row = explorerRow(asset, bars: known, quote: quote, asOf: asOf);
  final price = row.price;
  if (price == null) throw DataUnavailableFailure(asOf);

  // A quote of a day without a bar yet moves from the last close; otherwise
  // the last close moves from the one before.
  final previous =
      quote != null &&
          known.isNotEmpty &&
          _day(quote.asOf).isAfter(known.last.date)
      ? known.last
      : known.length >= 2
      ? known[known.length - 2]
      : null;
  final yearAgo = yearBefore(day);
  final fxRate = asset.currency == Currency.eur ? Decimal.one : fx(day);

  AssetPosition? position;
  final held = wallet.positions[asset.id];
  if (held != null && held.isOpen) {
    final value = price.times(held.quantity) * fxRate;
    final pnl = value - held.costBasis;
    final average = averagePurchaseRate(wallet.fills, asset.id);
    position = AssetPosition(
      quantity: held.quantity,
      value: value,
      pnl: pnl,
      pnlRatio: held.costBasis == Decimal.zero
          ? null
          : ratio(pnl, held.costBasis),
      currencyEffect: average == null
          ? Decimal.zero
          : currencyEffect(
              quantity: held.quantity,
              price: price,
              fxNow: fxRate,
              averageRate: average,
            ),
    );
  }

  return AssetOverview(
    asset: asset,
    walletId: wallet.id,
    asOf: asOf,
    price: price,
    observedAt: quote?.asOf ?? closeObservedAt ?? day,
    fxRate: fxRate,
    sessionChange: previous == null
        ? null
        : simpleReturn(previous.close, price.value),
    yearChange: row.yearChange,
    volatility: row.volatility,
    riskBand: row.riskBand,
    yearDrawdown: maxDrawdown([
      for (final b in known)
        if (b.date.isAfter(yearAgo)) (b.date, b.close),
    ]),
    fxYearChange: switch (asset.currency == Currency.eur
        ? null
        : _rateOn(fx, yearAgo)) {
      final then? => simpleReturn(then, fxRate),
      null => null,
    },
    uiLevel: uiLevel,
    position: position,
    bars: known,
    benchmark: [
      for (final b in benchmark)
        if (!b.date.isAfter(day)) b,
    ],
    buys: [
      for (final f in wallet.fills)
        if (f.assetId == asset.id && f.side == Side.buy && !f.date.isAfter(day))
          f,
    ],
    fx: fx,
    tradable: wallet.status != WalletStatus.finished,
  );
}

/// The rate on [day]; null before the first published one (a trip in 2000
/// has no rate a year back).
Decimal? _rateOn(Decimal Function(DateTime day) fx, DateTime day) {
  try {
    return fx(day);
  } on DataUnavailableFailure {
    return null;
  }
}

enum AssetPeriod { week, month, year, fiveYears }

/// A buy drawn on the chart: at the chart day on or after it, at its price.
final class BuyMarker {
  const BuyMarker(this.index, this.price);
  final int index;
  final Decimal price;
}

/// The asset chart over a period (BRIEF §4.8).
final class AssetChart {
  const AssetChart({
    required this.dates,
    required this.closes,
    required this.buys,
    required this.drawdown,
    required this.benchmark,
    required this.decomposition,
  });

  final List<DateTime> dates;
  final List<Decimal> closes;
  final List<BuyMarker> buys;

  /// The worst fall over the period; depth 0 and no dates when none.
  final Drawdown drawdown;

  /// The world ETF rebased to the asset's first close (decided
  /// 2026-10-10); null when not asked for or unknown.
  final List<Decimal>? benchmark;

  /// « Pourquoi ça bouge ? » over the period: from its first close to the
  /// price now. Null without a world ETF close at the start.
  final MoveDecomposition? decomposition;
}

/// The chart of [o] over [period], counted back from its day and opening on
/// the last close before the period.
AssetChart assetChartFor(
  AssetOverview o,
  AssetPeriod period, {
  bool benchmark = false,
}) {
  final day = _day(o.asOf);
  final start = switch (period) {
    AssetPeriod.week => day.subtract(const Duration(days: 7)),
    AssetPeriod.month => _monthBefore(day),
    AssetPeriod.year => _yearsBefore(day, 1),
    AssetPeriod.fiveYears => _yearsBefore(day, 5),
  };
  final opening = o.bars.lastIndexWhere((b) => !b.date.isAfter(start));
  final points = o.bars.sublist(opening < 0 ? 0 : opening);
  final dates = [for (final b in points) b.date];
  final closes = [for (final b in points) b.close];
  if (points.isEmpty) {
    return AssetChart(
      dates: const [],
      closes: const [],
      buys: const [],
      drawdown: Drawdown(Decimal.zero),
      benchmark: null,
      decomposition: null,
    );
  }

  /// The world ETF's close on or before [date].
  PriceBar? world(DateTime date) {
    PriceBar? last;
    for (final b in o.benchmark) {
      if (b.date.isAfter(date)) break;
      last = b;
    }
    return last;
  }

  final worldStart = world(dates.first);
  final worldEnd = world(day);
  final inEur = o.asset.currency == Currency.eur;
  final fxStart = inEur ? null : _rateOn(o.fx, dates.first);

  return AssetChart(
    dates: dates,
    closes: closes,
    buys: [
      for (final buy in o.buys)
        if (!buy.date.isBefore(dates.first))
          if (dates.indexWhere((d) => !d.isBefore(buy.date)) case final i
              when i >= 0)
            BuyMarker(i, buy.price.value),
    ],
    drawdown: maxDrawdown([for (final b in points) (b.date, b.close)]),
    benchmark: !benchmark || worldStart == null
        ? null
        : [
            for (final date in dates)
              ratio(closes.first * world(date)!.close, worldStart.close),
          ],
    decomposition:
        worldStart == null || worldEnd == null || (!inEur && fxStart == null)
        ? null
        : decomposeMove(
            assetStart: Price(closes.first, o.price.currency),
            assetEnd: o.price,
            benchmarkStart: Price(worldStart.close, worldStart.currency),
            benchmarkEnd: Price(worldEnd.close, worldEnd.currency),
            fxStart: fxStart,
            fxEnd: inEur ? null : o.fxRate,
          ),
  );
}

DateTime _monthBefore(DateTime day) {
  final lastDay = DateTime.utc(day.year, day.month, 0).day;
  return DateTime.utc(
    day.year,
    day.month - 1,
    day.day <= lastDay ? day.day : lastDay,
  );
}

/// The asset page of [assetId] in [walletId] (the live wallet when null),
/// as of that wallet's clock.
@riverpod
Future<AssetOverview> assetOverview(
  Ref ref,
  String assetId,
  String? walletId,
) async {
  // Every dependency is read before the first await.
  final market = ref.watch(marketRepositoryProvider);
  final fxService = ref.watch(fxServiceProvider);
  final wallets = ref.watch(walletRepositoryProvider);
  final now = ref.watch(liveClockProvider).now();
  final level = ref.watch(currentUiLevelProvider.future);

  final wallet = await wallets.load(walletId ?? WalletRepository.liveWalletId);
  final live = wallet.kind == WalletKind.live;
  final asOf = live ? now : HistoricalClock(wallet.simDate!).now();
  final asset = [
    for (final a in await market.assets(asOf: asOf))
      if (a.id == assetId) a,
  ].firstOrNull;
  if (asset == null) throw const NotFoundFailure();

  final day = _day(asOf);
  final from = _yearsBefore(day, 5).subtract(const Duration(days: 10));
  final bars = await market.history(assetId, from: from, to: asOf, asOf: asOf);
  final world = assetId == worldAssetId
      ? bars
      : await market.history(worldAssetId, from: from, to: asOf, asOf: asOf);
  final quote = live
      ? (await liveQuotes(market, [assetId], asOf: asOf))[assetId]
      : null;
  final calendar = await market.calendar(
    {asset.exchange},
    fromYear: day.year - 1,
    toYear: day.year,
  );
  final lastClose = bars.where((b) => !b.date.isAfter(day)).lastOrNull;
  return buildAssetOverview(
    asset: asset,
    wallet: wallet,
    asOf: asOf,
    bars: bars,
    benchmark: world,
    quote: quote,
    closeObservedAt: lastClose == null
        ? null
        : calendar.closeAt(asset.exchange, lastClose.date),
    fx: await fxService.lookup(
      asset.currency,
      Currency.eur,
      start: from,
      asOf: asOf,
    ),
    uiLevel: await level,
  );
}

/// The asset chart over [period], with the world ETF when [benchmark].
@riverpod
Future<AssetChart> assetChart(
  Ref ref,
  String assetId,
  String? walletId,
  AssetPeriod period,
  bool benchmark,
) async => assetChartFor(
  await ref.watch(assetOverviewProvider(assetId, walletId).future),
  period,
  benchmark: benchmark,
);
