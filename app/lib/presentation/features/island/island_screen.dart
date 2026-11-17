import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/learning/content.dart';
import '../../../application/learning/island_path.dart';
import '../../../application/learning/place.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/learning/path.dart';
import '../map/district.dart';
import '../map/port.dart';
import '../node/node_screen.dart';
import 'island_scene.dart';
import 'sea_chart.dart';

/// An island up close (BRIEF §4.3, M13-4): Actions & ETF's district or Les
/// bases' port fills the screen, a marker on each lesson's building, the
/// selected lesson's card at the bottom. Drag pans it, pinch zooms it. A
/// lesson done while away grows its building on the way back, then the view
/// glides to the next lesson.
class IslandScreen extends ConsumerWidget {
  const IslandScreen({
    super.key,
    required this.islandId,
    this.arriving = false,
  });

  final String islandId;

  /// Just landed from the sea chart (M13-5): the view opens on the pier.
  final bool arriving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(islandPathProvider(islandId));
    return Scaffold(
      // World screens sit on the sea (BRIEF §10.2).
      backgroundColor: AppColors.sea,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: switch (state) {
          AsyncValue(:final value?) => _Island(
            islandId: islandId,
            path: value,
            arriving: arriving,
          ),
          AsyncValue(:final error?) => SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Back(),
                Expanded(
                  child: Center(
                    child: ErrorView(
                      failure: error is Failure ? error : const ServerFailure(),
                      onRetry: () =>
                          ref.invalidate(islandPathProvider(islandId)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _ => const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(AppSpace.screenPadding),
              child: AsyncSkeleton(lines: 6),
            ),
          ),
        },
      ),
    );
  }
}

class _Island extends ConsumerStatefulWidget {
  const _Island({
    required this.islandId,
    required this.path,
    required this.arriving,
  });

  final String islandId;
  final IslandPathView path;
  final bool arriving;

  @override
  ConsumerState<_Island> createState() => _IslandState();
}

