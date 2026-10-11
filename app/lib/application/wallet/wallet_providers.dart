import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/clock/simulation_clock.dart';
import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../data/repositories/market_repository.dart';
import '../../domain/livret/livret_interest.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/price_bar.dart';
import '../../domain/wallet/dca.dart';
import '../../domain/wallet/order.dart';
import '../../domain/wallet/wallet.dart';
import '../providers.dart';
import 'wallet_overview.dart';

part 'wallet_providers.g.dart';

/// The wallet [walletId] valued at its clock: today for the live wallet,
/// the simulated day for a trip (CLAUDE.md rule 3).
@riverpod
Future<WalletOverview> walletOverview(Ref ref, String walletId) async {
  // Every dependency is read before the first await: the provider may be
  // disposed while it waits.
  final market = ref.watch(marketRepositoryProvider);
  final fx = ref.watch(fxServiceProvider);
  final now = ref.watch(liveClockProvider).now();
  final wallet = await ref.watch(walletRepositoryProvider).load(walletId);
  final live = wallet.kind == WalletKind.live;
  final asOf = live ? now : HistoricalClock(wallet.simDate!).now();

  final ids = {
    for (final p in wallet.positions.values)
      if (p.isOpen) p.assetId,
    for (final o in wallet.pendingOrders) o.assetId,
  };
  final assets = {for (final a in await market.assets(asOf: asOf)) a.id: a};
  final prices = <String, ObservedPrice>{};
  for (final id in ids) {
    final asset = assets[id];
    if (asset == null) throw const NotFoundFailure();
    prices[id] = await priceOf(market, asset, asOf: asOf, live: live);
  }
  final fxRates = <Currency, Decimal>{
    for (final currency in {
      for (final p in prices.values) p.price.price.currency,
    }..remove(Currency.eur))
      currency: await fx.rate(currency, Currency.eur, asOf: asOf),
  };

  var livret = Decimal.zero;
  if (wallet.livretMovements.isNotEmpty) {
    final history = await market.livret(asOf: asOf);
    final account = livretAt(
      wallet.livretMovements,
      rates: history.rates,
      asOf: _day(asOf),
    );
    livret = account.balance.amount + account.accrued;
  }

  return buildOverview(
    wallet: wallet,
    asOf: asOf,
    assets: assets,
    prices: prices,
    fxRates: fxRates,
    livret: livret,
  );
}

/// The live wallet prices from quotes; a trip, or an asset without a quote,
/// from the last close on or before [asOf].
Future<ObservedPrice> priceOf(
  MarketRepository market,
  Asset asset, {
  required DateTime asOf,
  required bool live,
}) async {
  if (live) {
    final quote = await market.latest(asset.id, asOf: asOf);
    if (quote != null) {
      return ObservedPrice(
        PriceAsOf(quote.price, _day(quote.asOf), stale: false),
        quote.asOf,
      );
    }
  }
  final day = _day(asOf);
  final bars = await market.history(
    asset.id,
    from: day.subtract(const Duration(days: 31)),
    to: day,
    asOf: asOf,
  );
  final calendar = await market.calendar(
    {asset.exchange},
    fromYear: day.year - 1,
    toYear: day.year,
  );
  final price = closeAsOf(
    bars,
    asOf: day,
    expectedDate: calendar.onOrBefore(asset.exchange, day),
  );
  if (price == null) throw DataUnavailableFailure(asOf);
  return ObservedPrice(price, calendar.closeAt(asset.exchange, price.date));
}

/// What the wallet's money would be worth in [benchmark], put in on the
/// same days: the world ETF with the wallet's fees (fractional shares), or
/// the Livret A within its ceiling (BRIEF §4.7, §4.11).
@riverpod
Future<List<ValuePoint>> walletBenchmark(
  Ref ref,
  String walletId,
  Benchmark benchmark,
) async {
  if (benchmark == Benchmark.livret) {
    return (await ref.watch(walletLivretProvider(walletId).future)).series;
  }
  final market = ref.watch(marketRepositoryProvider);
  final fx = ref.watch(fxServiceProvider);
  final overview = await ref.watch(walletOverviewProvider(walletId).future);
  final asOf = overview.asOf;
  final start = overview.series.first.date;
  final bars = await market.history(
    worldAssetId,
    from: start,
    to: asOf,
    asOf: asOf,
  );
  if (bars.isEmpty) return const [];
  final rate = await fx.lookup(
    bars.first.currency,
    Currency.eur,
    start: start,
    asOf: asOf,
  );
  return investFlows(
    externalFlows(overview.series),
    bars: bars,
    fxRate: rate,
    rules: TradingRules(
      fxFeeRate: overview.rules.fxFeeRate,
      fixedFee: overview.rules.fixedFee,
      fractionalShares: true,
    ),
    end: _day(asOf),
  ).series;
}

/// The wallet's money put on a Livret A on the same days, within its
/// ceiling (BRIEF §4.11); its run says when the ceiling kept money out.
@riverpod
Future<LivretRun> walletLivret(Ref ref, String walletId) async {
  final market = ref.watch(marketRepositoryProvider);
  final overview = await ref.watch(walletOverviewProvider(walletId).future);
  final history = await market.livret(asOf: overview.asOf);
  return livretFlows(
    externalFlows(overview.series),
    rates: history.rates,
    ceilings: history.ceilings,
    dates: [for (final v in overview.series) v.date],
  );
}

/// The wallet chart over [period], with [benchmark] when one is chosen.
@riverpod
Future<ChartData> walletChart(
  Ref ref,
  String walletId,
  ChartPeriod period,
  Benchmark? benchmark,
) async {
  // Both start at once; each is awaited in turn so that a failure arrives as
  // itself (a record `.wait` wraps it in a ParallelWaitError).
  final overviewF = ref.watch(walletOverviewProvider(walletId).future)
    ..ignore();
  final pointsF = benchmark == null
      ? null
      : (ref.watch(walletBenchmarkProvider(walletId, benchmark).future)
          ..ignore());
  final overview = await overviewF;
  return chartFor(overview.series, period, benchmark: await pointsF);
}

DateTime _day(DateTime t) {
  final utc = t.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
