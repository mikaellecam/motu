import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/learning/island_path.dart';
import '../../../application/wallet/living_island.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/learning/node.dart';
import '../../../domain/learning/path.dart';
import '../map/archipelago.dart';
import '../map/living_island.dart';
import '../node/node_screen.dart';
import 'islet_path.dart';

/// An island's path (BRIEF §3, §4.3), as the art direction's « stepping
/// islets »: the island on the sea, its progress, then each lesson on an
/// islet, a bridge built from each one done, and the current lesson's card.
/// A lesson that is not locked opens its player; coming back shows the new
/// progress.
class IslandScreen extends ConsumerWidget {
  const IslandScreen({super.key, required this.islandId});

  final String islandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(islandPathProvider(islandId));
    final inset = MediaQuery.paddingOf(context);
    return Scaffold(
      // World screens sit on the sea (BRIEF §10.2).
      backgroundColor: AppColors.sea,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Stack(
          children: [
            switch (state) {
              AsyncValue(:final value?) => SingleChildScrollView(
                padding: EdgeInsets.only(top: inset.top, bottom: inset.bottom),
                child: _Path(islandId: islandId, path: value),
              ),
              AsyncValue(:final error?) => Center(
                child: ErrorView(
                  failure: error is Failure ? error : const ServerFailure(),
                  onRetry: () => ref.invalidate(islandPathProvider(islandId)),
                ),
              ),
              _ => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.screenPadding,
                    _backRoom,
                    AppSpace.screenPadding,
                    AppSpace.screenPadding,
                  ),
                  child: const AsyncSkeleton(lines: 6),
                ),
              ),
            },
            // The path scrolls under the status bar, never into it.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: inset.top,
              child: const ColoredBox(color: AppColors.sea),
            ),
            // Over the island once the path is shown, scrolling with it.
            if (!state.hasValue)
              Positioned(
                left: AppSpace.screenPadding,
                top: inset.top + AppSpace.x3,
                child: const _Back(),
              ),
          ],
        ),
      ),
    );
  }
}

final _actionsEtf = archipelago.firstWhere((i) => i.id == IslandId.actionsEtf);

class _Path extends ConsumerWidget {
  const _Path({required this.islandId, required this.path});

  final String islandId;
  final IslandPathView path;

  /// Above the first islet, under the header or the card: room for the
  /// current lesson's bubble and its ring.
  static const _above = 76.0;

  /// Between the current lesson's islet and its card, and under the last
  /// islet.
  static const _toCard = AppSpace.x4;
  static const _below = 52.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final states = [for (final n in path.nodes) n.state];
    final current = states.indexOf(NodeState.current);
    final cut = current < 0 ? states.length : current + 1;
    final open = [
      for (final n in path.nodes)
        n.state == NodeState.locked
            ? null
            : () => context.push('/node/${n.node.id}'),
    ];
    final island = archipelago.where((i) => i.pack == islandId).firstOrNull;
    final grown = path.nodes.isEmpty ? 1.0 : path.done / path.nodes.length;
    // Offline or still loading, the island stands as it last did, or bare.
    // The wallet's buildings stand on Actions & ETF only.
    final buildings = island?.id != IslandId.actionsEtf
        ? const <DrawnBuilding>[]
        : drawnBuildings(ref.watch(livingIslandProvider).value ?? const []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: island == null ? _backRoom : 240,
          child: Stack(
            children: [
              if (island != null)
                Positioned.fill(
                  // Every island as wide as Actions & ETF's (M12-6).
                  child: Transform.scale(
                    scale: _actionsEtf.halo.width / island.halo.width,
                    alignment: Alignment.bottomCenter,
                    child: CustomPaint(
                      painter: ArchipelagoPainter(
                        buildings: buildings,
                        only: island,
                        // Grown by the lessons below it (M9-19, M12-6).
                        grown: grown,
                        grownBases: grown,
                      ),
                    ),
                  ),
                ),
              const Positioned(
                left: AppSpace.screenPadding,
                top: AppSpace.x3,
                child: _Back(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.screenPadding,
          ),
          child: _Header(path: path, language: language),
        ),
        if (cut > 0)
          _Run(
            run: IsletRun(
              states,
              first: 0,
              end: cut,
              top: _above,
              bottom: current < 0 ? _below : _toCard,
            ),
            path: path,
            open: open,
          ),
        if (current >= 0)
          Padding(
            // The card's shadow, kept clear of the route under it.
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screenPadding,
              0,
              AppSpace.screenPadding,
              AppShape.chunkyCardShadow,
            ),
            child: _CurrentCard(
              type: nodeTypeName(l10n, path.nodes[current].node.type),
              title: path.nodes[current].node.title.of(language),
              onStart: open[current],
            ),
          ),
        if (cut < states.length)
          _Run(
            run: IsletRun(
              states,
              first: cut,
              end: states.length,
              top: _above - AppShape.chunkyCardShadow,
              bottom: _below,
            ),
            path: path,
            open: open,
          ),
      ],
    );
  }
}

