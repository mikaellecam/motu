import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/cache_status.dart';
import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../domain/learning/profile_rules.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/market_calendar.dart';
import '../../domain/market/price_bar.dart';
import '../../domain/wallet/trip_engine.dart';
import '../providers.dart';
import '../wallet/wallet_overview.dart' show worldAssetId;
import '../wallet/wallet_providers.dart';
import '../wallet/wallets_list.dart';

part 'trip_runner.g.dart';

/// The cached market a trip moves through, loaded before an advance: the
/// bars of the assets the trip holds or trades, and a rate lookup. The
/// engine never asks for a day after the target.
final class SnapshotTripMarket implements TripMarket {
  SnapshotTripMarket({
    required this.lastDate,
    required this._bars,
    required this._exchanges,
    required this._calendar,
    required this._usdEur,
  }) : _byDay = {
         for (final MapEntry(key: id, value: list) in _bars.entries)
           id: {for (final b in list) b.date: b},
       };

  @override
  final DateTime lastDate;
  final Map<String, List<PriceBar>> _bars;
  final Map<String, Map<DateTime, PriceBar>> _byDay;
  final Map<String, Exchange> _exchanges;
  final MarketCalendar _calendar;
  final Decimal Function(DateTime day) _usdEur;

  @override
  PriceBar? bar(String assetId, DateTime date) => _byDay[assetId]?[date];

  @override
  PriceAsOf? priceAsOf(String assetId, DateTime date) => closeAsOf(
    _bars[assetId] ?? const [],
    asOf: date,
    expectedDate: _calendar.onOrBefore(exchangeOf(assetId), date),
  );

  @override
  Decimal fxRate(Currency currency, DateTime date) =>
      currency == Currency.eur ? Decimal.one : _usdEur(date);

  @override
  Exchange exchangeOf(String assetId) => _exchanges[assetId]!;
}

/// How far a time control moves a trip (BRIEF §4.5).
enum TripStep { day, week, month }

/// The day [step] aims at from [from]: the next trip day, a week, or the
/// same day next month (its last day when shorter). The engine stops on the
/// last trip day on or before it.
DateTime stepTarget(
  TripStep step,
  DateTime from, {
  required bool Function(DateTime day) isTripDay,
}) {
  switch (step) {
    case TripStep.day:
      var day = DateTime.utc(from.year, from.month, from.day + 1);
      // The longest market closure since 2000 lasted 6 days.
      for (var i = 0; i < 14 && !isTripDay(day); i++) {
        day = DateTime.utc(day.year, day.month, day.day + 1);
      }
      return day;
    case TripStep.week:
      return DateTime.utc(from.year, from.month, from.day + 7);
    case TripStep.month:
      final last = DateTime.utc(from.year, from.month + 2, 0).day;
      return DateTime.utc(
        from.year,
        from.month + 1,
        from.day <= last ? from.day : last,
      );
  }
}

/// Moves trip [walletId] forward and books the result. Its state is the
/// last advance, while one runs or after it.
@riverpod
class TripRunner extends _$TripRunner {
  @override
  FutureOr<TripAdvance?> build(String walletId) => null;

  Future<void> advance(TripStep step) => _run(step: step);

  /// « Avancer jusqu'à… » [target] (checked with `checkForward`).
  Future<void> advanceTo(DateTime target) => _run(target: target);

  Future<void> _run({TripStep? step, DateTime? target}) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => moveTrip(ref, walletId, step: step, to: target),
    );
    ref
      ..invalidate(walletOverviewProvider(walletId))
      ..invalidate(walletsListProvider);
  }
}

/// Moves trip [walletId] by [step] or to [to], one trip day at a time, and
/// books the result: the time controls, and the catch-up of a trip at today
/// (BRIEF §4.5).
Future<TripAdvance> moveTrip(
  Ref ref,
  String walletId, {
  TripStep? step,
  DateTime? to,
}) async {
  final market = ref.read(marketRepositoryProvider);
  final wallets = ref.read(walletRepositoryProvider);
  final fx = ref.read(fxServiceProvider);
  final profile = await ref.read(profileRepositoryProvider).load();
  final wallet = await wallets.load(walletId);
  final from = wallet.simDate;
  if (from == null) throw const NotFoundFailure();

  final catalogue = await market.assets(asOf: from);
  final exchanges = {for (final Asset a in catalogue) a.id: a.exchange};
  final allExchanges = exchanges.values.toSet();
  var calendar = await market.calendar(
    allExchanges,
    fromYear: from.year,
    toYear: from.year + 1,
  );
  bool tripDay(DateTime d) =>
      allExchanges.any((e) => calendar.isTradingDay(e, d));
  final target = to ?? stepTarget(step!, from, isTripDay: tripDay);
  calendar = await market.calendar(
    allExchanges,
    fromYear: from.year,
    toYear: target.year + 1,
  );

  // The assets the trip holds or trades, and the world ETF for the last
  // day with data.
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
      id: await market.history(id, from: window, to: target, asOf: target),
  };
  final world = bars[worldAssetId]!;
  // The last day with data is known as of today, not as of the target: a
  // trip that reaches it is at today (BRIEF §4.5). Only its date reaches
  // the engine, never a price after the target.
  final now = ref.read(liveClockProvider).now();
  final ahead = await market.history(
    worldAssetId,
    from: target,
    to: now,
    asOf: now,
  );
  final lastDate = ahead.isNotEmpty
      ? ahead.last.date
      : world.isEmpty
      ? from
      : world.last.date;
  // Offline, the cache may stop short of the data: past it, the trip would
  // take the cache's end for today. It moves only within the cache (BRIEF
  // §6.4).
  if (lastDate.isBefore(target) && await market.status().first is! Fresh) {
    throw DataUnavailableFailure(target);
  }
  final livret = await market.livret(asOf: target);
  final before = await wallets.tripState(walletId, livretRates: livret.rates);
  final usdEur = await fx.lookup(
    Currency.usd,
    Currency.eur,
    start: window,
    asOf: target,
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
          lastDate: lastDate,
          bars: bars,
          exchanges: exchanges,
          calendar: calendar,
          usdEur: usdEur,
        ),
        // As live (M4-6): an order takes part from the first session that
        // opened after it was placed. Only a trip at today stamps its orders
        // with the real time; any other runs from the day after its own.
        eligible: (order, day) => calendar
            .openAt(exchanges[order.assetId]!, day)
            .isAfter(order.createdAt),
      );
  await wallets.saveAdvance(walletId, advance, before: before);
  return advance;
}
