import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../domain/wallet/wallet.dart';
import '../providers.dart';
import '../wallet/wallet_providers.dart';
import '../wallet/wallets_list.dart';
import 'trip_runner.dart';

part 'trip_catch_up.g.dart';

/// A trip that reached today goes on by itself, like the live wallet (BRIEF
/// §4.5, decided 2026-10-24): it moves to the last session that closed, its
/// pending orders, contributions and automatic stops included, as an advance
/// would. Runs at launch and on the trip's pull-to-refresh; a stopped or
/// finished trip waits. A failure stays in the state: offline, nothing
/// moves.
@Riverpod(keepAlive: true)
class TripCatchUp extends _$TripCatchUp {
  @override
  FutureOr<void> build() {}

  /// Catches up every trip at today, or only [walletId]. A call while one
  /// runs waits for that one.
  Future<void> run([String? walletId]) =>
      _running ??= _run(walletId).whenComplete(() => _running = null);

  Future<void>? _running;

  Future<void> _run(String? walletId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final trips = await ref
          .read(walletRepositoryProvider)
          .watchWallets()
          .first;
      Failure? failure;
      for (final trip in trips) {
        if (trip.kind != WalletKind.trip ||
            trip.status != WalletStatus.active ||
            !trip.reachedToday ||
            (walletId != null && trip.id != walletId)) {
          continue;
        }
        // One trip that cannot move does not hold back the others.
        try {
          if (await _catchUp(trip.id, from: trip.simDate!)) {
            ref
              ..invalidate(walletOverviewProvider(trip.id))
              ..invalidate(walletsListProvider);
          }
        } on Failure catch (f) {
          failure = f;
        }
      }
      if (failure != null) throw failure;
    });
  }

  /// Whether trip [walletId], on [from], moved.
  Future<bool> _catchUp(String walletId, {required DateTime from}) async {
    final market = ref.read(marketRepositoryProvider);
    final now = ref.read(liveClockProvider).now();
    final exchanges = {
      for (final a in await market.assets(asOf: from)) a.exchange,
    };
    final calendar = await market.calendar(
      exchanges,
      fromYear: from.year,
      toYear: now.toUtc().year,
    );
    final target = calendar.lastClosedDay(exchanges, after: from, now: now);
    if (target == null) return false;
    final advance = await moveTrip(ref, walletId, to: target);
    return advance.state.date.isAfter(from);
  }
}