class _IslandState extends ConsumerState<_Island>
    with SingleTickerProviderStateMixin {
  final _scene = GlobalKey<IslandSceneState>();

  /// A building growing, its lesson just done (as M9-19's 1,4 s).
  late final _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// The pieces growing now, and those done while this screen was hidden.
  Set<int> _growing = {};
  final _pending = <int>{};

  /// The marker touched; the lesson to do until one is.
  int? _picked;

  bool get _port => widget.islandId == lesBasesIsland;

  /// Each piece's node id, in the island's order.
  List<String> get _ids => _port
      ? [for (final p in portParts) p.nodeId]
      : [for (final b in districtBuildings) b.nodeId];

  /// Each piece's lesson in the path, by node id.
  Map<String, int> get _lessons => {
    for (final (i, n) in widget.path.nodes.indexed) n.node.id: i,
  };

  PathNode? _node(int piece) => switch (_lessons[_ids[piece]]) {
    final i? => widget.path.nodes[i],
    null => null,
  };

  /// The piece of the lesson to do, or none.
  int? get _current {
    for (var k = 0; k < _ids.length; k++) {
      if (_node(k)?.state == NodeState.current) return k;
    }
    return null;
  }

  Set<int> _done(IslandPathView path) => {
    for (final (k, id) in _ids.indexed)
      if (path.nodes.any((n) => n.node.id == id && n.state == NodeState.done))
        k,
  };

  @override
  void didUpdateWidget(_Island old) {
    super.didUpdateWidget(old);
    _pending.addAll(_done(widget.path).difference(_done(old.path)));
    if (_pending.isNotEmpty) {
      _picked = null;
      _maybeGrow();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Back from the lesson: what it built grows now, in sight.
    _maybeGrow();
  }

  void _maybeGrow() {
    if (_pending.isEmpty || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    final now = {..._pending};
    _pending.clear();
    void then() {
      if (!mounted) return;
      setState(() => _growing = {});
      if (_current case final c?) _scene.currentState?.glideTo(c);
    }

    if (MediaQuery.disableAnimationsOf(context) || _port) {
      // The port builds its part at once.
      WidgetsBinding.instance.addPostFrameCallback((_) => then());
      return;
    }
    setState(() => _growing = now);
    _grow.forward(from: 0).whenComplete(then);
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The app opens here next time (M13-6).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(placeProvider.notifier).visit(widget.islandId);
    });
  }

  /// The sea chart; a crossing lands up close on the island boarded, in the
  /// « Archipel » tab.
  void _chart() => showSeaChart(context, here: widget.islandId, onBoard: _sail);

  void _sail(String to) {
    ref.read(placeProvider.notifier).sail(to);
    if (Navigator.of(context).canPop()) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final path = widget.path;
    final done = _done(path);
    final current = _current;
    final port = ref.watch(portViewProvider).value;
    // The sea opens with a first line, from the ferry quay (M13-7).
    final sail = switch (port) {
      final port? =>
        port.lines.isNotEmpty &&
            quayStands(portBuilt(port.completed, skipped: port.skipped)),
      null => false,
    };
    // Unlocked, not done: their ghosts (M13-7).
    final ghosts = {
      for (var k = 0; k < _ids.length; k++)
        if (_node(k)?.state case NodeState.current || NodeState.open) k,
    };
    final markers = [
      for (var k = 0; k < _ids.length; k++)
        // No marker for a locked lesson (M13-7).
        if (_node(k) case final node? when node.state != NodeState.locked)
          Marker(
            switch (node.state) {
              NodeState.done => MarkerKind.done,
              NodeState.current => MarkerKind.current,
              _ => MarkerKind.later,
            },
            l10n.island_node_semantics(
              _lessons[_ids[k]]! + 1,
              node.node.title.of(language),
              pieceName(l10n, _ids[k]),
              _stateName(l10n, node.state),
            ),
          )
        else
          null,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bar(path: path, language: language),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _grow,
                  builder: (context, _) {
                    final t = Curves.easeInOut.transform(_grow.value);
                    final grown = [
                      for (var k = 0; k < _ids.length; k++)
                        _growing.contains(k)
                            ? t
                            : done.contains(k)
                            ? 1.0
                            : 0.0,
                    ];
                    final world = _port
                        ? portWorld(
                            portBuilt({
                              for (final (k, id) in _ids.indexed)
                                if (grown[k] > 0) id,
                            }, skipped: port?.skipped ?? false),
                            lines: port?.lines ?? const {},
                            ghosts: ghosts,
                          )
                        : districtWorld(
                            grown,
                            // Its ferry with its line from the port.
                            ferry:
                                sail && port!.lines.contains(actionsEtfIsland),
                            ghosts: ghosts,
                          );
                    return IslandScene(
                      key: _scene,
                      world: world,
                      markers: markers,
                      focus: current,
                      arriving: widget.arriving,
                      onFerry: sail ? _chart : null,
                      onMarker: (k) => setState(() => _picked = k),
                      // Touching the island or the sea closes the card.
                      onTapAway: () => setState(() => _picked = null),
                    );
                  },
                ),
              ),
              Positioned(
                right: AppSpace.screenPadding,
                top: AppSpace.x3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (sail) ...[
                      ChunkyButton(
                        label: l10n.chart_sail,
                        icon: Icons.sailing,
                        kind: ChunkyButtonKind.secondary,
                        onPressed: _chart,
                      ),
                      const SizedBox(height: AppSpace.x2),
                    ],
                    ChunkyIconButton(
                      icon: Icons.my_location,
                      label: l10n.island_recentre,
                      onPressed: () {
                        setState(() => _picked = null);
                        _scene.currentState?.glideTo(current ?? 0);
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                left: AppSpace.screenPadding,
                right: AppSpace.screenPadding,
                bottom:
                    AppSpace.screenPadding +
                    MediaQuery.paddingOf(context).bottom,
                // Nothing until a marker is touched (M13-9).
                child: switch (_picked) {
                  final piece? => _LessonCard(
                    piece: piece,
                    pieceId: _ids[piece],
                    index: _lessons[_ids[piece]],
                    node: _node(piece),
                    path: path,
                    language: language,
                  ),
                  null => const SizedBox.shrink(),
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _stateName(AppLocalizations l10n, NodeState state) => switch (state) {
  NodeState.done => l10n.island_state_done,
  NodeState.current => l10n.island_state_current,
  NodeState.open => l10n.island_state_open,
  NodeState.locked => l10n.island_state_locked,
};

/// The island's name and progress over the scene, back and settings beside.
class _Bar extends StatelessWidget {
  const _Bar({required this.path, required this.language});

  final IslandPathView path;
  final String language;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = path.nodes.length;
    return ColoredBox(
      color: AppColors.page,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.x1,
            AppSpace.x1,
            AppSpace.x1,
            AppSpace.x2,
          ),
          child: Row(
            children: [
              if (Navigator.of(context).canPop()) const _Back(),
              if (!Navigator.of(context).canPop())
                const SizedBox(width: AppSpace.screenPadding - AppSpace.x1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(path.title.of(language), style: AppText.title),
                    Text(switch (path.opensAfter) {
                      // Closed: the lesson it waits for (M12-7).
                      final lesson? => l10n.map_island_opens_after(
                        lesson.of(language),
                      ),
                      null => l10n.island_progress(path.done, total),
                    }, style: AppText.label.copyWith(color: AppColors.muted)),
                  ],
                ),
              ),
              ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.x3,
                    vertical: AppSpace.x1 / 2,
                  ),
                  decoration: ShapeDecoration(
                    color: AppColors.progress,
                    shape: const StadiumBorder(
                      side: BorderSide(color: AppColors.ink, width: 2),
                    ),
                  ),
                  child: Text(
                    l10n.map_island_progress(path.done, total),
                    style: AppText.bodyStrong,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.map_settings,
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected lesson: its number, its building, its title, where it
/// stands, and the way into it.
class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.piece,
    required this.pieceId,
    required this.index,
    required this.node,
    required this.path,
    required this.language,
  });

  final int piece;
  final String pieceId;
  final int? index;
  final PathNode? node;
  final IslandPathView path;
  final String language;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final node = this.node;
    final index = this.index;
    if (node == null || index == null) return const SizedBox.shrink();
    final state = node.state;
    final open = state != NodeState.locked;
    void play() => context.push('/node/${node.node.id}');
    // A locked lesson names what it waits for: the island's gate, or the
    // lesson before it.
    final waiting = switch (path.opensAfter) {
      final gate? => gate.of(language),
      null when index > 0 => path.nodes[index - 1].node.title.of(language),
      null => '',
    };
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: switch (state) {
                      NodeState.done => AppColors.ink,
                      NodeState.current => AppColors.progress,
                      _ => AppColors.surface,
                    },
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: open ? AppColors.ink : MapPalette.lockedInk,
                      width: AppShape.chunkyBorder,
                    ),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: AppText.bodyStrong.copyWith(
                      color: switch (state) {
                        NodeState.done => AppColors.surface,
                        NodeState.locked => MapPalette.lockedInk,
                        _ => AppColors.ink,
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.island_node_caption(
                        pieceName(l10n, pieceId),
                        _stateName(l10n, state),
                      ),
                      style: AppText.label.copyWith(color: AppColors.muted),
                    ),
                    Text(
                      node.node.title.of(language),
                      style: AppText.titleSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.x1),
          Text(
            nodeTypeName(l10n, node.node.type),
            style: AppText.label.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: AppSpace.x3),
          switch (state) {
            NodeState.done => ChunkyButton(
              label: l10n.island_replay,
              kind: ChunkyButtonKind.secondary,
              onPressed: play,
            ),
            NodeState.locked => ChunkyButton(
              label: l10n.map_island_opens_after(waiting),
              onPressed: null,
            ),
            _ => ChunkyButton(label: l10n.island_start, onPressed: play),
          },
        ],
      ),
    );
  }
}

