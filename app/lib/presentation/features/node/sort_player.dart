import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/lesson_play.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../widgets/term_text.dart';
import 'node_screen.dart';

/// `sort` (BRIEF §4.3): drag the items onto the scale, from its low end to
/// its high end; once placed, how many sit at their rank and the real
/// order with each value.
class SortPlayer extends ConsumerWidget {
  const SortPlayer({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final formats = Formats(language);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final actions = ref.read(sortPlayProvider(nodeId).notifier);
    final view = ref.watch(sortViewProvider(nodeId)).value;

    return playerState(
      ref.watch(sortPlayProvider(nodeId)),
      onRetry: () => ref.invalidate(sortPlayProvider(nodeId)),
      data: (state) {
        if (view == null) return const SizedBox.shrink();
        final sort = view.sort;
        final labels = {for (final i in sort.items) i.id: i.label.of(language)};
        final title = Text(view.node.title.of(language), style: AppText.title);

        if (state.submitted) {
          return ListView(
            padding: const EdgeInsets.all(AppSpace.screenPadding),
            children: [
              title,
              const SizedBox(height: AppSpace.x4),
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.sort_result(state.placed!, state.order.length),
                  style: AppText.titleSmall,
                ),
              ),
              const SizedBox(height: AppSpace.x4),
              Text(l10n.sort_truth, style: muted),
              const SizedBox(height: AppSpace.x2),
              ChunkyCard(
                child: Column(
                  children: [
                    for (final (i, id) in view.truth.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpace.x1,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: AppSpace.x6,
                              child: Text(
                                '${i + 1}',
                                style: AppText.bodyStrong,
                              ),
                            ),
                            Expanded(
                              child: Text(labels[id]!, style: text.bodyLarge),
                            ),
                            Text(
                              formats.percent(view.values[id]!),
                              style: AppText.figure.copyWith(
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.x4),
              TermText(sort.explanation.of(language), terms: view.terms),
              const SizedBox(height: AppSpace.x6),
              LessonEnd(node: view.node),
            ],
          );
        }

        return ReorderableListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          buildDefaultDragHandles: false,
          onReorderItem: actions.move,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: AppSpace.x2),
              TermText(sort.prompt.of(language), terms: view.terms),
              Text(l10n.sort_hint, style: muted),
              const SizedBox(height: AppSpace.x4),
              Text(sort.low.of(language), style: AppText.label),
              const SizedBox(height: AppSpace.x2),
            ],
          ),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(sort.high.of(language), style: AppText.label),
              const SizedBox(height: AppSpace.x6),
              if (state.failure case final failure?)
                Text(
                  failureMessage(context, failure),
                  style: text.bodyMedium?.copyWith(color: AppColors.alertText),
                ),
              ChunkyButton(label: l10n.node_check, onPressed: actions.submit),
            ],
          ),
          children: [
            for (final (i, id) in state.order.indexed)
              Padding(
                key: ValueKey(id),
                padding: const EdgeInsets.only(bottom: AppSpace.x3),
                child: ChunkyCard(
                  padding: const EdgeInsets.only(left: AppSpace.x4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: AppSpace.x6,
                        child: Text('${i + 1}', style: AppText.bodyStrong),
                      ),
                      Expanded(
                        child: Text(labels[id]!, style: AppText.bodyStrong),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: SizedBox(
                          width: AppSpace.minTarget + AppSpace.x2,
                          height: AppSpace.minTarget + AppSpace.x2,
                          child: Icon(
                            Icons.drag_handle,
                            color: AppColors.ink,
                            semanticLabel: l10n.sort_move,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