/// The island's name and progress, in a chunky card over the sea.
class _Header extends StatelessWidget {
  const _Header({required this.path, required this.language});

  final IslandPathView path;
  final String language;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = path.nodes.length;
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(path.title.of(language), style: AppText.title),
          const SizedBox(height: AppSpace.x1),
          Text(
            l10n.island_progress(path.done, total),
            style: AppText.label.copyWith(color: AppColors.muted),
          ),
          // Closed: the lesson it waits for (M12-7).
          if (path.opensAfter case final lesson?) ...[
            const SizedBox(height: AppSpace.x1),
            Text(
              l10n.map_island_opens_after(lesson.of(language)),
              style: AppText.bodyStrong,
            ),
          ],
          const SizedBox(height: AppSpace.x2),
          ExcludeSemantics(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.ink, width: 2),
                borderRadius: BorderRadius.circular(AppSpace.x2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpace.x2),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : path.done / total,
                  minHeight: 12,
                  color: AppColors.progress,
                  backgroundColor: AppColors.line,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A run of islets with each lesson's bubble on its islet and, but for the
/// current lesson's, its title and where it stands beside it, towards the
/// middle.
class _Run extends StatelessWidget {
  const _Run({required this.run, required this.path, required this.open});

  final IsletRun run;
  final IslandPathView path;
  final List<VoidCallback?> open;

  /// From an islet's centre to its caption, clear of both bridges.
  static const _toCaption = IsletGrid.tile + 35;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final captionWidth =
            width / 2 + IsletGrid.step - _toCaption - AppSpace.screenPadding;
        return SizedBox(
          height: run.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: IsletRunPainter(run)),
              ),
              for (var i = run.first; i < run.end; i++)
                ..._lesson(context, i, width, captionWidth),
            ],
          ),
        );
      },
    );
  }

  /// Lesson [i]'s caption, unless it is the current one, and its bubble.
  List<Widget> _lesson(
    BuildContext context,
    int i,
    double width,
    double captionWidth,
  ) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final node = path.nodes[i];
    final c = run.centre(i, width);
    final title = node.node.title.of(language);
    final type = nodeTypeName(l10n, node.node.type);
    final stateName = switch (node.state) {
      NodeState.done => l10n.island_state_done,
      NodeState.current => l10n.island_state_current,
      NodeState.open => l10n.island_state_open,
      NodeState.locked => l10n.island_state_locked,
    };
    final current = node.state == NodeState.current;
    final size = current ? 76.0 : 56.0;
    final lift = current ? IsletGrid.currentLift : IsletGrid.lift;
    return [
      if (!current)
        Positioned(
          left: i.isEven ? c.dx + _toCaption : c.dx - _toCaption - captionWidth,
          top: c.dy - AppSpace.x1,
          width: captionWidth,
          child: FractionalTranslation(
            translation: const Offset(0, -0.5),
            child: _Caption(
              title: title,
              line: l10n.island_node_caption(type, stateName),
              end: i.isOdd,
              onTap: open[i],
            ),
          ),
        ),
      Positioned(
        left: c.dx - size / 2,
        top: c.dy - lift - size / 2,
        child: _Bubble(
          icon: _typeIcon(node.node.type),
          state: node.state,
          size: size,
          label: l10n.island_node_semantics(i + 1, title, type, stateName),
          onTap: open[i],
        ),
      ),
    ];
  }
}

