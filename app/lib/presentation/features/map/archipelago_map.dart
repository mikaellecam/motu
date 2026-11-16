import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chunky.dart';
import 'archipelago.dart';

/// The archipelago, drawn in code, fitted to the screen and still (BRIEF
/// §4.2, M12-12): no pan, no zoom. Each
/// island's label is its tap target and its screen-reader entry.
class ArchipelagoMap extends StatelessWidget {
  const ArchipelagoMap({
    super.key,
    required this.onOpen,
    this.progress = const {},
    this.opensAfter = const {},
    this.lessonsDone = const {},
  });

  /// Called with the playable island the user taps.
  final ValueChanged<IslandId> onOpen;

  /// Lessons done on each playable island, of all of them: its label shows
  /// them, and they build Les bases.
  final Map<IslandId, ({int done, int total})> progress;

  /// The lesson each closed island waits for, by name (M12-7): its pill says
  /// so instead of its progress.
  final Map<IslandId, String> opensAfter;

  /// The ids of the lessons done: each grows its building in Actions & ETF's
  /// district (M13-2).
  final Set<String> lessonsDone;

  /// How far Les bases' lessons have built it (M12-6).
  static double _built(({int done, int total})? progress) => switch (progress) {
    (:final done, :final total) when total > 0 => done / total,
    _ => 1,
  };

  /// The next-step card over the bottom of the map: the islands stay above.
  static const _cardRoom = 200.0;

  /// The scale that shows all five islands above the card, as the art
  /// direction does.
  static double fitScale(Size viewport) => math.min(
    viewport.width / mapSize.width,
    (viewport.height - _cardRoom) / mapSize.height,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        final scale = fitScale(viewport);
        final above = viewport.height - _cardRoom - mapSize.height * scale;
        // The whole archipelago, centred across, at the top.
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: (viewport.width - mapSize.width * scale) / 2,
              top: math.max(AppSpace.x2, above / 2),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: mapSize,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: ArchipelagoPainter(
                            lessonsDone: lessonsDone,
                            // Its ferry once the line from the port is open.
                            ferry: !opensAfter.containsKey(IslandId.actionsEtf),
                            // Built at once, as far as its lessons (M12-6).
                            grownBases: _built(progress[IslandId.basics]),
                          ),
                        ),
                      ),
                      for (final island in archipelago)
                        _IslandLabel(
                          island: island,
                          // ≥ 44 px on screen, whatever the scale.
                          target: AppSpace.minTarget / scale,
                          progress: progress[island.id],
                          opensAfter: opensAfter[island.id],
                          onTap: island.locked ? null : () => onOpen(island.id),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
    this.opensAfter,
  });

  final IslandLayout island;
  final ({int done, int total})? progress;
  final String? opensAfter;

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
          _ when opensAfter != null => l10n.map_island_closed(
            name,
            opensAfter!,
          ),
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
                  : _OpenPill(
                      name,
                      progress: opensAfter == null ? progress : null,
                      closed: opensAfter != null,
                      sink: sink,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenPill extends StatelessWidget {
  const _OpenPill(
    this.name, {
    required this.progress,
    required this.sink,
    this.closed = false,
  });
  final String name;
  final ({int done, int total})? progress;

  /// Its lessons wait for another island's (M12-7): a lock in place of its
  /// progress; the lesson it waits for in its label and on its path.
  final bool closed;

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
      child: Center(widthFactor: 1, heightFactor: 1, child: _line(context)),
    ),
  );

  /// Its name, then its lessons done, or a lock while it waits.
  Widget _line(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(
          name,
          style: AppText.titleSmall.copyWith(color: AppColors.ink),
          textAlign: TextAlign.center,
        ),
      ),
      if (closed) ...[
        const SizedBox(width: AppSpace.x2),
        const Icon(Icons.lock_outline, size: 18, color: AppColors.ink),
      ],
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
              AppLocalizations.of(context).map_island_progress(done, total),
              style: AppText.label.copyWith(
                color: AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    ],
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
