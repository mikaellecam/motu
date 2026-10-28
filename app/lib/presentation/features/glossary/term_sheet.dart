import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
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
import '../../../domain/analytics/drawdown.dart';
import '../../../domain/analytics/volatility.dart';
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

/// A term's sheet (artboard GlossarySheet-A): title, « Nouvelle notion »
/// on its first open and ✕, the one-line definition (the longer one behind
/// « En savoir plus », so the example and the test stay near), its live
/// example on real data, « Ce que ça change pour toi », related terms and
/// « Tester en 30 secondes ».
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
  var _more = false;

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
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpace.x2,
                  runSpacing: AppSpace.x1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(value.term.title.of(language), style: AppText.title),
                    if (value.firstOpen) NotionBadge(l10n.glossary_new_notion),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.x2),
              ChunkyIconButton(
                icon: Icons.close,
                label: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.x3),
          Text(value.term.short.of(language), style: AppText.body),
          if (_more) ...[
            const SizedBox(height: AppSpace.x2),
            TermText(
              value.term.body.of(language),
              terms: value.terms,
              onTerm: _open,
            ),
          ] else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.x1),
                ),
                onPressed: () => setState(() => _more = true),
                child: Text(l10n.glossary_more),
              ),
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
                  ChunkyChip(
                    label: t.title.of(language),
                    onTap: () => _open(t.id),
                  ),
              ],
            ),
          ],
          if (value.quiz.isNotEmpty) ...[
            const SizedBox(height: AppSpace.x6),
            if (_quiz)
              _TermQuizPanel(termId: widget.termId, quiz: value.quiz)
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

    return ChunkyCard(
      child: switch (ref.watch(liveExampleProvider(kind, assetId))) {
        AsyncValue(:final value?) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.glossary_example_title,
              style: AppText.label.copyWith(color: AppColors.primary),
            ),
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
                  l10n.glossary_example_volatility(value.asset.name, figure(v)),
                (LiveExample.drawdown, final v?) =>
                  l10n.glossary_example_drawdown(value.asset.name, figure(v)),
                (LiveExample.currency, final v?) =>
                  l10n.glossary_example_currency(
                    value.asset.currency.code,
                    figure(v),
                  ),
              },
              style: AppText.titleSmall.copyWith(
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
              switch (kind) {
                // How far each day moved, the asset beside the world ETF on
                // one scale (M9-28): the jittery one shows at a glance.
                LiveExample.volatility => _DailyMoves([
                  (value.asset.name, dailyChanges(value.closes), lineColors[0]),
                  // Named as the line above names it.
                  if (value.world != null)
                    (
                      l10n.wallet_benchmark_world,
                      dailyChanges(value.worldCloses),
                      lineColors[1],
                    ),
                ]),
                _ => Semantics(
                  label: l10n.node_chart_semantics(
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
                  excludeSemantics: true,
                  child: _PriceLine(value.closes, value.drawdown),
                ),
              },
            ],
          ],
        ),
        AsyncValue(hasError: true) => Text(
          l10n.glossary_example_unavailable,
          style: muted,
        ),
        _ => const AsyncSkeleton(lines: 2),
      },
    );
  }
}

/// An example's year of closes, small; the worst drop's peak and trough
/// marked when there is one (M9-28), as the asset page marks them.
class _PriceLine extends StatelessWidget {
  const _PriceLine(this.closes, this.drawdown);
  final List<(DateTime, Decimal)> closes;
  final Drawdown? drawdown;

  @override
  Widget build(BuildContext context) {
    final marks = {
      for (final date in [drawdown?.peakDate, drawdown?.troughDate])
        if (date != null) closes.indexWhere((c) => c.$1 == date),
    }..remove(-1);
    return SizedBox(
      height: 96,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              // Doubles from here on: pixels, not money.
              spots: [
                for (final (i, (_, close)) in closes.indexed)
                  FlSpot(i.toDouble(), close.toDouble()),
              ],
              color: AppColors.primary,
              barWidth: 2,
              dotData: FlDotData(
                checkToShowDot: (spot, _) => marks.contains(spot.x.toInt()),
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: AppColors.alert,
                  strokeWidth: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The volatility example (M9-28): each day's change as a thin bar from a
/// middle line, one row per asset, all on the widest move's scale. The
/// figures above say it in words: hidden from screen readers.
class _DailyMoves extends StatelessWidget {
  const _DailyMoves(this.rows);
  final List<(String, List<(DateTime, Decimal)>, Color)> rows;

  @override
  Widget build(BuildContext context) {
    // Doubles from here on: pixels, not money. One scale for both rows: an
    // ordinary day's move (the 95th percentile), the rare bigger ones
    // reaching the row's edge, so one crash day does not flatten the rest.
    final sizes = [
      for (final (_, changes, _) in rows)
        for (final (_, change) in changes) change.abs().toDouble(),
    ]..sort();
    final widest = sizes.isEmpty
        ? 0.0
        : sizes[((sizes.length - 1) * 0.95).round()];
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (name, changes, color)) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpace.x2),
            Text(name, style: AppText.caption.copyWith(color: AppColors.muted)),
            SizedBox(
              height: 40,
              child: CustomPaint(
                painter: _MovesPainter(
                  [for (final (_, change) in changes) change.toDouble()],
                  widest,
                  color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MovesPainter extends CustomPainter {
  _MovesPainter(this.moves, this.widest, this.color);
  final List<double> moves;
  final double widest;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    canvas.drawLine(
      Offset(0, middle),
      Offset(size.width, middle),
      Paint()
        ..color = AppColors.line
        ..strokeWidth = 1,
    );
    if (moves.isEmpty || widest == 0) return;
    final step = size.width / moves.length;
    final bar = Paint()
      ..color = color
      ..strokeWidth = math.max(1, step * 0.6);
    for (final (i, move) in moves.indexed) {
      final x = (i + 0.5) * step;
      final reach = (move / widest).clamp(-1.0, 1.0);
      canvas.drawLine(
        Offset(x, middle),
        Offset(x, middle - reach * middle),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(_MovesPainter old) =>
      old.widest != widest || old.color != color || old.moves != moves;
}

/// « Nouvelle » or « Nouvelle notion »: a small pill in the new notions'
/// yellow, an ink edge so it reads as a label, not a button.
class NotionBadge extends StatelessWidget {
  const NotionBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.progress,
      borderRadius: BorderRadius.circular(AppSpace.x4),
      border: Border.all(color: AppColors.ink, width: 2),
    ),
    child: Text(label, style: AppText.label),
  );
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
