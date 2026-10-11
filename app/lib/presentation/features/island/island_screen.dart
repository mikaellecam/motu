import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/learning/island_path.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/learning/node.dart';
import '../../../domain/learning/path.dart';

/// An island's path (BRIEF §3, §4.3): its nodes in order with where each
/// stands, progress on top. A node that is not locked opens its player;
/// coming back shows the new progress.
class IslandScreen extends ConsumerWidget {
  const IslandScreen({super.key, required this.islandId});

  final String islandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final state = ref.watch(islandPathProvider(islandId));
    return Scaffold(
      appBar: AppBar(),
      body: switch (state) {
        AsyncValue(:final value?) => ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            Text(value.title.of(language), style: AppText.display),
            const SizedBox(height: AppSpace.x2),
            Text(
              l10n.island_progress(value.done, value.nodes.length),
              style: AppText.bodyStrong,
            ),
            const SizedBox(height: AppSpace.x2),
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: value.nodes.isEmpty
                    ? 0
                    : value.done / value.nodes.length,
                minHeight: 10,
                color: AppColors.progress,
                backgroundColor: AppColors.line,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(height: AppSpace.x6),
            for (final (i, n) in value.nodes.indexed) ...[
              _NodeTile(
                number: i + 1,
                title: n.node.title.of(language),
                type: _typeName(l10n, n.node.type),
                state: n.state,
                onOpen: n.state == NodeState.locked
                    ? null
                    : () => context.push('/node/${n.node.id}'),
              ),
              const SizedBox(height: AppSpace.x4),
            ],
          ],
        ),
        AsyncValue(:final error?) => Center(
          child: ErrorView(
            failure: error is Failure ? error : const ServerFailure(),
            onRetry: () => ref.invalidate(islandPathProvider(islandId)),
          ),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(AppSpace.screenPadding),
          child: AsyncSkeleton(lines: 6),
        ),
      },
    );
  }
}

String _typeName(AppLocalizations l10n, NodeType type) => switch (type) {
  NodeType.predictReveal => l10n.node_type_predict_reveal,
  NodeType.toy => l10n.node_type_toy,
  NodeType.decision => l10n.node_type_decision,
  NodeType.sort => l10n.node_type_sort,
  NodeType.buildPuzzle => l10n.node_type_build_puzzle,
  NodeType.mission => l10n.node_type_mission,
  NodeType.checkpoint => l10n.node_type_checkpoint,
};

/// One node: a badge (✓ done, its number in primary for the current one,
/// a padlock when locked), its title and type.
class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.number,
    required this.title,
    required this.type,
    required this.state,
    required this.onOpen,
  });

  final int number;
  final String title;
  final String type;
  final NodeState state;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locked = state == NodeState.locked;
    final ink = locked ? AppColors.muted : AppColors.ink;
    final (fill, badge) = switch (state) {
      NodeState.done => (
        AppColors.progress,
        const Icon(Icons.check, color: AppColors.ink),
      ),
      NodeState.current => (
        AppColors.primary,
        Text(
          '$number',
          style: AppText.bodyStrong.copyWith(color: AppColors.surface),
        ),
      ),
      NodeState.open => (
        AppColors.surface,
        Text('$number', style: AppText.bodyStrong),
      ),
      NodeState.locked => (
        AppColors.line,
        const Icon(Icons.lock_outline, color: AppColors.muted),
      ),
    };
    final stateName = switch (state) {
      NodeState.done => l10n.island_state_done,
      NodeState.current => l10n.island_state_current,
      NodeState.open => l10n.island_state_open,
      NodeState.locked => l10n.island_state_locked,
    };

    return Semantics(
      button: !locked,
      enabled: !locked,
      label: l10n.island_node_semantics(number, title, type, stateName),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: ChunkyCard(
          padding: const EdgeInsets.all(AppSpace.x3),
          child: Row(
            children: [
              Container(
                width: AppSpace.minTarget,
                height: AppSpace.minTarget,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: ink, width: AppShape.chunkyBorder),
                ),
                child: badge,
              ),
              const SizedBox(width: AppSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.bodyStrong.copyWith(color: ink)),
                    Text(
                      type,
                      style: AppText.caption.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (state == NodeState.current) ...[
                const SizedBox(width: AppSpace.x2),
                Text(
                  l10n.island_your_turn,
                  style: AppText.label.copyWith(color: AppColors.primary),
                ),
              ],
              if (!locked)
                const Icon(Icons.chevron_right, color: AppColors.ink),
            ],
          ),
        ),
      ),
    );
  }
}
