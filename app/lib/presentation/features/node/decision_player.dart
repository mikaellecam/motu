import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/lesson_play.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../widgets/sign_color.dart';
import '../../widgets/term_text.dart';
import 'node_screen.dart';
import 'reveal_chart.dart';

/// `decision` (BRIEF §4.3): the moment and the curve up to it, three
/// choices each with an upside and a downside; once chosen, the rest of the
/// curve draws itself and each choice shows what the money became.
class DecisionPlayer extends ConsumerWidget {
  const DecisionPlayer({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final formats = Formats(language);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final play = ref.watch(decisionPlayProvider(nodeId));
    final actions = ref.read(decisionPlayProvider(nodeId).notifier);

    return playerState(
      ref.watch(decisionViewProvider(nodeId)),
      onRetry: () => ref.invalidate(decisionViewProvider(nodeId)),
      data: (view) {
        final decision = view.decision;
        final shown = play.submitted
            ? [...view.before, ...view.after.skip(1)]
            : view.before;
        return ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            LessonCard(
              label: nodeTypeName(l10n, view.node.type),
              headline: view.node.title.of(language),
              children: [
                TermText(
                  decision.context.of(language),
                  terms: view.terms,
                  style: text.bodyLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.x4),
            ChunkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RevealChart(
                    // A new chart on reveal: the whole curve draws itself.
                    key: ValueKey(play.submitted),
                    animate: play.submitted,
                    lines: [
                      ChartLine([
                        for (final (date, value) in shown)
                          (
                            date.millisecondsSinceEpoch.toDouble(),
                            value.toDouble(),
                          ),
                      ], lineColors.first),
                    ],
                    semanticsLabel: l10n.node_chart_semantics(
                      l10n.node_chart_line(
                        decision.seriesLabel.of(language),
                        formatValue(formats, shown.first.$2, view.currency),
                        formatValue(formats, shown.last.$2, view.currency),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.x2),
                  Text(decision.seriesLabel.of(language), style: muted),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.x4),
            if (!play.submitted) ...[
              Text(l10n.decision_question, style: AppText.titleSmall),
              const SizedBox(height: AppSpace.x2),
              for (final choice in decision.choices) ...[
                ChunkyChoice(
                  label: choice.label.of(language),
                  upside: choice.upside.of(language),
                  downside: choice.downside.of(language),
                  selected: play.chosen == choice.id,
                  onTap: () => actions.choose(choice.id),
                ),
                const SizedBox(height: AppSpace.x3),
              ],
              if (play.failure case final failure?)
                Text(
                  failureMessage(context, failure),
                  style: text.bodyMedium?.copyWith(color: AppColors.alertText),
                ),
              ChunkyButton(
                label: l10n.node_check,
                onPressed: play.chosen == null ? null : actions.submit,
              ),
            ] else ...[
              // What each choice became takes the choices' place, yours
              // named.
              LessonCard(
                label: l10n.decision_after,
                children: [
                  Text(
                    l10n.decision_outcomes(
                      formatValue(formats, decision.invested, view.currency),
                      formats.date(view.after.first.$1),
                      formats.date(view.after.last.$1),
                    ),
                    style: muted,
                  ),
                  for (final choice in decision.choices)
                    ChartLegendRow(
                      label: choice.id == play.chosen
                          ? '${choice.label.of(language)} (${l10n.decision_your_choice})'
                          : choice.label.of(language),
                      value: formatValue(
                        formats,
                        view.outcomes[choice.id]!,
                        view.currency,
                      ),
                      count: (
                        from: decision.invested,
                        to: view.outcomes[choice.id]!,
                        format: (v) => formatValue(formats, v, view.currency),
                        percent: (r) => formats.percent(r, signed: true),
                      ),
                      change: formats.percent(
                        choice.kept * view.change,
                        signed: true,
                      ),
                      changeColor: signColor(
                        choice.kept * view.change,
                        ratio: true,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.x4),
              LessonCard(
                label: l10n.node_why,
                children: [
                  TermText(
                    decision.explanation.of(language),
                    terms: view.terms,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.x6),
              LessonEnd(node: view.node),
            ],
          ],
        );
      },
    );
  }
}
