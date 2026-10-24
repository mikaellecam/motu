import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/dca/dca_simulator.dart';
import '../../../application/learning/content.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/wallet/dca.dart';
import '../../../domain/wallet/dca_simulator.dart';
import '../../../domain/wallet/trip_start.dart';
import '../../widgets/chart_axis.dart';
import '../../widgets/chart_legend.dart';
import '../../widgets/section_title.dart';
import '../../widgets/sign_color.dart';
import '../glossary/term_sheet.dart';
import '../node/node_screen.dart' show LessonCard;

/// The DCA simulator (BRIEF §4.10): the form, the result against the same
/// money put in at once and on a Livret A, the companion's insight, and the
/// saved simulations.
class DcaScreen extends ConsumerStatefulWidget {
  const DcaScreen({super.key});

  @override
  ConsumerState<DcaScreen> createState() => _DcaScreenState();
}

class _DcaScreenState extends ConsumerState<DcaScreen> {
  final _amount = TextEditingController();
  final _date = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    super.dispose();
  }

  /// A saved simulation loaded into the form: the fields follow.
  void _sync(TextEditingController controller, String text) {
    if (controller.text != text) controller.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(dcaFormViewProvider);
    final form = ref.watch(dcaFormControllerProvider);
    _sync(_amount, form.amount);
    _sync(_date, form.date);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dca_title)),
      body: switch (view) {
        AsyncValue(:final value?) => ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            Text(
              l10n.dca_intro,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpace.x4),
            _Form(value, amount: _amount, date: _date),
            if (form.run case final run?) ...[
              const SizedBox(height: AppSpace.x4),
              _Result(run),
            ],
            const SizedBox(height: AppSpace.x4),
            _Saved(value),
          ],
        ),
        AsyncValue(:final error?) => Center(
          child: ErrorView(
            failure: error is Failure ? error : const ServerFailure(),
            onRetry: () => ref.invalidate(dcaFormViewProvider),
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

Formats _formats(BuildContext context) =>
    Formats(Localizations.localeOf(context).languageCode);

class _Form extends ConsumerWidget {
  const _Form(this.view, {required this.amount, required this.date});

  final DcaFormView view;
  final TextEditingController amount;
  final TextEditingController date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final actions = ref.read(dcaFormControllerProvider.notifier);
    final form = view.form;
    final error = text.bodySmall?.copyWith(color: AppColors.alertText);
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final showErrors = form.submitted || form.date.isNotEmpty;

    String amountError(ValidationFailure e) => switch (e.code) {
      'amount_too_large' => l10n.dca_error_too_large(
        formats.money(e.params['max']! as Money),
      ),
      'amount_below_fees' => l10n.dca_error_fees(
        formats.money(e.params['fees']! as Money),
      ),
      _ => l10n.order_error_amount_not_positive,
    };
    final startNote = switch (view.start) {
      StartUnreadable() when showErrors => (l10n.wizard_date_unreadable, error),
      StartBeforeFloor(:final floor) => (
        l10n.wizard_date_before_floor(formats.date(floor)),
        error,
      ),
      StartTooRecent(:final latest) => (
        l10n.dca_date_too_recent(formats.date(latest)),
        error,
      ),
      StartOk(:final date, :final rolledFrom?) => (
        l10n.dca_date_rolled(formats.date(rolledFrom), formats.date(date)),
        muted,
      ),
      _ => null,
    };

    // Outlined boxes, as in the trip wizard; what is typed reads like what
    // the lists show.
    final valueStyle = text.titleMedium;
    InputDecoration box(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.surface,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(AppShape.flatButtonRadius),
        ),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: view.assets.any((a) => a.id == form.assetId)
                  ? form.assetId
                  : null,
              isExpanded: true,
              decoration: box(l10n.dca_asset),
              items: [
                for (final a in view.assets)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (id) {
                if (id != null) actions.setAsset(id);
              },
            ),
            const SizedBox(height: AppSpace.x4),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: valueStyle,
                    decoration: box(l10n.dca_amount).copyWith(suffixText: '€'),
                    onChanged: actions.setAmount,
                  ),
                ),
                const SizedBox(width: AppSpace.x3),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<DcaFrequency>(
                    initialValue: form.frequency,
                    isExpanded: true,
                    decoration: box(l10n.dca_frequency),
                    items: [
                      for (final (f, label) in [
                        (DcaFrequency.monthly, l10n.dca_monthly),
                        (DcaFrequency.weekly, l10n.dca_weekly),
                      ])
                        DropdownMenuItem(
                          value: f,
                          child: Text(label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (f) {
                      if (f != null) actions.setFrequency(f);
                    },
                  ),
                ),
              ],
            ),
            for (final e in view.amountErrors)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.x1),
                child: Text(amountError(e), style: error),
              ),
            const SizedBox(height: AppSpace.x4),
            Text(l10n.dca_since, style: text.titleSmall),
            const SizedBox(height: AppSpace.x1),
            Wrap(
              spacing: AppSpace.x2,
              children: [
                for (final years in dcaYears)
                  ChoiceChip(
                    label: Text(l10n.dca_years(years)),
                    selected: view.years == years,
                    onSelected: (_) => actions.setYears(years),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.x2),
            TextField(
              controller: date,
              keyboardType: TextInputType.datetime,
              style: valueStyle,
              decoration: box(l10n.dca_date),
              onChanged: actions.setDate,
            ),
            if (startNote case (final note, final style))
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.x1),
                child: Text(note, style: style),
              ),
            const SizedBox(height: AppSpace.x4),
            FilledButton(
              onPressed: () => actions.simulate(view.params),
              child: Text(l10n.dca_simulate),
            ),
          ],
        ),
      ),
    );
  }
}

