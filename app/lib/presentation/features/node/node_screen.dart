import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/learning/node_player.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../domain/learning/node.dart';
import 'checkpoint_player.dart';
import 'decision_player.dart';
import 'predict_reveal_player.dart';
import 'puzzle_player.dart';
import 'sort_player.dart';
import 'toy_player.dart';

/// The node player (BRIEF §3: `/node/:nodeId`): one lesson, played by the
/// widget of its type (§4.3).
class NodeScreen extends ConsumerWidget {
  const NodeScreen({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final node = ref.watch(islandNodeProvider(nodeId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close),
          onPressed: () => leaveNode(context),
        ),
      ),
      body: playerState(
        node,
        onRetry: () => ref.invalidate(islandNodeProvider(nodeId)),
        data: (value) => switch (value.type) {
          NodeType.predictReveal => PredictRevealPlayer(nodeId: nodeId),
          NodeType.toy => ToyPlayer(nodeId: nodeId),
          NodeType.decision => DecisionPlayer(nodeId: nodeId),
          NodeType.sort => SortPlayer(nodeId: nodeId),
          NodeType.buildPuzzle => PuzzlePlayer(nodeId: nodeId),
          NodeType.checkpoint => CheckpointPlayer(nodeId: nodeId),
          // Missions play in the sandbox (M6-5).
          NodeType.mission => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.screenPadding),
              child: Text(l10n.node_not_playable, textAlign: TextAlign.center),
            ),
          ),
        },
      ),
    );
  }
}

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
