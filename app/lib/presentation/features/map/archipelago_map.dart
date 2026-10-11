import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/wallet/island_buildings.dart';
import 'archipelago.dart';
import 'living_island.dart';

/// The archipelago, drawn in code, with pan and zoom (BRIEF §4.2). Each
/// island's label is its tap target and its screen-reader entry.
class ArchipelagoMap extends StatefulWidget {
  const ArchipelagoMap({
    super.key,
    required this.onOpen,
    this.buildings = const [],
  });

  /// Called with the playable island the user taps.
  final ValueChanged<IslandId> onOpen;

  /// The live wallet on Actions & ETF, the largest first (the living island,
  /// M7-2). A change animates in stages (BRIEF §10.5).
  final List<IslandBuilding> buildings;

  @override
  State<ArchipelagoMap> createState() => _ArchipelagoMapState();
}

class _ArchipelagoMapState extends State<ArchipelagoMap>
    with SingleTickerProviderStateMixin {
  final _geometry = ArchipelagoGeometry();
  final _transform = TransformationController();
  bool _centred = false;

  /// One staged run from [_from] to [_to] (BRIEF §10.5).
  late final _growth = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    value: 1,
  );
  late var _from = drawnBuildings(widget.buildings);
  late var _to = _from;

  List<DrawnBuilding> get _frame => islandFrame(_from, _to, _growth.value);

  @override
  void didUpdateWidget(ArchipelagoMap old) {
    super.didUpdateWidget(old);
    if (listEquals(old.buildings, widget.buildings)) return;
    _from = _frame;
    _to = drawnBuildings(widget.buildings);
    if (MediaQuery.disableAnimationsOf(context)) {
      _growth.value = 1;
    } else {
      _growth.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _growth.dispose();
    _transform.dispose();
    super.dispose();
  }

  /// Opens slightly zoomed out on the playable island, so its neighbours
  /// show at the edges and invite panning.
  static const initialScale = 0.75;

  void _centre(Size viewport) {
    if (_centred) return;
    _centred = true;
    final home = archipelago.firstWhere((i) => !i.locked);
    final target = _geometry.centre(home) * initialScale;
    _transform.value = Matrix4.diagonal3Values(initialScale, initialScale, 1)
      ..setTranslationRaw(
        viewport.width / 2 - target.dx,
        viewport.height / 2 - target.dy,
        0,
      );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _centre(constraints.biggest);
        return InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          // Never smaller than the opening view: labels stay ≥ 44 px.
          minScale: initialScale,
          maxScale: 2.5,
          boundaryMargin: const EdgeInsets.all(160),
          child: SizedBox.fromSize(
            size: _geometry.size,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _growth,
                    builder: (context, _) => CustomPaint(
                      painter: ArchipelagoPainter(_geometry, buildings: _frame),
                    ),
                  ),
                ),
                for (final island in archipelago)
                  _IslandLabel(
                    island: island,
                    anchor: _geometry.labelAnchor(island),
                    onTap: island.locked
                        ? null
                        : () => widget.onOpen(island.id),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IslandLabel extends StatelessWidget {
  const _IslandLabel({
    required this.island,
    required this.anchor,
    required this.onTap,
  });

  final IslandLayout island;
  final Offset anchor;
  final VoidCallback? onTap;

  static const _width = 160.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = islandName(l10n, island.id);
    final style = AppText.label.copyWith(
      color: island.locked ? AppColors.muted : AppColors.ink,
    );
    return Positioned(
      left: anchor.dx - _width / 2,
      top: anchor.dy + AppSpace.x2,
      width: _width,
      child: Semantics(
        button: onTap != null,
        label: island.locked ? l10n.map_island_locked(name) : name,
        // Excluding the child's semantics drops its tap action too.
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            // ≥ 44 px on screen even at the smallest zoom.
            constraints: BoxConstraints(
              minHeight: AppSpace.minTarget / _ArchipelagoMapState.initialScale,
            ),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppShape.chunkyButtonRadius),
                  ),
                  border: Border.all(
                    color: island.locked ? AppColors.line : AppColors.ink,
                    width: AppShape.chunkyBorder,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.x3,
                    vertical: AppSpace.x2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name, style: style, textAlign: TextAlign.center),
                      if (island.locked)
                        Text(
                          l10n.map_soon,
                          style: AppText.caption.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String islandName(AppLocalizations l10n, IslandId id) => switch (id) {
  IslandId.actionsEtf => l10n.island_actionsEtf,
  IslandId.trading => l10n.island_trading,
  IslandId.realEstate => l10n.island_realEstate,
  IslandId.crypto => l10n.island_crypto,
  IslandId.basics => l10n.island_basics,
};
