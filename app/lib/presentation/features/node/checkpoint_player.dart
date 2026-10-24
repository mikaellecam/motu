import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/lesson_play.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../widgets/term_text.dart';
import 'node_screen.dart';

/// `checkpoint` (BRIEF §4.3): one question at a time, each answer checked
/// with its explanation, then the score. Done whatever the score.
class CheckpointPlayer extends ConsumerWidget {
  const CheckpointPlayer({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final quiz = ref.watch(checkpointPlayProvider(nodeId));
    final actions = ref.read(checkpointPlayProvider(nodeId).notifier);

    return playerState(
      ref.watch(checkpointViewProvider(nodeId)),
      onRetry: () => ref.invalidate(checkpointViewProvider(nodeId)),
      data: (view) {
        final questions = view.checkpoint.questions;
        final type = nodeTypeName(l10n, view.node.type);
        if (quiz.finished) {
          return ListView(
            padding: const EdgeInsets.all(AppSpace.screenPadding),
            children: [
              Semantics(
                liveRegion: true,
                child: LessonCard(
                  label: type,
                  headline: view.node.title.of(language),
                  children: [
                    Text(
                      l10n.checkpoint_score(quiz.score!, questions.length),
                      style: AppText.display,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      l10n.checkpoint_done,
                      style: text.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.x6),
              LessonEnd(node: view.node),
            ],
          );
        }

        final question = questions[quiz.index];
        String label(String id) =>
            question.choices.firstWhere((c) => c.id == id).label.of(language);
        final right = quiz.chosen == question.answer;
        final last = quiz.index + 1 == questions.length;
        return ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            LessonCard(
              label: l10n.checkpoint_progress(quiz.index + 1, questions.length),
              headline: view.node.title.of(language),
              children: [
                TermText(
                  question.question.of(language),
                  terms: view.terms,
                  style: text.bodyLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.x4),
            for (final choice in question.choices) ...[
              ChunkyChoice(
                label: choice.label.of(language),
                selected: quiz.chosen == choice.id,
                onTap: () => actions.choose(choice.id),
                mark: !quiz.checked
                    ? null
                    : choice.id == question.answer
                    ? (right: true, label: l10n.node_mark_right)
                    : choice.id == quiz.chosen
                    ? (right: false, label: l10n.node_mark_wrong)
                    : null,
              ),
              const SizedBox(height: AppSpace.x3),
            ],
            if (!quiz.checked)
              ChunkyButton(
                label: l10n.node_check,
                onPressed: quiz.chosen == null ? null : actions.check,
              )
            else ...[
              Semantics(
                liveRegion: true,
                child: LessonCard(
                  headline: right ? l10n.node_right : l10n.node_wrong_headline,
                  children: [
                    Text(
                      right
                          ? l10n.node_recap_right(label(quiz.chosen!))
                          : l10n.node_recap_wrong(
                              label(quiz.chosen!),
                              label(question.answer),
                            ),
                      style: text.bodyLarge,
                    ),
                    if (question.explanation case final explanation?)
                      TermText(explanation.of(language), terms: view.terms),
                  ],
                ),
              ),
              if (quiz.failure case final failure?)
                Text(
                  failureMessage(context, failure),
                  style: text.bodyMedium?.copyWith(color: AppColors.alertText),
                ),
              const SizedBox(height: AppSpace.x4),
              ChunkyButton(
                label: last ? l10n.checkpoint_finish : l10n.checkpoint_next,
                onPressed: actions.next,
              ),
            ],
          ],
        );
      },
    );
  }
}
