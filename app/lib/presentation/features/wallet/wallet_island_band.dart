import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/learning/content.dart';
import '../../../application/learning/island_path.dart';
import '../../../application/wallet/living_island.dart';
import '../../../application/wallet/wallet_overview.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/market/asset.dart';
import '../../../domain/wallet/wallet.dart';
import '../map/archipelago.dart';
import '../map/iso.dart';
import '../map/living_island.dart';

/// A wallet's island at the top of its screen (BRIEF §4.7, M11-4): its city
/// on a panel of sea, zoomed in so that each building is a touch target that
/// opens its asset. Before the first buy, the bare island and what it waits
/// for. Still, like the wallet's islet (M11-3).
class WalletIslandBand extends ConsumerWidget {
  const WalletIslandBand(this.o, {super.key});

  final WalletOverview o;

  static const height = 250.0;

  /// The island at the map's scale, its halo resting on the box's bottom.
  static const _drawn = Size(230, 240);

  /// Two neighbours' strips (25.5 px apart on the map) each a full 44 px
  /// target.
  static const _zoom = 1.75;

  /// The top of the drawn box the panel shows: room for the tallest building
  /// and its flag, the island's front edge left out.
  static const _top = 55.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final island = archipelago.firstWhere((i) => i.id == IslandId.actionsEtf);
    final standing = ref.watch(walletIslandProvider(o.id)).value ?? const [];
    final buildings = drawnBuildings(standing);
    final path = ref.watch(islandPathProvider(actionsEtfIsland)).value;
    final assets = <String, Asset>{
      for (final p in o.positions) p.asset.id: p.asset,
      for (final (:asset, order: _, reserved: _) in o.pendingOrders)
        asset.id: asset,
    };
    // The painter's canvas, on the drawn box: its halo on the bottom centre.
    final corner = island.halo.bottomCenter - _drawn.bottomCenter(Offset.zero);
    final rects = ArchipelagoPainter.buildingRects(island, buildings);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppShape.flatCardRadius),
      child: Container(
        height: height,
        color: AppColors.sea,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Transform(
                transform: Matrix4.identity()
                  ..translateByDouble(
                    box.maxWidth / 2 - _drawn.width / 2 * _zoom,
                    -_top * _zoom,
                    0,
                    1,
                  )
                  ..scaleByDouble(_zoom, _zoom, 1, 1),
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: _drawn.width,
                  maxWidth: _drawn.width,
                  minHeight: _drawn.height,
                  maxHeight: _drawn.height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Semantics(
                          image: true,
                          label: o.kind == WalletKind.live
                              ? l10n.wallets_islet_live
                              : l10n.wallets_islet_trip(o.name),
                          child: CustomPaint(
                            painter: ArchipelagoPainter(
                              buildings: buildings,
                              only: island,
                              grown: switch (path) {
                                final path? when path.nodes.isNotEmpty =>
                                  path.done / path.nodes.length,
                                _ => 1,
                              },
                            ),
                          ),
                        ),
                      ),
                      for (final (i, rect) in rects.indexed)
                        if (assets[standing[i].assetId] case final asset?)
                          Positioned.fromRect(
                            rect: rect.shift(-corner),
                            // Its own node, the tap its action: one stop
                            // per building for screen readers.
                            child: Semantics(
                              container: true,
                              button: true,
                              label: asset.name,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => context.push(
                                  '/asset/${asset.id}?wallet=${o.id}',
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: AppSpace.x4,
                right: AppSpace.x4,
                bottom: AppSpace.x3,
                child: Center(
                  child: DecoratedBox(
                    decoration: const ShapeDecoration(
                      color: AppColors.surface,
                      shape: StadiumBorder(
                        side: BorderSide(color: AppColors.ink, width: 2),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.x3,
                        vertical: AppSpace.x1,
                      ),
                      child: Text(
                        rects.isEmpty
                            ? l10n.wallet_island_empty
                            : l10n.wallet_island_hint,
                        style: AppText.label,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plot of the island with nothing on it yet but a foundation slab: what
/// a wallet's first buy will build on, on a square of sea.
class BarePlot extends StatelessWidget {
  const BarePlot({super.key});

  static const size = 76.0;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.sea,
        borderRadius: BorderRadius.circular(AppSpace.x3),
      ),
      child: const CustomPaint(painter: _PlotPainter()),
    ),
  );
}

class _PlotPainter extends CustomPainter {
  const _PlotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = IsoProjection(
      tile: size.width * 0.7,
      unit: size.width * 0.35,
      origin: Offset(size.width / 2, size.height * 0.42),
    );
    final pen = BlockPen(canvas, AppColors.ink, 1.6);
    pen
      ..block(boxFacets(p, -0.5, -0.5, 1, 1, 0.5, z: -0.5), MapPalette.dirt)
      ..block(
        boxFacets(p, -0.36, -0.36, 0.72, 0.72, 0.06),
        MapPalette.buildings.first.$1,
      );
  }

  @override
  bool shouldRepaint(_PlotPainter oldDelegate) => false;
}
