import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/content.dart';
import '../../../application/learning/island_path.dart';
import '../../../application/wallet/living_island.dart';
import '../../../core/theme/tokens.dart';
import '../map/archipelago.dart';
import '../map/living_island.dart';

/// A wallet's island on a square of sea, in its card of the Portefeuille tab
/// (BRIEF §4.5, M11-3): its buildings as the map draws them, on Actions & ETF
/// as the lessons greened it. Still: a list does not animate.
class WalletIslet extends ConsumerWidget {
  const WalletIslet({super.key, required this.walletId, required this.label});

  final String walletId;

  /// What screen readers say: whose island it is.
  final String label;

  static const size = 68.0;

  /// The island at the map's scale, scaled down to [size].
  static const _drawn = Size(230, 200);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buildings = drawnBuildings(
      ref.watch(walletIslandProvider(walletId)).value ?? const [],
    );
    final path = ref.watch(islandPathProvider(actionsEtfIsland)).value;
    return Semantics(
      image: true,
      label: label,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.sea,
          borderRadius: BorderRadius.circular(AppSpace.x3),
        ),
        child: FittedBox(
          child: SizedBox.fromSize(
            size: _drawn,
            child: CustomPaint(
              painter: ArchipelagoPainter(
                buildings: buildings,
                only: archipelago.firstWhere(
                  (i) => i.id == IslandId.actionsEtf,
                ),
                grown: switch (path) {
                  final path? when path.nodes.isNotEmpty =>
                    path.done / path.nodes.length,
                  _ => 1,
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
