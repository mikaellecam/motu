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
/// assumption. Done once every slider moved.
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
        final years = l10n.toy_years(s.value('years').toBigInt().toInt());
        // Each line: its name, its yearly values, its color.
        final (lines, result) = switch (s.outcome) {
          FeesOutcome(:final result) => (
            [
              (
                l10n.toy_fee_line(formats.percent(s.value('fee_low'))),
                result.low,
                lineColors[0],
              ),
              (
                l10n.toy_fee_line(formats.percent(s.value('fee_high'))),
                result.high,
                lineColors[1],
              ),
            ],
            l10n.toy_fees_result(
              years,
              formats.amount(result.gap, Currency.eur),
            ),
          ),
          CompoundOutcome(:final result) => (
            [
              (l10n.toy_value, result.value, lineColors[0]),
              (l10n.toy_money_in, result.moneyIn, lineColors[2]),
            ],
            l10n.toy_compound_result(
              years,
              formats.amount(result.value.last, Currency.eur),
              formats.amount(result.moneyIn.last, Currency.eur),
            ),
          ),
        };
        final rate = formats.percent(s.value('return'), signed: true);
        final past = s.view.past;

        return ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            Text(s.view.node.title.of(language), style: AppText.title),
            const SizedBox(height: AppSpace.x2),
            TermText(toy.intro.of(language), terms: s.view.terms),
            const SizedBox(height: AppSpace.x4),
            ChunkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RevealChart(
                    lines: [
                      for (final (_, values, color) in lines)
                        ChartLine([
                          for (final (year, v) in values.indexed)
                            (year.toDouble(), v.toDouble()),
                        ], color),
                    ],
                    animate: false,
                    semanticsLabel: l10n.node_chart_semantics(
                      [
                        for (final (label, values, _) in lines)
                          l10n.node_chart_line(
                            label,
                            formats.amount(values.first, Currency.eur),
                            formats.amount(values.last, Currency.eur),
                          ),
                      ].join('; '),
                    ),
                  ),
                  const SizedBox(height: AppSpace.x3),
                  for (final (label, values, color) in lines)
                    ChartLegendRow(
                      color: color,
                      label: label,
                      value: formats.amount(values.last, Currency.eur),
                    ),
                  const SizedBox(height: AppSpace.x2),
                  Semantics(
                    liveRegion: true,
                    child: Text(result, style: AppText.bodyStrong),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.x2),
            Text(
              s.returnIsPast && past != null && toy.returnFrom != null
                  ? l10n.toy_return_past(
                      rate,
                      toy.returnFrom!.label.of(language),
                      '${past.from.year}',
                      '${past.to.year}',
                    )
                  : l10n.toy_return_hypothesis(rate),
              style: muted,
            ),
            const SizedBox(height: AppSpace.x4),
            for (final c in toy.controls)
              _ToySlider(
                control: c,
                label: c.label.of(language),
                value: s.value(c.id),
                shown: _format(l10n, formats, c.id, s.value(c.id)),
                onStep: (index) => actions.setStep(c.id, index),
              ),
            const SizedBox(height: AppSpace.x4),
            TermText(toy.explanation.of(language), terms: s.view.terms),
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

  String _format(
    AppLocalizations l10n,
    Formats formats,
    String control,
    Decimal value,
  ) => switch (control) {
    'amount' || 'monthly' => formats.amount(value, Currency.eur),
    'years' => l10n.toy_years(value.toBigInt().toInt()),
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