class _Result extends ConsumerWidget {
  const _Result(this.params);
  final DcaParams params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(dcaRunProvider(params));
    return switch (run) {
      AsyncValue(:final value?) => _ResultCard(value),
      AsyncValue(:final error?) => ErrorView(
        failure: error is Failure ? error : const ServerFailure(),
        onRetry: () => ref.invalidate(dcaRunProvider(params)),
      ),
      _ => const AsyncSkeleton(lines: 5),
    };
  }
}

/// The glossary term the companion's note links to.
const _dcaTerm = 'dca';

/// The result (artboard DCA-A): what was put in and what it would be worth,
/// the chart, the same money put in at once and on a Livret A, the
/// companion's note, « Enregistrer ».
class _ResultCard extends ConsumerWidget {
  const _ResultCard(this.r);
  final DcaResult r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final dca = r.dca;
    final invested = dca.invested.amount;
    // Round euros, as in the artboard; the gain's colour follows the figure
    // shown.
    String whole(Decimal v) => formats.amount(v, Currency.eur, decimals: 0);
    final gain = roundHalfEven(dca.gain, 0);
    final first = dca.series.isEmpty ? r.params.start : dca.series.first.date;
    final term = ref
        .watch(contentPackProvider(actionsEtfIsland))
        .value
        ?.glossary[_dcaTerm]
        ?.title;

