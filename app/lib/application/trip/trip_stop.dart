import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../domain/market/asset.dart';
import '../../domain/wallet/position.dart';
import '../../domain/wallet/stop_decision.dart';
import '../../domain/wallet/trip_engine.dart';
import '../providers.dart';
import '../wallet/wallet_providers.dart';
import '../wallet/wallets_list.dart';

part 'trip_stop.g.dart';

/// What fell, against the line it crossed: the wallet's value and its stop
/// line (money put in × (1 − drawdown)) for a portfolio drop; the position's
/// value as now held and its line (cost × (1 − loss)) for a position drop.
final class StopChart {
  const StopChart(this.dates, this.values, this.threshold);
  final List<DateTime> dates;
  final List<Decimal> values;
  final List<Decimal> threshold;
}

/// The automatic-stop screen (BRIEF §4.5).
final class StopView {
  const StopView({
    required this.walletId,
    required this.date,
    required this.reasons,
    required this.assetNames,
    required this.chart,
  });

  final String walletId;

  /// The trip's day.
  final DateTime date;
  final List<StopReason> reasons;

  /// Names of the assets the reasons are about, by id, including the asset
  /// of a filled order (under its order id).
  final Map<String, String> assetNames;
  final StopChart? chart;

  bool get dropStop => isDropStop(reasons);
}

/// The journal's event id of the stop on [date].
String stopEventId(DateTime date) =>
    'stop-${date.toIso8601String().substring(0, 10)}';

@riverpod
Future<StopView> tripStop(Ref ref, String walletId) async {
  final wallets = ref.watch(walletRepositoryProvider);
  final market = ref.watch(marketRepositoryProvider);
  final fx = ref.watch(fxServiceProvider);
  final wallet = await wallets.load(walletId);
  final date = wallet.simDate;
  if (date == null) throw const NotFoundFailure();
  final reasons = wallet.stopReasons;
  final assets = {
    for (final Asset a in await market.assets(asOf: date)) a.id: a,
  };
  final names = <String, String>{};
  for (final r in reasons) {
    switch (r) {
      case PositionLossStop(:final assetId):
        names[assetId] = assets[assetId]?.name ?? assetId;
      case OrderFilledStop(:final orderId):
        final asset = await wallets.orderAsset(orderId);
        if (asset != null) names[orderId] = assets[asset]?.name ?? asset;
      case DrawdownStop() || ContributionStop():
        break;
    }
  }

  StopChart? chart;
  final drawdown = wallet.params.stops.drawdown ?? Decimal.zero;
  final positionDrop = reasons.whereType<PositionLossStop>().firstOrNull;
  if (reasons.any((r) => r is DrawdownStop)) {
    var putIn = Decimal.zero;
    final threshold = <Decimal>[];
    for (final v in wallet.values) {
      putIn += v.flow.amount;
      threshold.add(putIn * (Decimal.one - drawdown));
    }
    chart = StopChart(
      [for (final v in wallet.values) v.date],
      [for (final v in wallet.values) v.value.amount],
      threshold,
    );
  } else if (positionDrop != null) {
    final position = wallet.positions[positionDrop.assetId];
    final asset = assets[positionDrop.assetId];
    final firstBuy = wallet.fills
        .where((f) => f.assetId == positionDrop.assetId && f.side == Side.buy)
        .firstOrNull
        ?.date;
    if (position != null && asset != null && firstBuy != null) {
      final bars = await market.history(
        asset.id,
        from: firstBuy,
        to: date,
        asOf: date,
      );
      final rate = await fx.lookup(
        asset.currency,
        Currency.eur,
        start: firstBuy,
        asOf: date,
      );
      final line =
          position.costBasis *
          (Decimal.one - (wallet.params.stops.positionLoss ?? Decimal.zero));
      chart = StopChart(
        [for (final b in bars) b.date],
        [
          for (final b in bars)
            b.close * position.quantity.toDecimal() * rate(b.date),
        ],
        [for (final _ in bars) line],
      );
    }
  }
  return StopView(
    walletId: walletId,
    date: date,
    reasons: reasons,
    assetNames: names,
    chart: chart,
  );
}

/// Records the user's answer and sets the trip going again.
@riverpod
class StopActions extends _$StopActions {
  @override
  FutureOr<void> build(String walletId) {}

  Future<void> decide(StopDecision decision, {String? reason}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final wallets = ref.read(walletRepositoryProvider);
      final wallet = await wallets.load(walletId);
      final date = wallet.simDate!;
      final text = reason?.trim();
      await wallets.decide(
        walletId,
        simDate: date,
        eventId: stopEventId(date),
        decision: decision.id,
        sells: stopSells(
          decision,
          reasons: wallet.stopReasons,
          positions: wallet.positions,
          date: date,
          fractional: wallet.params.rules.fractionalShares,
        ),
        reason: text == null || text.isEmpty ? null : text,
      );
    });
    _refresh();
  }

  Future<void> updateStops(StopConditions stops) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(walletRepositoryProvider).updateStops(walletId, stops),
    );
    _refresh();
  }

  void _refresh() => ref
    ..invalidate(walletOverviewProvider(walletId))
    ..invalidate(tripStopProvider(walletId))
    ..invalidate(walletsListProvider);
}
