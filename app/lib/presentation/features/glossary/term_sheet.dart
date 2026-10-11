import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/glossary.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../core/failure.dart';
import '../../../domain/learning/checkpoint.dart';
import '../../../domain/learning/glossary.dart';
import '../../widgets/sign_color.dart';
import '../../widgets/term_text.dart';
import '../node/reveal_chart.dart';

/// Opens the sheet of [termId] (BRIEF §4.4), from a `{{term}}` link, an
/// essentials tile ([assetId]: its live example is about that asset), a
/// chip or the index.
Future<void> showTermSheet(
  BuildContext context,
  String termId, {
  String? assetId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.85,
    minChildSize: 0.4,
    maxChildSize: 0.95,
    builder: (context, controller) =>
        TermSheet(termId: termId, assetId: assetId, controller: controller),
  ),
);

/// A term's sheet: title, « Nouvelle notion » on its first open, the
/// definition, its live example on real data, « Ce que ça change pour
/// toi », related terms and « Tester en 30 secondes ».
class TermSheet extends ConsumerStatefulWidget {
  const TermSheet({
    super.key,
    required this.termId,
    this.assetId,
    this.controller,
  });

  final String termId;
  final String? assetId;
  final ScrollController? controller;

  @override
  ConsumerState<TermSheet> createState() => _TermSheetState();
}

class _TermSheetState extends ConsumerState<TermSheet> {
  var _quiz = false;

