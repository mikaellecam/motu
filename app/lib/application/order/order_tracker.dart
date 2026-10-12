import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/clock/simulation_clock.dart';
import '../../core/failure.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../domain/market/asset.dart';
import '../../domain/wallet/order.dart';
import '../../domain/wallet/wallet.dart';
import '../asset/asset_page.dart';
import '../providers.dart';
import '../wallet/wallet_providers.dart';
import '../wallet/wallets_list.dart';

part 'order_tracker.g.dart';

/// An order on its screen (BRIEF §4.6: sent → market opens → executed).
final class OrderView {
  const OrderView({
    required this.detail,
    required this.asset,
    required this.trip,
    this.opensAt,
    this.opened = false,
  });

  final OrderDetail detail;
  final Asset asset;

  /// A trip order: it goes when the trip moves on.
  final bool trip;

  /// A live market order that waited: sent while its market was closed, or
  /// offline (BRIEF §14.1); the session open it fills at. Null for one
  /// filled at the quote.
  final DateTime? opensAt;

  /// [opensAt] has passed: the outcome shows once the session has closed.
  final bool opened;
}

/// Where order [orderId] stands, and « Annuler l'ordre » while it waits.
@riverpod
class OrderTracker extends _$OrderTracker {
  @override
  Future<OrderView> build(String orderId) async {
    final wallets = ref.watch(walletRepositoryProvider);
    final market = ref.watch(marketRepositoryProvider);
    final now = ref.watch(liveClockProvider).now();
    final detail = await wallets.orderDetail(orderId);
    if (detail == null) throw const NotFoundFailure();
    final wallet = await wallets.load(detail.walletId);
    final trip = wallet.kind == WalletKind.trip;
    final asOf = trip ? HistoricalClock(wallet.simDate!).now() : now;
    final asset = (await market.assets(asOf: asOf))
        .where((a) => a.id == detail.order.assetId)
        .firstOrNull;
    if (asset == null) throw const NotFoundFailure();

    final order = detail.order;
    DateTime? opensAt;
    if (!trip && order.type == OrderType.market) {
      final created = order.createdAt;
      final calendar = await market.calendar(
        {asset.exchange},
        fromYear: created.year,
        toYear: created.year + 1,
      );
      // Filled at the quote: open when sent, filled that same day.
      final fill = detail.fill?.date;
      final atQuote =
          calendar.isOpen(asset.exchange, created) &&
          fill != null &&
          _day(fill) == _day(created);
      if (!atQuote) opensAt = calendar.nextOpen(asset.exchange, created);
    }
    return OrderView(
      detail: detail,
      asset: asset,
      trip: trip,
      opensAt: opensAt,
      opened: opensAt != null && !now.isBefore(opensAt),
    );
  }

  /// Cancels the order if it still waits; the screen then shows where it
  /// stands, cancelled or filled in the meantime.
  Future<void> cancel() async {
    final view = await future;
    await ref.read(walletRepositoryProvider).cancelByUser(orderId);
    final walletId = view.detail.walletId;
    ref
      ..invalidate(walletOverviewProvider(walletId))
      ..invalidate(assetOverviewProvider(view.asset.id, walletId))
      ..invalidate(walletsListProvider)
      ..invalidateSelf();
  }
}

DateTime _day(DateTime t) {
  final u = t.toUtc();
  return DateTime.utc(u.year, u.month, u.day);
}
