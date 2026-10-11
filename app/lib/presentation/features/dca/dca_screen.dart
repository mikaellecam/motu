import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/dca/dca_simulator.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/wallet/dca.dart';
import '../../../domain/wallet/dca_simulator.dart';
import '../../../domain/wallet/trip_start.dart';
import '../../widgets/sign_color.dart';
import '../node/reveal_chart.dart';

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
            Text(l10n.dca_intro, style: Theme.of(context).textTheme.bodyMedium),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: view.assets.any((a) => a.id == form.assetId)
                  ? form.assetId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.dca_asset),
              items: [
                for (final a in view.assets)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (id) {
                if (id != null) actions.setAsset(id);
              },
            ),
            const SizedBox(height: AppSpace.x3),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.dca_amount,
                suffixText: '€',
              ),
              onChanged: actions.setAmount,
            ),
            for (final e in view.amountErrors)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.x1),
                child: Text(amountError(e), style: error),
              ),
            const SizedBox(height: AppSpace.x3),
            SegmentedButton<DcaFrequency>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: DcaFrequency.monthly,
                  label: Text(l10n.dca_monthly),
                ),
                ButtonSegment(
                  value: DcaFrequency.weekly,
                  label: Text(l10n.dca_weekly),
                ),
              ],
              selected: {form.frequency},
              onSelectionChanged: (s) => actions.setFrequency(s.single),
            ),
            const SizedBox(height: AppSpace.x3),
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
              decoration: InputDecoration(labelText: l10n.dca_date),
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

class _ResultCard extends ConsumerWidget {
  const _ResultCard(this.r);
  final DcaResult r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final dca = r.dca;
    String eur(Decimal v) => formats.amount(v, Currency.eur);
    String change(Decimal value) => formats.percent(
      ratio(value - dca.invested.amount, dca.invested.amount),
      signed: true,
    );
    final first = dca.series.isEmpty ? r.params.start : dca.series.first.date;

    final insight = switch (r.insight) {
      DcaLoss(change: final c) => l10n.dca_insight_loss(
        eur(dca.finalValue),
        formats.money(dca.invested),
        formats.percent(c, signed: true),
      ),
      DcaCheapYear(:final year, :final discount) => l10n.dca_insight_cheap_year(
        '$year',
        formats.percent(discount),
      ),
      DcaVersusLumpSum(dcaAhead: true, :final difference) =>
        l10n.dca_insight_dca_ahead(eur(difference)),
      DcaVersusLumpSum(:final difference) => l10n.dca_insight_lump_ahead(
        eur(difference),
      ),
      null => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(r.asset.name, style: text.titleMedium),
                Text(
                  l10n.dca_period(
                    formats.date(first),
                    formats.date(r.end),
                    dca.purchases.length,
                  ),
                  style: muted,
                ),
                const SizedBox(height: AppSpace.x3),
                ChartLegendRow(
                  label: l10n.dca_invested,
                  value: formats.money(dca.invested),
                ),
                ChartLegendRow(
                  label: l10n.dca_final,
                  value: eur(dca.finalValue),
                ),
                ChartLegendRow(
                  label: l10n.dca_gain,
                  value: formats.amount(dca.gain, Currency.eur, signed: true),
                  change: dca.gainRatio == null
                      ? null
                      : formats.percent(dca.gainRatio!, signed: true),
                  changeColor: signColor(dca.gain),
                ),
                const SizedBox(height: AppSpace.x3),
                RevealChart(
                  lines: [
                    ChartLine([
                      for (final p in dca.series)
                        (
                          p.date.millisecondsSinceEpoch.toDouble(),
                          p.value.toDouble(),
                        ),
                    ], AppColors.primary),
                    ChartLine([
                      for (final p in dca.series)
                        (
                          p.date.millisecondsSinceEpoch.toDouble(),
                          p.invested.amount.toDouble(),
                        ),
                    ], AppColors.muted),
                  ],
                  semanticsLabel: l10n.dca_chart_semantics(
                    formats.date(first),
                    formats.date(r.end),
                    formats.money(dca.invested),
                  ),
                ),
                const SizedBox(height: AppSpace.x2),
                ChartLegendRow(
                  color: AppColors.primary,
                  label: l10n.dca_value,
                  value: eur(dca.finalValue),
                ),
                ChartLegendRow(
                  color: AppColors.muted,
                  label: l10n.wallet_chart_money_in,
                  value: formats.money(dca.invested),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.x4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.dca_compare_title, style: text.titleMedium),
                const SizedBox(height: AppSpace.x2),
                for (final (label, value) in [
                  (l10n.dca_compare_dca, dca.finalValue),
                  (l10n.dca_compare_lump_sum, r.lumpSum.finalValue),
                  (l10n.dca_compare_livret, r.livret.finalValue),
                ])
                  ChartLegendRow(
                    label: label,
                    value: eur(value),
                    change: change(value),
                    changeColor: signColor(value - dca.invested.amount),
                  ),
                if (r.livret.capped)
                  Text(
                    l10n.dca_livret_capped(formats.money(r.livret.uninvested)),
                    style: muted,
                  ),
              ],
            ),
          ),
        ),
        if (insight != null) ...[
          const SizedBox(height: AppSpace.x4),
          ChunkyCard(child: Text(insight, style: text.bodyMedium)),
        ],
        const SizedBox(height: AppSpace.x3),
        OutlinedButton(
          onPressed: () async {
            await ref.read(dcaFormControllerProvider.notifier).save(r);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.dca_saved_done)));
          },
          child: Text(l10n.dca_save),
        ),
      ],
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
    final text = Theme.of(context).textTheme;
    final names = {for (final a in view.assets) a.id: a.name};
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
              child: Text(l10n.dca_saved_title, style: text.titleMedium),
            ),
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
    );
  }
}