  /// Another term replaces this one: one sheet at a time.
  void _open(String termId) {
    final navigator = Navigator.of(context);
    navigator.pop();
    showTermSheet(navigator.context, termId, assetId: widget.assetId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final state = ref.watch(termSheetProvider(widget.termId));
    final passed =
        ref.watch(glossaryProgressProvider).value?[widget.termId]?.quizPassed ??
        false;

    return switch (state) {
      AsyncValue(:final value?) => ListView(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenPadding,
          0,
          AppSpace.screenPadding,
          AppSpace.x8,
        ),
        children: [
          Wrap(
            spacing: AppSpace.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(value.term.title.of(language), style: AppText.title),
              if (value.firstOpen)
                Chip(
                  label: Text(l10n.glossary_new_notion),
                  backgroundColor: AppColors.progress,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: AppSpace.x2),
          Text(value.term.short.of(language), style: AppText.bodyStrong),
          const SizedBox(height: AppSpace.x2),
          TermText(
            value.term.body.of(language),
            terms: value.terms,
            onTerm: _open,
          ),
          if (value.term.liveExample case final kind?) ...[
            const SizedBox(height: AppSpace.x4),
            _LiveExampleCard(kind: kind, assetId: widget.assetId),
          ],
          if (value.term.forYou case final forYou?) ...[
            const SizedBox(height: AppSpace.x4),
            Text(l10n.glossary_for_you, style: AppText.titleSmall),
            const SizedBox(height: AppSpace.x1),
            TermText(forYou.of(language), terms: value.terms, onTerm: _open),
          ],
          if (value.related.isNotEmpty) ...[
            const SizedBox(height: AppSpace.x4),
            Text(l10n.glossary_related, style: AppText.titleSmall),
            const SizedBox(height: AppSpace.x2),
            Wrap(
              spacing: AppSpace.x2,
              runSpacing: AppSpace.x2,
              children: [
                for (final t in value.related)
                  ActionChip(
                    label: Text(t.title.of(language)),
                    onPressed: () => _open(t.id),
                  ),
              ],
            ),
          ],
          if (value.term.quiz.isNotEmpty) ...[
            const SizedBox(height: AppSpace.x6),
            if (_quiz)
              _TermQuizPanel(termId: widget.termId, quiz: value.term.quiz)
            else ...[
              ChunkyButton(
                label: l10n.glossary_quiz_start,
                kind: ChunkyButtonKind.progress,
                onPressed: () => setState(() => _quiz = true),
              ),
              if (passed) ...[
                const SizedBox(height: AppSpace.x2),
                Text(
                  l10n.glossary_quiz_done,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ],
          ],
        ],
      ),
      AsyncValue(:final error?) => ErrorView(
        failure: error is Failure ? error : const ServerFailure(),
        onRetry: () => ref.invalidate(termSheetProvider(widget.termId)),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(AppSpace.screenPadding),
        child: AsyncSkeleton(lines: 4),
      ),
    };
  }
}

/// The term's figure over the last year for the asset, beside the world
/// ETF's, and the asset's year as a small line.
class _LiveExampleCard extends ConsumerWidget {
  const _LiveExampleCard({required this.kind, required this.assetId});
  final LiveExample kind;
  final String? assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    String figure(Decimal v) => switch (kind) {
      LiveExample.volatility => formats.percent(v),
      _ => formats.percent(v, signed: true),
    };
    Color? colorOf(Decimal v) =>
        kind == LiveExample.volatility ? null : signColor(v, ratio: true);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x4),
        child: switch (ref.watch(liveExampleProvider(kind, assetId))) {
          AsyncValue(:final value?) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.glossary_example_title, style: muted),
              const SizedBox(height: AppSpace.x1),
              Text(
                switch ((kind, value.figure)) {
                  (LiveExample.currency, _)
                      when value.asset.currency == Currency.eur =>
                    l10n.glossary_example_in_euros(value.asset.name),
                  (_, null) => l10n.glossary_example_too_short,
                  (LiveExample.performance, final v?) =>
                    l10n.glossary_example_performance(
                      value.asset.name,
                      figure(v),
                    ),
                  (LiveExample.volatility, final v?) =>
                    l10n.glossary_example_volatility(
                      value.asset.name,
                      figure(v),
                    ),
                  (LiveExample.drawdown, final v?) =>
                    l10n.glossary_example_drawdown(value.asset.name, figure(v)),
                  (LiveExample.currency, final v?) =>
                    l10n.glossary_example_currency(
                      value.asset.currency.code,
                      figure(v),
                    ),
                },
                style: AppText.bodyStrong.copyWith(
                  color: value.figure == null ? null : colorOf(value.figure!),
                ),
              ),
              if (value.worldFigure case final w?)
                Text(
                  l10n.glossary_example_world(figure(w)),
                  style: text.bodyMedium,
                ),
              if (value.closes.length > 1) ...[
                const SizedBox(height: AppSpace.x3),
                RevealChart(
                  height: 96,
                  animate: false,
                  lines: [
                    ChartLine([
                      for (final (d, c) in value.closes)
                        (d.millisecondsSinceEpoch.toDouble(), c.toDouble()),
                    ], AppColors.primary),
                  ],
                  semanticsLabel: l10n.node_chart_semantics(
                    l10n.node_chart_line(
                      value.asset.name,
                      formats.price(
                        Price(value.closes.first.$2, value.asset.currency),
                      ),
                      formats.price(
                        Price(value.closes.last.$2, value.asset.currency),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          AsyncValue(hasError: true) => Text(
            l10n.glossary_example_unavailable,
            style: muted,
          ),
          _ => const AsyncSkeleton(lines: 2),
        },
      ),
    );
  }
}

/// « Tester en 30 secondes »: the term's questions one at a time, then the
/// result; all right, the term is mastered.
class _TermQuizPanel extends ConsumerWidget {
  const _TermQuizPanel({required this.termId, required this.quiz});
  final String termId;
  final List<QuizQuestion> quiz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final state = ref.watch(termQuizProvider(termId));
    final actions = ref.read(termQuizProvider(termId).notifier);
    final total = quiz.length;

    if (state.finished) {
      final passed = state.score == total;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              passed
                  ? l10n.glossary_quiz_passed
                  : l10n.glossary_quiz_failed(state.score!, total),
              style: AppText.titleSmall,
            ),
          ),
          if (!passed) ...[
            const SizedBox(height: AppSpace.x3),
            ChunkyButton(
              label: l10n.glossary_quiz_retry,
              onPressed: actions.retry,
            ),
          ],
        ],
      );
    }

    final question = quiz[state.index];
    final answer = question.choices.firstWhere((c) => c.id == question.answer);
    final last = state.index + 1 == total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.checkpoint_progress(state.index + 1, total),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpace.x1),
        Text(question.question.of(language), style: AppText.bodyStrong),
        const SizedBox(height: AppSpace.x3),
        for (final choice in question.choices) ...[
          ChunkyChoice(
            label: choice.label.of(language),
            selected: state.chosen == choice.id,
            onTap: () => actions.choose(choice.id),
          ),
          const SizedBox(height: AppSpace.x2),
        ],
        if (!state.checked)
          ChunkyButton(
            label: l10n.node_check,
            onPressed: state.chosen == null ? null : actions.check,
          )
        else ...[
          Text(
            state.chosen == question.answer
                ? l10n.node_right
                : l10n.node_wrong(answer.label.of(language)),
            style: AppText.bodyStrong,
          ),
          const SizedBox(height: AppSpace.x3),
          ChunkyButton(
            label: last ? l10n.checkpoint_finish : l10n.checkpoint_next,
            onPressed: actions.next,
          ),
        ],
      ],
    );
  }
}
