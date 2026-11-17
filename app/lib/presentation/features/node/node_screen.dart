import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/learning/lesson_cards.dart';
import '../../../application/learning/node_player.dart';
import '../../../application/trip/trip_wizard.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/learning/content.dart';
import '../../../domain/learning/node.dart';
import 'card_player.dart';
import 'checkpoint_player.dart';
import 'decision_player.dart';
import 'mission_player.dart';
import 'predict_reveal_player.dart';
import 'puzzle_player.dart';
import 'sort_player.dart';
import 'toy_player.dart';

/// The node player (BRIEF §3: `/node/:nodeId`, §4.3): one lesson on the
/// sea, as the art direction draws it, played by the widget of its type
/// under a chunky ✕ and the island's progress.
class NodeScreen extends ConsumerWidget {
  const NodeScreen({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final node = ref.watch(islandNodeProvider(nodeId));
    return Scaffold(
      // World screens sit on the sea (BRIEF §10.2).
      backgroundColor: AppColors.sea,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screenPadding,
                  AppSpace.x3,
                  AppSpace.screenPadding,
                  0,
                ),
                child: Row(
                  children: [
                    ChunkyIconButton(
                      icon: Icons.close,
                      label: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: () => leaveNode(context),
                    ),
                    const SizedBox(width: AppSpace.x3),
                    Expanded(child: _CardProgress(nodeId: nodeId)),
                  ],
                ),
              ),
              Expanded(
                child: playerState(
                  node,
                  onRetry: () => ref.invalidate(islandNodeProvider(nodeId)),
                  data: (value) => switch (value.type) {
                    // Past its interaction, a lesson shows its cards (M13-13).
                    _ when ref.watch(lessonCardsProvider(nodeId)).at > 0 =>
                      CardPlayer(nodeId: nodeId),
                    NodeType.predictReveal => PredictRevealPlayer(
                      nodeId: nodeId,
                    ),
                    NodeType.toy => ToyPlayer(nodeId: nodeId),
                    NodeType.decision => DecisionPlayer(nodeId: nodeId),
                    NodeType.sort => SortPlayer(nodeId: nodeId),
                    NodeType.buildPuzzle => PuzzlePlayer(nodeId: nodeId),
                    NodeType.checkpoint ||
                    NodeType.quiz => CheckpointPlayer(nodeId: nodeId),
                    NodeType.mission => MissionPlayer(nodeId: nodeId),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// This lesson's cards as pills (M13-13): its interaction then each card,
/// those seen filled, this one in primary. Screen readers hear « Carte n
/// sur N ». A lesson without cards shows none.
class _CardProgress extends ConsumerWidget {
  const _CardProgress({required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(islandNodeProvider(nodeId)).value?.cards;
    if (cards == null || cards.isEmpty) return const SizedBox.shrink();
    final at = ref.watch(lessonCardsProvider(nodeId)).at;
    final total = cards.length + 1;
    return Semantics(
      label: AppLocalizations.of(context).card_progress(at + 1, total),
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.x1),
            Expanded(
              child: Container(
                height: AppSpace.x3,
                decoration: BoxDecoration(
                  color: i == at
                      ? AppColors.primary
                      : i < at
                      ? AppColors.progress
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpace.x2),
                  border: Border.all(color: AppColors.ink, width: 2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A lesson's block on the sea (the art direction's « predict and reveal »):
/// a [label] in primary, a Baloo [headline], then [children]. It opens each
/// lesson (its type and title), gives the verdict once answered, and holds
/// the « Pourquoi ? ».
class LessonCard extends StatelessWidget {
  const LessonCard({
    super.key,
    this.label,
    this.headline,
    this.children = const [],
  });

  final String? label;
  final String? headline;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label case final label?)
            Text(
              label,
              style: AppText.label.copyWith(color: AppColors.primary),
            ),
          if (headline case final headline?) ...[
            if (label != null) const SizedBox(height: AppSpace.x1),
            Text(headline, style: AppText.title),
          ],
          for (final (i, child) in children.indexed) ...[
            if (i > 0 || label != null || headline != null)
              const SizedBox(height: AppSpace.x2),
            child,
          ],
        ],
      ),
    );
  }
}

/// What a lesson type is called, on the path and over each lesson.
String nodeTypeName(AppLocalizations l10n, NodeType type) => switch (type) {
  NodeType.predictReveal => l10n.node_type_predict_reveal,
  NodeType.toy => l10n.node_type_toy,
  NodeType.decision => l10n.node_type_decision,
  NodeType.sort => l10n.node_type_sort,
  NodeType.buildPuzzle => l10n.node_type_build_puzzle,
  NodeType.mission => l10n.node_type_mission,
  NodeType.checkpoint => l10n.node_type_checkpoint,
  NodeType.quiz => l10n.node_type_quiz,
};

/// Back where the lesson was opened from, or the map.
void leaveNode(BuildContext context) =>
    context.canPop() ? context.pop() : context.go('/');

/// A player's loading and error states.
Widget playerState<T>(
  AsyncValue<T> state, {
  required VoidCallback onRetry,
  required Widget Function(T value) data,
}) => switch (state) {
  AsyncData(:final value) => data(value),
  AsyncError(:final error) => Center(
    child: ErrorView(
      failure: error is Failure ? error : const ServerFailure(),
      onRetry: onRetry,
    ),
  ),
  _ => const Padding(
    padding: EdgeInsets.all(AppSpace.screenPadding),
    child: AsyncSkeleton(lines: 5),
  ),
};

/// The end of a played lesson: its bridge into the sandbox when it has one
/// (BRIEF §4.3: « Rejoue-le toi-même » opens the prefilled trip wizard),
/// then « Continuer ». A lesson with cards goes on to its first card
/// (M13-13); its last card ends with this, [onContinue] saving it.
class LessonEnd extends ConsumerWidget {
  const LessonEnd({super.key, required this.node, this.onContinue});

  final NodeContent node;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (onContinue == null && node.cards.isNotEmpty) {
      return ChunkyButton(
        label: AppLocalizations.of(context).node_continue,
        onPressed: ref.read(lessonCardsProvider(node.id).notifier).next,
      );
    }
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (node.bridge case final bridge?) ...[
          ChunkyButton(
            label: l10n.node_bridge,
            kind: ChunkyButtonKind.progress,
            onPressed: () => context.push(bridgeLocation(bridge, node.id)),
          ),
          const SizedBox(height: AppSpace.x3),
        ],
        ChunkyButton(
          label: l10n.node_continue,
          onPressed: onContinue ?? () => leaveNode(context),
        ),
      ],
    );
  }
}
