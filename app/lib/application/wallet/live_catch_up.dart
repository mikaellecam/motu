import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/money/money.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../domain/learning/profile_rules.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/price_bar.dart';
import '../../domain/wallet/trip_engine.dart';
import '../providers.dart';
import '../trip/trip_runner.dart' show SnapshotTripMarket;
import 'wallet_overview.dart' show worldAssetId;
import 'wallet_providers.dart';
import 'wallets_list.dart';

part 'live_catch_up.g.dart';

/// Brings the live wallet up to the last session that closed (M4-6): its
/// pending orders fill on the bars they waited for, and each closed session
/// gets its end-of-day value. Runs at launch and on pull-to-refresh; its
/// state is the last catch-up, null when there was nothing to do. A failure
/// stays in the state: the wallet works offline on what it has.
@Riverpod(keepAlive: true)
class LiveCatchUp extends _$LiveCatchUp {
  @override
  FutureOr<TripAdvance?> build() => null;

  /// True once the wallet is caught up, false when the catch-up failed. A
  /// call while one runs waits for that one.
  Future<bool> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<bool>? _running;

  Future<bool> _run() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_catchUp);
    if (state.value != null) {
      ref
        ..invalidate(walletOverviewProvider(WalletRepository.liveWalletId))
        ..invalidate(walletsListProvider);
    }
    return !state.hasError;
  }

  Future<TripAdvance?> _catchUp() async {
    final market = ref.read(marketRepositoryProvider);
    final wallets = ref.read(walletRepositoryProvider);
    final fx = ref.read(fxServiceProvider);
    final now = ref.read(liveClockProvider).now().toUtc();
    final profile = await ref.read(profileRepositoryProvider).load();
    final wallet = await wallets.load(WalletRepository.liveWalletId);
    final last = wallet.values.last.date;
    final dayBefore = DateTime.utc(last.year, last.month, last.day - 1);

    final catalogue = await market.assets(asOf: now);
    final exchanges = {for (final Asset a in catalogue) a.id: a.exchange};
    final allExchanges = exchanges.values.toSet();
    final calendar = await market.calendar(
      allExchanges,
      fromYear: dayBefore.year,
      toYear: now.year,
    );
    // Never caught up, and created before its first day's sessions closed:
    // its start value came before them, so that day runs too and its close
    // replaces it (M12-13, decided 2026-10-28).
    var firstDay = false;
    if (!await wallets.everAdvanced(WalletRepository.liveWalletId)) {
      final created = await wallets.createdAt(WalletRepository.liveWalletId);
      firstDay = allExchanges.any(
        (e) =>
            calendar.isTradingDay(e, last) &&
            calendar.closeAt(e, last).isAfter(created),
      );
    }
    final from = firstDay ? dayBefore : last;

    final target = calendar.lastClosedDay(allExchanges, after: from, now: now);
    if (target == null) return null;

    final ids = {
      worldAssetId,
      for (final p in wallet.positions.values)
        if (p.isOpen) p.assetId,
      for (final o in wallet.pendingOrders) o.assetId,
      for (final plan in wallet.plans)
        if (plan.active) plan.assetId,
    };
    final window = from.subtract(const Duration(days: 31));
    final bars = <String, List<PriceBar>>{
      for (final id in ids)
        id: await market.history(id, from: window, to: target, asOf: now),
    };
    final world = bars[worldAssetId]!;
    final livret = await market.livret(asOf: now);
    // Past sessions are valued with the holdings of now: no fill at the
    // quote is booked before they are (the order ticket waits for this).
    final live = await wallets.liveState(livretRates: livret.rates);
    final before = firstDay ? live.copyWith(date: from) : live;
    final usdEur = await fx.lookup(
      Currency.usd,
      Currency.eur,
      start: window,
      asOf: now,
    );

    final advance =
        TripEngine(
          calendar: calendar,
          exchanges: allExchanges,
          livretRates: livret.rates,
          rules: wallet.params.rules,
          monthlyContribution: wallet.params.monthlyContribution,
          thresholds: profile == null
              ? MomentThresholds(concentration: Decimal.parse('0.40'))
              : momentThresholds(profile),
        ).advance(
          before,
          target: target,
          stops: wallet.params.stops,
          market: SnapshotTripMarket(
            lastDate: world.isEmpty ? from : world.last.date,
            bars: bars,
            exchanges: exchanges,
            calendar: calendar,
            usdEur: usdEur,
          ),
          // An order takes part from the first session that opened after it
          // was placed: a limit set mid-session never fills on that
          // session's earlier prices.
          eligible: (order, day) => calendar
              .openAt(exchanges[order.assetId]!, day)
              .isAfter(order.createdAt),
        );
    if (!advance.state.date.isAfter(before.date)) return null;
    await wallets.saveAdvance(
      WalletRepository.liveWalletId,
      advance,
      before: before,
    );
    return advance;
  }
}
