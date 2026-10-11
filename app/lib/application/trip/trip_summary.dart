import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../domain/analytics/returns.dart';
import '../../domain/learning/content.dart';
import '../../domain/wallet/position.dart';
import '../../domain/wallet/trip_summary.dart';
import '../learning/content.dart';
import '../providers.dart';
import '../wallet/wallet_overview.dart';
import '../wallet/wallet_providers.dart';
import '../wallet/wallets_list.dart';

part 'trip_summary.g.dart';

/// The rows of the comparison (BRIEF §4.5): the trip, then the same money
/// elsewhere.
enum Outcome { you, world, livret, worst }

/// Where the trip's money ends up in one [outcome].
final class OutcomeRow {
  const OutcomeRow(
    this.outcome, {
    required this.value,
    required this.twr,
    this.date,
  });

  final Outcome outcome;

  /// In EUR at the end of the trip, unrounded.
  final Decimal value;

  /// Time-weighted return over the trip (BRIEF §7.6).
  final Decimal twr;

  /// The day of « Ta pire décision ».
  final DateTime? date;
}

/// A journal entry and what happened after it.
final class ReplayLine {
  const ReplayLine(this.entry, {this.sold = const [], this.moved});
  final JournalEntry entry;

  /// The names of the assets a sell sold; empty when it did not fill.
  final List<String> sold;

  /// See [movedAfter].
  final Decimal? moved;
}

/// The end-of-trip summary (BRIEF §4.5).
final class TripSummary {
  const TripSummary({
    required this.name,
    required this.start,
    required this.end,
    required this.moneyIn,
    required this.outcomes,
    required this.livretCapped,
    required this.journal,
    required this.terms,
  });

  final String name;
  final DateTime start;
  final DateTime end;
  final Money moneyIn;

  /// [Outcome.you] first; « Sans rien toucher » without world ETF data and
  /// « Ta pire décision » without a sell are left out.
  final List<OutcomeRow> outcomes;

  /// The Livret ceiling kept part of the money out (BRIEF §4.11).
  final bool livretCapped;
  final List<ReplayLine> journal;

  /// The glossary terms met (decided 2026-10-11), as the content pack has
  /// them.
  final List<GlossaryTerm> terms;
}

/// The summary of trip [walletId] on its current day.
@riverpod
Future<TripSummary> tripSummary(Ref ref, String walletId) async {
  final market = ref.watch(marketRepositoryProvider);
  final fx = ref.watch(fxServiceProvider);
  final wallets = ref.watch(walletRepositoryProvider);
  // Everything starts at once; each is awaited in turn so that a failure
  // arrives as itself (a record `.wait` wraps it in a ParallelWaitError).
  final overviewF = ref.watch(walletOverviewProvider(walletId).future)
    ..ignore();
  final worldF = ref.watch(
    walletBenchmarkProvider(walletId, Benchmark.world).future,
  )..ignore();
  final livretF = ref.watch(walletLivretProvider(walletId).future)..ignore();
  final packF = ref.watch(contentPackProvider(actionsEtfIsland).future)
    ..ignore();
  final walletF = wallets.load(walletId)..ignore();
  final journalF = wallets.journal(walletId)..ignore();
  final momentsF = wallets.moments(walletId)..ignore();
  final overview = await overviewF;
  final world = await worldF;
  final livret = await livretF;
  final pack = await packF;
  final wallet = await walletF;
  final journal = await journalF;
  final moments = await momentsF;
  final end = overview.asOf;
  final assets = {for (final a in await market.assets(asOf: end)) a.id: a};

  Future<Decimal> eurPer(Currency currency, DateTime asOf) async =>
      currency == Currency.eur
      ? Decimal.one
      : await fx.rate(currency, Currency.eur, asOf: asOf);
  Future<Price> closeOf(String assetId, DateTime asOf) async {
    final asset = assets[assetId];
    if (asset == null) throw const NotFoundFailure();
    return (await priceOf(market, asset, asOf: asOf, live: false)).price.price;
  }

  // What selling everything would have cost on each day the journal sold.
  final sells = journal.where((e) => e.isSell).toList();
  final fees = <DateTime, Money>{};
  for (final e in sells) {
    final held = positionsFrom(
      wallet.fills.where((f) => !f.date.isAfter(e.date)),
    );
    final prices = {
      for (final p in held.values.where((p) => p.isOpen))
        p.assetId: await closeOf(p.assetId, e.date),
    };
    final eurRates = {
      for (final c in {for (final p in prices.values) p.currency})
        c: await eurPer(c, e.date),
    };
    fees[e.date] = sellAllFees(
      held,
      prices: prices,
      fxRate: (c) => eurRates[c]!,
      rules: wallet.params.rules,
    );
  }
  final worst = worstSell(overview.series, fees);

  // The sold shares, valued at the end of the trip.
  final endPrices = <String, Decimal>{};
  for (final f in [for (final e in sells) ...soldBy(e, wallet.fills)]) {
    final close = await closeOf(f.assetId, end);
    endPrices[f.assetId] = close.value * await eurPer(close.currency, end);
  }

  return TripSummary(
    name: overview.name,
    start: overview.series.first.date,
    end: end,
    moneyIn: overview.moneyIn,
    outcomes: [
      OutcomeRow(
        Outcome.you,
        value: overview.total,
        twr: timeWeightedReturn(overview.series),
      ),
      if (world.isNotEmpty)
        OutcomeRow(
          Outcome.world,
          value: world.last.value,
          twr: timeWeightedReturn(asDailyValues(world)),
        ),
      OutcomeRow(
        Outcome.livret,
        value: livret.finalValue,
        twr: timeWeightedReturn(asDailyValues(livret.series)),
      ),
      if (worst != null)
        OutcomeRow(
          Outcome.worst,
          value: worst.series.last.value.amount,
          twr: timeWeightedReturn(worst.series),
          date: worst.date,
        ),
    ],
    livretCapped: livret.capped,
    journal: [
      for (final e in journal)
        ReplayLine(
          e,
          sold: [
            for (final f in soldBy(e, wallet.fills))
              assets[f.assetId]?.name ?? f.assetId,
          ],
          moved: movedAfter(
            e,
            series: overview.series,
            fills: wallet.fills,
            endPrices: endPrices,
          ),
        ),
    ],
    terms: [for (final id in termsMet(moments)) ?pack.glossary[id]],
  );
}

/// Ends trip [walletId] by hand (BRIEF §4.5: « any time »).
@riverpod
class TripFinish extends _$TripFinish {
  @override
  FutureOr<void> build(String walletId) {}

  Future<void> finish() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(walletRepositoryProvider).finish(walletId),
    );
    ref
      ..invalidate(walletOverviewProvider(walletId))
      ..invalidate(walletsListProvider);
  }
}
