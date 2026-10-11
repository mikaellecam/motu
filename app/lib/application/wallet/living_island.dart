import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/wallet_repository.dart';
import '../../domain/wallet/island_buildings.dart';
import '../../domain/wallet/position.dart';
import 'wallet_providers.dart';

part 'living_island.g.dart';

/// The live wallet as the Actions & ETF island shows it (BRIEF §4.2): its
/// five largest positions, raised by the buys still waiting to fill. The
/// overview it reads is refreshed when an order is placed, filled or
/// cancelled, so the island follows.
@riverpod
Future<List<IslandBuilding>> livingIsland(Ref ref) async {
  final overview = await ref.watch(
    walletOverviewProvider(WalletRepository.liveWalletId).future,
  );
  final pending = <String, Decimal>{};
  for (final (:order, :asset, :reserved) in overview.pendingOrders) {
    if (order.side == Side.buy) {
      pending[asset.id] = (pending[asset.id] ?? Decimal.zero) + reserved.amount;
    }
  }
  return islandBuildings(
    held: {for (final p in overview.positions) p.asset.id: p.value},
    pending: pending,
  );
}
