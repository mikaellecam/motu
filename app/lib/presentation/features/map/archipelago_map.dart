import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chunky.dart';
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
    this.progress = const {},
  });

  /// Called with the playable island the user taps.
  final ValueChanged<IslandId> onOpen;

  /// The live wallet on Actions & ETF, the largest first (the living island,
  /// M7-2). A change animates in stages (BRIEF §10.5).
  final List<IslandBuilding> buildings;

  /// Lessons done on each playable island, of all of them: its label shows
  /// them, and they build it.
  final Map<IslandId, ({int done, int total})> progress;

  @override
  State<ArchipelagoMap> createState() => _ArchipelagoMapState();
}

class _ArchipelagoMapState extends State<ArchipelagoMap>
    with TickerProviderStateMixin {
  final _transform = TransformationController();
  bool _opened = false;

  /// One staged run from [_from] to [_to] (BRIEF §10.5).
  late final _growth = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    value: 1,
  );
  late var _from = drawnBuildings(widget.buildings);
  late var _to = _from;

  List<DrawnBuilding> get _frame => islandFrame(_from, _to, _growth.value);

  /// How far the lessons have greened Actions & ETF (M9-19): as the art
  /// direction draws it until its lessons are known.
  static double _greened(({int done, int total})? progress) =>
      switch (progress) {
        (:final done, :final total) when total > 0 => done / total,
        _ => 1,
      };

  /// The grass and trees easing to the lessons done.
  late final _green = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    value: _greened(widget.progress[IslandId.actionsEtf]),
  );

  @override
  void didUpdateWidget(ArchipelagoMap old) {
    super.didUpdateWidget(old);
    final still = MediaQuery.disableAnimationsOf(context);
    final greened = _greened(widget.progress[IslandId.actionsEtf]);
    if (greened != _greened(old.progress[IslandId.actionsEtf])) {
      // Lessons known at last: the island stands as it is, no greening
      // back from the full art.
      if (still || old.progress[IslandId.actionsEtf] == null) {
        _green.value = greened;
      } else {
        // Its whole duration, however small the step: animateTo alone
        // shortens it to the distance (a lesson, a twelfth).
        _green.animateTo(
          greened,
          duration: _green.duration,
          curve: Curves.easeInOut,
        );
      }
    }
    if (listEquals(old.buildings, widget.buildings)) return;
    _from = _frame;
    _to = drawnBuildings(widget.buildings);
    if (still) {
      _growth.value = 1;
    } else {
      _growth.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _growth.dispose();
    _green.dispose();
    _transform.dispose();
    super.dispose();
  }

  /// The next-step card over the bottom of the map: the islands stay above.
  static const _cardRoom = 200.0;

  /// The zoom that shows all five islands above the card, as the art
  /// direction does, and the smallest the map allows.
  static double fitScale(Size viewport) => math.max(
    0.5,
    math.min(
      viewport.width / mapSize.width,
      (viewport.height - _cardRoom) / mapSize.height,
    ),
  );

  /// Opens on the whole archipelago, centred across, at the top.
  void _open(Size viewport, double scale) {
    if (_opened) return;
    _opened = true;
    final above = viewport.height - _cardRoom - mapSize.height * scale;
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        (viewport.width - mapSize.width * scale) / 2,
        math.max(AppSpace.x2, above / 2),
        0,
      );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        final scale = fitScale(viewport);
        _open(viewport, scale);
        return InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          minScale: scale,
          maxScale: math.max(2.5, scale * 2),
          // Room to pan the islands anywhere on screen, not off it.
          boundaryMargin: EdgeInsets.symmetric(
            horizontal: viewport.width / scale / 2,
            vertical: viewport.height / scale,
          ),
          child: SizedBox.fromSize(
            size: mapSize,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_growth, _green]),
                    builder: (context, _) => CustomPaint(
                      painter: ArchipelagoPainter(
                        buildings: _frame,
                        grown: _green.value,
                        // Built at once, as far as its lessons (M12-6).
                        grownBases: _greened(widget.progress[IslandId.basics]),
                      ),
                    ),
                  ),
                ),
                for (final island in archipelago)
                  _IslandLabel(
                    island: island,
                    // ≥ 44 px on screen even at the smallest zoom.
                    target: AppSpace.minTarget / scale,
                    progress: widget.progress[island.id],
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

/// An island's name on the sea, as the art direction draws it: Actions & ETF
/// in a chunky pill, the locked islands in a thin one with a lock.
class _IslandLabel extends StatelessWidget {
  const _IslandLabel({
    required this.island,
    required this.target,
    required this.progress,
    required this.onTap,
  });

  final IslandLayout island;
  final ({int done, int total})? progress;

  /// The tap target's height, in map px.
  final double target;
  final VoidCallback? onTap;

  static const _width = 280.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = islandName(l10n, island.id);
    final anchor = island.labelAnchor;
    // The pill's top on the anchor; the target round its middle.
    final middle = anchor.dy + (island.locked ? 15 : 22);
    return Positioned(
      left: anchor.dx - _width / 2,
      top: middle - target / 2,
      width: _width,
      child: Semantics(
        button: onTap != null,
        label: switch (progress) {
          _ when island.locked => l10n.map_island_locked(name),
          (:final done, :final total) => l10n.map_island_open(
            name,
            done,
            total,
          ),
          null => name,
        },
        // Excluding the child's semantics drops its tap action too.
        onTap: onTap,
        excludeSemantics: true,
        child: ChunkyPress(
          depth: AppShape.chunkyButtonShadow,
          onTap: onTap,
          builder: (sink) => ConstrainedBox(
            constraints: BoxConstraints(minHeight: target),
            child: Center(
              child: island.locked
                  ? _LockedPill(name)
                  : _OpenPill(name, progress: progress, sink: sink),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenPill extends StatelessWidget {
  const _OpenPill(this.name, {required this.progress, required this.sink});
  final String name;
  final ({int done, int total})? progress;

  /// How far the pill is pressed down onto its shadow.
  final double sink;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(0, sink),
    child: Container(
      constraints: const BoxConstraints(minHeight: AppSpace.minTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: const StadiumBorder(
          side: BorderSide(color: AppColors.ink, width: AppShape.chunkyBorder),
        ),
        shadows: [
          BoxShadow(
            color: AppColors.ink,
            offset: Offset(0, AppShape.chunkyButtonShadow - sink),
          ),
        ],
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                style: AppText.titleSmall.copyWith(color: AppColors.ink),
                textAlign: TextAlign.center,
              ),
            ),
            if (progress case (:final done, :final total)) ...[
              const SizedBox(width: AppSpace.x2),
              DecoratedBox(
                decoration: const ShapeDecoration(
                  color: AppColors.progress,
                  shape: StadiumBorder(),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.x2,
                    vertical: 2,
                  ),
                  child: Text(
                    AppLocalizations.of(context)
                        .map_island_progress(done, total),
                    style: AppText.label.copyWith(
                      color: AppColors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _LockedPill extends StatelessWidget {
  const _LockedPill(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpace.x3,
      vertical: AppSpace.x1,
    ),
    decoration: const ShapeDecoration(
      color: AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: AppColors.muted, width: 2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline, size: 14, color: AppColors.muted),
        const SizedBox(width: AppSpace.x1),
        Flexible(
          child: Text(
            name,
            style: AppText.label.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    ),
  );
}

String islandName(AppLocalizations l10n, IslandId id) => switch (id) {
  IslandId.actionsEtf => l10n.island_actionsEtf,
  IslandId.trading => l10n.island_trading,
  IslandId.realEstate => l10n.island_realEstate,
  IslandId.crypto => l10n.island_crypto,
  IslandId.basics => l10n.island_basics,
};
