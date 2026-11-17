import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/lesson_cards.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/learning/cards.dart';
import '../../widgets/term_text.dart';
import 'node_screen.dart';
import 'reveal_chart.dart';

/// A lesson's card after its interaction (M13-13): a worked example, a
/// comparison on one chart, or a quick check; then « Continuer », and after
/// the last one the lesson is saved as done.
class CardPlayer extends ConsumerWidget {
  const CardPlayer({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final formats = Formats(language);
    final text = Theme.of(context).textTheme;
    final flow = ref.watch(lessonCardsProvider(nodeId));
    final actions = ref.read(lessonCardsProvider(nodeId).notifier);

    return playerState(
      ref.watch(cardsViewProvider(nodeId)),
      onRetry: () => ref.invalidate(cardsViewProvider(nodeId)),
      data: (view) {
        final at = flow.at;
        final card = view.node.cards[at - 1];
        final last = at == view.node.cards.length;
        Future<void> next() async {
          await actions.next();
          if (context.mounted && ref.read(lessonCardsProvider(nodeId)).done) {
            leaveNode(context);
          }
        }

        final end = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (flow.failure case final failure?) ...[
              Text(
                failureMessage(context, failure),
                style: text.bodyMedium?.copyWith(color: AppColors.alertText),
              ),
              const SizedBox(height: AppSpace.x3),
            ],
            if (last)
              LessonEnd(node: view.node, onContinue: next)
            else
              ChunkyButton(label: l10n.node_continue, onPressed: next),
          ],
        );

        return ListView(
          // A card of its own: the list starts at its top.
          key: ValueKey(at),
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: switch (card) {
            StoryCard() => [
              LessonCard(
                label: card.compare ? l10n.card_compare : l10n.card_example,
                headline: card.headline.of(language),
                children: [
                  TermText(
                    card.text.of(language),
                    terms: view.terms,
                    style: text.bodyLarge,
                  ),
                ],
              ),
              if (view.lines[at - 1] case final lines
                  when lines.isNotEmpty) ...[
                const SizedBox(height: AppSpace.x4),
                ChunkyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RevealChart(
                        lines: [
                          for (final (i, line) in lines.indexed)
                            ChartLine([
                              for (final (x, v) in line.values.indexed)
                                (x.toDouble(), v.toDouble()),
                            ], lineColors[i]),
                        ],
                        semanticsLabel: l10n.node_chart_semantics(
                          [
                            for (final line in lines)
                              if (line.values.isNotEmpty)
                                l10n.node_chart_line(
                                  line.label.of(language),
                                  formats.amount(
                                    line.values.first,
                                    line.currency,
                                  ),
                                  formats.amount(
                                    line.values.last,
                                    line.currency,
                                  ),
                                ),
                          ].join('; '),
                        ),
                      ),
                      const SizedBox(height: AppSpace.x3),
                      for (final (i, line) in lines.indexed)
                        if (line.values.isNotEmpty)
                          ChartLegendRow(
                            color: lineColors[i],
                            label: line.label.of(language),
                            value: formats.amount(
                              line.values.last,
                              line.currency,
                            ),
                          ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.x6),
              end,
            ],
            CheckCard(:final question) => () {
              final picked = flow.picked[at];
              final checked = flow.checks[at];
              final right = checked == question.answer;
              String label(String id) => question.choices
                  .firstWhere((c) => c.id == id)
                  .label
                  .of(language);
              return [
                LessonCard(
                  label: l10n.card_check,
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
                    selected: (checked ?? picked) == choice.id,
                    onTap: () => actions.pick(at, choice.id),
                    mark: checked == null
                        ? null
                        : choice.id == question.answer
                        ? (right: true, label: l10n.node_mark_right)
                        : choice.id == checked
                        ? (right: false, label: l10n.node_mark_wrong)
                        : null,
                  ),
                  const SizedBox(height: AppSpace.x3),
                ],
                if (checked == null)
                  ChunkyButton(
                    label: l10n.node_check,
                    onPressed: picked == null ? null : () => actions.check(at),
                  )
                else ...[
                  Semantics(
                    liveRegion: true,
                    child: LessonCard(
                      headline: right
                          ? l10n.node_right
                          : l10n.node_wrong_headline,
                      children: [
                        Text(
                          right
                              ? l10n.node_recap_right(label(checked))
                              : l10n.node_recap_wrong(
                                  label(checked),
                                  label(question.answer),
                                ),
                          style: text.bodyLarge,
                        ),
                        if (question.explanation case final explanation?)
                          TermText(explanation.of(language), terms: view.terms),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.x6),
                  end,
                ],
              ];
            }(),
          },
        );
      },
    );
  }
}
