import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import 'archipelago.dart';

/// The archipelago, drawn in code, with pan and zoom (BRIEF §4.2). Each
/// island's label is its tap target and its screen-reader entry.
class ArchipelagoMap extends StatefulWidget {
  const ArchipelagoMap({
    super.key,
    required this.onOpen,
    this.buildingHeights = const [],
  });

  /// Called with the playable island the user taps.
  final ValueChanged<IslandId> onOpen;

  /// Heights of the Actions & ETF buildings (the living island, M7-2).
  final List<double> buildingHeights;

  @override
  State<ArchipelagoMap> createState() => _ArchipelagoMapState();
}

class _ArchipelagoMapState extends State<ArchipelagoMap> {
  final _geometry = ArchipelagoGeometry();
  final _transform = TransformationController();
  bool _centred = false;

  @override
  void dispose() {
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
                  child: CustomPaint(
                    painter: ArchipelagoPainter(
                      _geometry,
                      buildingHeights: widget.buildingHeights,
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