    final insight = switch (r.insight) {
      DcaLoss(change: final c) => l10n.dca_insight_loss(
        formats.amount(dca.finalValue, Currency.eur),
        formats.money(dca.invested),
        formats.percent(c, signed: true),
      ),
      DcaCheapYear(:final year, :final discount) => l10n.dca_insight_cheap_year(
        '$year',
        formats.percent(discount),
      ),
      DcaVersusLumpSum(dcaAhead: true, :final difference) =>
        l10n.dca_insight_dca_ahead(formats.amount(difference, Currency.eur)),
      DcaVersusLumpSum(:final difference) => l10n.dca_insight_lump_ahead(
        formats.amount(difference, Currency.eur),
      ),
      null => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LessonCard(
          label: l10n.dca_result(dca.purchases.length),
          children: [
            Text(
              l10n.dca_period(
                r.asset.name,
                formats.date(first),
                formats.date(r.end),
              ),
              style: muted,
            ),
            // Side by side, or one under the other when they do not fit.
            LayoutBuilder(
              builder: (context, box) => Wrap(
                spacing: AppSpace.x3,
                runSpacing: AppSpace.x2,
                children: [
                  for (final (label, value) in [
                    (l10n.dca_invested, invested),
                    (l10n.dca_final, dca.finalValue),
                  ])
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: (box.maxWidth - AppSpace.x3) / 2,
                      ),
                      child: MergeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(label, style: muted),
                            Text(
                              whole(value),
                              style: AppText.figureLarge.copyWith(
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              [
                formats.amount(gain, Currency.eur, signed: true, decimals: 0),
                if (dca.gainRatio case final ratio?)
                  '(${formats.percent(ratio, signed: true)})',
              ].join(' '),
              style: AppText.bodyStrong.copyWith(color: signColor(gain)),
            ),
          ],
        ),
        if (dca.series.length > 1) ...[
          const SizedBox(height: AppSpace.x4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: AppSpace.x4,
                    runSpacing: AppSpace.x1,
                    children: [
                      ChartLegend(l10n.dca_value, color: AppColors.primary),
                      ChartLegend(
                        l10n.wallet_chart_money_in,
                        color: AppColors.muted,
                        dashed: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.x3),
                  SizedBox(height: 180, child: _Chart(r)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.x4),
        TitledSection(
          title: l10n.dca_compare_title,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.x4,
                vertical: AppSpace.x2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, (label, value)) in [
                    (l10n.dca_compare_dca, dca.finalValue),
                    (l10n.dca_compare_lump_sum, r.lumpSum.finalValue),
                    (l10n.dca_compare_livret, r.livret.finalValue),
                  ].indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    // The name on one line, its figures stacked beside it.
                    MergeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpace.x2,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(label, style: text.bodyMedium),
                            ),
                            const SizedBox(width: AppSpace.x3),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  whole(value),
                                  style: AppText.figure.copyWith(
                                    color: AppColors.ink,
                                  ),
                                ),
                                Text(
                                  formats.percent(
                                    ratio(value - invested, invested),
                                    signed: true,
                                  ),
                                  style: AppText.caption.copyWith(
                                    color: signColor(value - invested),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (r.livret.capped)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.x2),
                      child: Text(
                        l10n.dca_livret_capped(
                          formats.money(r.livret.uninvested),
                        ),
                        style: muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (insight != null) ...[
          const SizedBox(height: AppSpace.x4),
          LessonCard(
            label: l10n.companion_kicker,
            children: [
              Text(insight, style: AppText.body),
              if (term != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    label: Text(term.of(language)),
                    onPressed: () => showTermSheet(context, _dcaTerm),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpace.x4),
        ChunkyButton(
          label: l10n.dca_save,
          kind: ChunkyButtonKind.secondary,
          onPressed: () async {
            await ref.read(dcaFormControllerProvider.notifier).save(r);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.dca_saved_done)));
          },
        ),
      ],
    );
  }
}

/// The value of the purchases over the money put in, dated like the other
/// money charts (§10.1): a light fill under the value, a dot where it ends.
class _Chart extends StatelessWidget {
  const _Chart(this.r);
  final DcaResult r;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final series = r.dca.series;
    // Doubles from here on: pixels, not money.
    List<FlSpot> spots(Decimal Function(ValuePoint p) y) => [
      for (final (i, p) in series.indexed)
        FlSpot(i.toDouble(), y(p).toDouble()),
    ];
    final value = spots((p) => p.value);
    final paid = spots((p) => p.invested.amount);
    final ys = [
      for (final s in [...value, ...paid]) s.y,
    ];
    final low = ys.reduce((a, b) => a < b ? a : b);
    final high = ys.reduce((a, b) => a > b ? a : b);
    final margin = (high - low) * 0.1 + 1;

    return Semantics(
      label: l10n.dca_chart_semantics(
        formats.date(series.first.date),
        formats.date(r.end),
        formats.money(r.dca.invested),
      ),
      excludeSemantics: true,
      child: LineChart(
        LineChartData(
          minY: low - margin,
          maxY: high + margin,
          gridData: const FlGridData(show: false),
          titlesData: dateAxis(
            [for (final p in series) p.date],
            formats,
            style: AppText.caption.copyWith(color: AppColors.muted),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: paid,
              color: AppColors.muted,
              barWidth: 1.5,
              dashArray: const [6, 4],
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: value,
              color: AppColors.primary,
              barWidth: 2.5,
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              dotData: FlDotData(
                checkToShowDot: (spot, _) => spot.x == value.length - 1,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: AppColors.primary,
                  strokeColor: AppColors.surface,
                  strokeWidth: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Saved extends ConsumerWidget {
  const _Saved(this.view);
  final DcaFormView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedDcaProvider).value ?? const [];
    if (saved.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final names = {for (final a in view.assets) a.id: a.name};
    return TitledSection(
      title: l10n.dca_saved_title,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in saved)
                ListTile(
                  title: Text(names[s.params.assetId] ?? s.params.assetId),
                  subtitle: Text(
                    [
                      l10n.dca_saved_row(
                        formats.money(s.params.amount),
                        s.params.frequency.name,
                        formats.date(s.params.start),
                      ),
                      l10n.dca_saved_result(
                        formats.amount(s.summary.finalValue, Currency.eur),
                        formats.money(s.summary.invested),
                        formats.date(s.summary.end),
                      ),
                    ].join('\n'),
                  ),
                  trailing: TextButton(
                    onPressed: () => ref
                        .read(dcaFormControllerProvider.notifier)
                        .load(s.params),
                    child: Text(l10n.dca_rerun),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