/// The name of the building or harbour part a lesson grows (M13-4).
String pieceName(AppLocalizations l10n, String nodeId) => switch (nodeId) {
  'ae.livret-vs-etf' => l10n.piece_ae_livret_vs_etf,
  'ae.fees-toy' => l10n.piece_ae_fees_toy,
  'ae.mission-first-etf' => l10n.piece_ae_mission_first_etf,
  'ae.apple-vs-world-2022' => l10n.piece_ae_apple_vs_world_2022,
  'ae.march-2020' => l10n.piece_ae_march_2020,
  'ae.risk-ladder' => l10n.piece_ae_risk_ladder,
  'ae.compound-toy' => l10n.piece_ae_compound_toy,
  'ae.mission-three-regions' => l10n.piece_ae_mission_three_regions,
  'ae.dollar-trap' => l10n.piece_ae_dollar_trap,
  'ae.calm-portfolio' => l10n.piece_ae_calm_portfolio,
  'ae.mission-dca' => l10n.piece_ae_mission_dca,
  'ae.checkpoint-1' => l10n.piece_ae_checkpoint_1,
  'lb.safety-cushion' => l10n.piece_lb_safety_cushion,
  'lb.cash-inflation' => l10n.piece_lb_cash_inflation,
  'lb.livret-inflation' => l10n.piece_lb_livret_inflation,
  'lb.mission-livret' => l10n.piece_lb_mission_livret,
  'lb.cushion-2020' => l10n.piece_lb_cushion_2020,
  'lb.loan-cost' => l10n.piece_lb_loan_cost,
  'lb.save-or-repay' => l10n.piece_lb_save_or_repay,
  'lb.spot-the-scam' => l10n.piece_lb_spot_the_scam,
  'lb.checkpoint-1' => l10n.piece_lb_checkpoint_1,
  _ => '',
};

/// Back, a toy block over the sea.
class _Back extends StatelessWidget {
  const _Back();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpace.x1),
    child: ChunkyIconButton(
      icon: Icons.chevron_left,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () => Navigator.maybePop(context),
    ),
  );
}