/// A lesson's bubble on its islet: its type's icon, filled by where it
/// stands, a toy block that presses down when it opens.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.icon,
    required this.state,
    required this.size,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final NodeState state;
  final double size;
  final String label;
  final VoidCallback? onTap;

  static const _depth = 5.0;

  @override
  Widget build(BuildContext context) {
    final current = state == NodeState.current;
    final (fill, edge, glyph) = switch (state) {
      NodeState.done => (AppColors.progress, AppColors.ink, AppColors.ink),
      NodeState.current => (
        AppColors.primary,
        AppColors.ink,
        AppColors.surface,
      ),
      NodeState.open => (AppColors.surface, AppColors.ink, AppColors.ink),
      NodeState.locked => (
        MapPalette.stone,
        MapPalette.lockedInk,
        MapPalette.lockedInk,
      ),
    };
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: ChunkyPress(
        depth: _depth,
        onTap: onTap,
        builder: (sink) => Transform.translate(
          offset: Offset(0, sink),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: edge, width: AppShape.chunkyBorder),
              boxShadow: [
                if (current)
                  const BoxShadow(
                    color: MapPalette.currentRing,
                    spreadRadius: AppSpace.x2,
                  ),
                BoxShadow(color: edge, offset: Offset(0, _depth - sink)),
              ],
            ),
            child: Icon(icon, color: glyph, size: current ? 30 : 24),
          ),
        ),
      ),
    );
  }
}

/// A lesson's title and « type · where it stands » beside its islet. Its
/// bubble speaks for it to screen readers.
class _Caption extends StatelessWidget {
  const _Caption({
    required this.title,
    required this.line,
    required this.end,
    required this.onTap,
  });

  final String title;
  final String line;

  /// Set towards the islet on its right: aligned to the end.
  final bool end;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final align = end ? TextAlign.end : TextAlign.start;
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: end
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              title,
              textAlign: align,
              style: AppText.label.copyWith(color: AppColors.ink),
            ),
            Text(
              line,
              textAlign: align,
              style: AppText.caption.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The current lesson under its islet: its type, its title, and the button
/// that starts it.
class _CurrentCard extends StatelessWidget {
  const _CurrentCard({
    required this.type,
    required this.title,
    required this.onStart,
  });

  final String type;
  final String title;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(type, style: AppText.label.copyWith(color: AppColors.primary)),
          const SizedBox(height: AppSpace.x1),
          Text(title, style: AppText.titleSmall),
          const SizedBox(height: AppSpace.x3),
          ChunkyButton(label: l10n.island_start, onPressed: onStart),
        ],
      ),
    );
  }
}

IconData _typeIcon(NodeType type) => switch (type) {
  NodeType.predictReveal => Icons.visibility_outlined,
  NodeType.toy => Icons.tune,
  NodeType.decision => Icons.signpost_outlined,
  NodeType.sort => Icons.signal_cellular_alt,
  NodeType.buildPuzzle => Icons.extension_outlined,
  NodeType.mission => Icons.flag_outlined,
  NodeType.checkpoint => Icons.emoji_events_outlined,
  NodeType.quiz => Icons.quiz_outlined,
};

/// The room the back button takes at the top of the screen.
const _backRoom = AppSpace.x3 + ChunkyIconButton.size + AppSpace.x4;

/// Back to the map, a toy block over the sea.
class _Back extends StatelessWidget {
  const _Back();

  @override
  Widget build(BuildContext context) => ChunkyIconButton(
    icon: Icons.chevron_left,
    label: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: () => Navigator.maybePop(context),
  );
}
