import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/node_player.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/learning/toys.dart';
import '../../widgets/term_text.dart';
import 'node_screen.dart';
import 'reveal_chart.dart';

/// `toy` (BRIEF §4.3): sliders on a formula chart. The yearly return starts
/// from a real past average (decided 2026-10-11) and says when it became an
/// assumption. The cushion and the loan draw a dashed level to reach (M12-3).
/// Done once every slider moved.
class ToyPlayer extends ConsumerWidget {
  const ToyPlayer({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final formats = Formats(language);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final actions = ref.read(toyPlayProvider(nodeId).notifier);

    return playerState(
      ref.watch(toyPlayProvider(nodeId)),
      onRetry: () => ref.invalidate(toyPlayProvider(nodeId)),
      data: (s) {
        final toy = s.view.toy;
        String euros(Decimal v) => formats.amount(v, Currency.eur);
        String years() => l10n.toy_years(s.value('years').toBigInt().toInt());
        // A level to reach, as long as the curve beside it.
        List<Decimal> level(Decimal v, List<Decimal> beside) =>
            List.filled(beside.length, v);
        // Each line: its name, its values (a year or a month each), its
        // color, dashed for a level; then figures without a line, the
        // result, and a line under it.
        final (lines, figures, result, note) = switch (s.outcome) {
          FeesOutcome(:final result) => (
            [
              (
                l10n.toy_fee_line(formats.percent(s.value('fee_low'))),
                result.low,
                lineColors[0],
                false,
              ),
              (
                l10n.toy_fee_line(formats.percent(s.value('fee_high'))),
                result.high,
                lineColors[1],
                false,
              ),
            ],
            const <(String, String)>[],
            l10n.toy_fees_result(years(), euros(result.gap)),
            _returnLine(l10n, s, language, formats),
          ),
          CompoundOutcome(:final result) => (
            [
              (l10n.toy_value, result.value, lineColors[0], false),
              (l10n.toy_money_in, result.moneyIn, lineColors[2], false),
            ],
            const <(String, String)>[],
            l10n.toy_compound_result(
              years(),
              euros(result.value.last),
              euros(result.moneyIn.last),
            ),
            _returnLine(l10n, s, language, formats),
          ),
          CushionOutcome(:final result) => (
            [
              (l10n.toy_cushion_saved, result.saved, lineColors[0], false),
              (
                l10n.toy_cushion_target,
                level(result.target, result.saved),
                lineColors[1],
                true,
              ),
            ],
            const <(String, String)>[],
            switch (result.fullIn) {
              null => l10n.toy_cushion_never,
              final months => l10n.toy_cushion_result(
                euros(result.target),
                l10n.toy_months(months),
              ),
            },
            null,
          ),
          LoanOutcome(:final result) => (
            [
              (l10n.toy_loan_repaid, result.repaid, lineColors[0], false),
              (
                l10n.toy_loan_borrowed,
                level(result.amount, result.repaid),
                lineColors[1],
                true,
              ),
            ],
            [(l10n.toy_loan_payment, euros(result.payment))],
            l10n.toy_loan_result(euros(result.cost)),
            result.cost == Decimal.zero
                ? l10n.toy_loan_no_cost
                : l10n.toy_loan_paid_back(
                    result.paidBackIn,
                    euros(result.amount),
                  ),
          ),
        };

        return ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            LessonCard(
              label: nodeTypeName(l10n, s.view.node.type),
              headline: s.view.node.title.of(language),
              children: [
                TermText(
                  toy.intro.of(language),
                  terms: s.view.terms,
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
                    lines: [
                      for (final (_, values, color, dashed) in lines)
                        ChartLine(
                          [
                            for (final (i, v) in values.indexed)
                              (i.toDouble(), v.toDouble()),
                          ],
                          color,
                          dashed: dashed,
                        ),
                    ],
                    animate: false,
                    semanticsLabel: l10n.node_chart_semantics(
                      [
                        for (final (label, values, _, _) in lines)
                          l10n.node_chart_line(
                            label,
                            euros(values.first),
                            euros(values.last),
                          ),
                      ].join('; '),
                    ),
                  ),
                  const SizedBox(height: AppSpace.x3),
                  for (final (label, values, color, dashed) in lines)
                    ChartLegendRow(
                      color: color,
                      dashed: dashed,
                      label: label,
                      value: euros(values.last),
                    ),
                  for (final (label, value) in figures)
                    ChartLegendRow(label: label, value: value),
                  const SizedBox(height: AppSpace.x2),
                  Semantics(
                    liveRegion: true,
                    child: Text(result, style: AppText.bodyStrong),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: AppSpace.x2),
                    Text(note, style: muted),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.x4),
            ChunkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in toy.controls)
                    _ToySlider(
                      control: c,
                      label: c.label.of(language),
                      value: s.value(c.id),
                      shown: _format(l10n, formats, c.id, s.value(c.id)),
                      onStep: (index) => actions.setStep(c.id, index),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.x4),
            LessonCard(
              label: l10n.node_why,
              children: [
                TermText(toy.explanation.of(language), terms: s.view.terms),
              ],
            ),
            const SizedBox(height: AppSpace.x6),
            if (s.completed)
              LessonEnd(node: s.view.node)
            else
              Text(
                l10n.toy_touch_all,
                style: muted,
                textAlign: TextAlign.center,
              ),
            if (s.failure case final failure?)
              Text(
                failureMessage(context, failure),
                style: text.bodyMedium?.copyWith(color: AppColors.alertText),
              ),
          ],
        );
      },
    );
  }

  /// Where the yearly return comes from: a real past average, or an
  /// assumption once moved.
  static String _returnLine(
    AppLocalizations l10n,
    ToyState s,
    String language,
    Formats formats,
  ) {
    final rate = formats.percent(s.value('return'), signed: true);
    final past = s.view.past;
    final from = s.view.toy.returnFrom;
    return s.returnIsPast && past != null && from != null
        ? l10n.toy_return_past(
            rate,
            from.label.of(language),
            '${past.from.year}',
            '${past.to.year}',
          )
        : l10n.toy_return_hypothesis(rate);
  }

  String _format(
    AppLocalizations l10n,
    Formats formats,
    String control,
    Decimal value,
  ) => switch (control) {
    'amount' ||
    'monthly' ||
    'spending' ||
    'saving' => formats.amount(value, Currency.eur),
    'years' => l10n.toy_years(value.toBigInt().toInt()),
    'months' => l10n.toy_months(value.toBigInt().toInt()),
    'return' => formats.percent(value, signed: true),
    _ => formats.percent(value),
  };
}

/// One input: its name and value, then a slider on its steps.
class _ToySlider extends StatelessWidget {
  const _ToySlider({
    required this.control,
    required this.label,
    required this.value,
    required this.shown,
    required this.onStep,
  });

  final ToyControl control;
  final String label;
  final Decimal value;
  final String shown;
  final void Function(int index) onStep;

  @override
  Widget build(BuildContext context) {
    final min = control.min.toDouble();
    final step = control.step.toDouble();
    final divisions = ((control.max - control.min) / control.step)
        .toDecimal(scaleOnInfinitePrecision: 0)
        .toBigInt()
        .toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppText.bodyStrong)),
            Text(shown, style: AppText.figure.copyWith(color: AppColors.ink)),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min,
          max: control.max.toDouble(),
          divisions: divisions > 0 ? divisions : null,
          semanticFormatterCallback: (_) => shown,
          onChanged: (v) => onStep(((v - min) / step).round()),
        ),
      ],
    );
  }
}
