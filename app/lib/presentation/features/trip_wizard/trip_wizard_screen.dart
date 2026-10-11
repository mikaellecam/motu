import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/trip/trip_wizard.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/wallet/trip_setup.dart';
import '../../../domain/wallet/trip_start.dart';

/// The trip wizard (BRIEF §4.5), chunky « world » style: the start date, the
/// difficulty, then the recap that creates the trip.
class TripWizardScreen extends ConsumerStatefulWidget {
  const TripWizardScreen({super.key, this.args = const TripWizardArgs()});

  final TripWizardArgs args;

  @override
  ConsumerState<TripWizardScreen> createState() => _TripWizardScreenState();
}

class _TripWizardScreenState extends ConsumerState<TripWizardScreen> {
  final _custom = TextEditingController();

  @override
  void initState() {
    super.initState();
    final wizard = ref.read(tripWizardProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await wizard.prefill(widget.args);
      if (mounted) _custom.text = ref.read(tripWizardProvider).custom;
    });
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(tripWizardProvider);
    final wizard = ref.read(tripWizardProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.wallets_new_trip),
        leading: draft.step > 1 ? BackButton(onPressed: wizard.back) : null,
      ),
      body: switch (draft.step) {
        1 => _DateStep(draft: draft, custom: _custom),
        2 => _DifficultyStep(draft: draft),
        _ => _RecapStep(draft: draft),
      },
    );
  }
}

class _DateStep extends ConsumerWidget {
  const _DateStep({required this.draft, required this.custom});

  final TripDraft draft;
  final TextEditingController custom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final wizard = ref.read(tripWizardProvider.notifier);
    final state = ref.watch(wizardDatesProvider);
    final dates = state.value;
    if (dates == null) {
      return state.hasError
          ? Center(
              child: ErrorView(
                failure: state.error is Failure
                    ? state.error! as Failure
                    : const ServerFailure(),
                onRetry: () => ref.invalidate(wizardDatesProvider),
              ),
            )
          : const Padding(
              padding: EdgeInsets.all(AppSpace.screenPadding),
              child: AsyncSkeleton(lines: 6),
            );
    }

    Widget preset(PresetOption option) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.x3),
      child: _PresetCard(
        option,
        catalogueSize: dates.catalogueSize,
        selected: draft.preset == option.preset,
        onTap: () {
          custom.clear();
          wizard.choose(option);
        },
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpace.screenPadding),
      children: [
        Text(
          l10n.wizard_step(1),
          style: text.bodySmall?.copyWith(color: AppColors.muted),
        ),
        Text(l10n.wizard_when, style: AppText.title),
        const SizedBox(height: AppSpace.x4),
        Text(l10n.wizard_history, style: text.titleMedium),
        const SizedBox(height: AppSpace.x2),
        for (final o in dates.presets)
          if (o.preset.historic) preset(o),
        const SizedBox(height: AppSpace.x2),
        Text(l10n.wizard_quick, style: text.titleMedium),
        const SizedBox(height: AppSpace.x2),
        for (final o in dates.presets)
          if (!o.preset.historic) preset(o),
        const SizedBox(height: AppSpace.x2),
        Text(l10n.wizard_custom, style: text.titleMedium),
        const SizedBox(height: AppSpace.x2),
        TextField(
          controller: custom,
          keyboardType: TextInputType.datetime,
          decoration: InputDecoration(
            hintText: l10n.wizard_custom_hint,
            filled: true,
            fillColor: AppColors.surface,
            border: const OutlineInputBorder(),
          ),
          onChanged: wizard.type,
        ),
        if (draft.preset == null)
          _CustomVerdict(draft: draft, catalogue: dates),
        const SizedBox(height: AppSpace.x6),
        ChunkyButton(
          label: l10n.wizard_next,
          onPressed: draft.start == null ? null : wizard.next,
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard(
    this.option, {
    required this.catalogueSize,
    required this.selected,
    required this.onTap,
  });

  final PresetOption option;
  final int catalogueSize;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final title = presetTitle(l10n, option.preset);
    final teaser = switch (option.preset) {
      TripPreset.dotcom => l10n.wizard_teaser_dotcom,
      TripPreset.lehman => l10n.wizard_teaser_lehman,
      TripPreset.covid => l10n.wizard_teaser_covid,
      TripPreset.inflation => l10n.wizard_teaser_inflation,
      _ => null,
    };

    return _ChoiceCard(
      selected: selected,
      onTap: onTap,
      children: [
        Text(title, style: text.titleMedium),
        Text(formats.date(option.date), style: muted),
        if (teaser != null) ...[
          const SizedBox(height: AppSpace.x1),
          Text(teaser, style: text.bodyMedium),
        ],
        const SizedBox(height: AppSpace.x1),
        Text(
          l10n.wizard_available(option.available, catalogueSize),
          style: muted,
        ),
      ],
    );
  }
}

/// What the typed date gives: an error, the day the trip moves to, or how
/// many assets existed then.
class _CustomVerdict extends ConsumerWidget {
  const _CustomVerdict({required this.draft, required this.catalogue});

  final TripDraft draft;
  final WizardDates catalogue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final error = text.bodyMedium?.copyWith(color: AppColors.alertText);
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    if (draft.custom.trim().isEmpty) return const SizedBox.shrink();

    final lines = <Widget>[
      ...switch (draft.check) {
        null => const <Widget>[],
        StartUnreadable() => [Text(l10n.wizard_date_unreadable, style: error)],
        StartBeforeFloor(:final floor) => [
          Text(
            l10n.wizard_date_before_floor(formats.date(floor)),
            style: error,
          ),
          if (ref.watch(lessonBeforeProvider(parseDay(draft.custom)!)).value
              case final lesson?)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.push('/node/${lesson.id}'),
                child: Text(
                  l10n.wizard_lesson_link(
                    lesson.title.of(
                      Localizations.localeOf(context).languageCode,
                    ),
                  ),
                ),
              ),
            ),
        ],
        StartTooRecent(:final latest) => [
          Text(l10n.wizard_date_too_recent(formats.date(latest)), style: error),
        ],
        StartOk(:final date, :final rolledFrom) => [
          if (rolledFrom != null)
            Text(
              l10n.wizard_date_rolled(
                formats.date(rolledFrom),
                formats.date(date),
              ),
              style: text.bodyMedium,
            ),
          Text(
            l10n.wizard_available(
              catalogue.availableOn(date),
              catalogue.catalogueSize,
            ),
            style: muted,
          ),
        ],
      },
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }
}

/// A moment's name, also the trip's default name.
String presetTitle(AppLocalizations l10n, TripPreset preset) =>
    switch (preset) {
      TripPreset.dotcom => l10n.wizard_preset_dotcom,
      TripPreset.lehman => l10n.wizard_preset_lehman,
      TripPreset.covid => l10n.wizard_preset_covid,
      TripPreset.inflation => l10n.wizard_preset_inflation,
      _ => l10n.wizard_years_ago(preset.years!),
    };

String _difficultyName(AppLocalizations l10n, Difficulty d) => switch (d) {
  Difficulty.decouverte => l10n.difficulty_decouverte,
  Difficulty.realiste => l10n.difficulty_realiste,
  Difficulty.serre => l10n.difficulty_serre,
  Difficulty.surMesure => l10n.difficulty_sur_mesure,
};

/// « 50 000 € au départ · 200 € par mois · … », one line per setting.
List<String> _summary(AppLocalizations l10n, Formats formats, TripSettings s) {
  final percent = s.fxFeeRate.shift(2);
  return [
    l10n.wizard_cash(formats.money(s.startingCash)),
    s.monthlyContribution.isZero
        ? l10n.wizard_no_contribution
        : l10n.wizard_contribution(formats.money(s.monthlyContribution)),
    l10n.wizard_fx_fee(
      formats.percent(s.fxFeeRate, decimals: percent.scale.clamp(0, 2)),
    ),
    s.fixedFee.isZero
        ? l10n.wizard_no_fixed_fee
        : l10n.wizard_fixed_fee(formats.money(s.fixedFee)),
    s.fractionalShares ? l10n.wizard_fractional : l10n.wizard_whole,
  ];
}

Formats _formats(BuildContext context) =>
    Formats(Localizations.localeOf(context).languageCode);

class _DifficultyStep extends ConsumerWidget {
  const _DifficultyStep({required this.draft});
  final TripDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final wizard = ref.read(tripWizardProvider.notifier);
    final settings = draft.settings;
    final start = draft.start!;
    final ceiling = ref.watch(livretCeilingOnProvider(start)).value;
    final percent = draft.cushionPercent;
    final kept = settings == null || percent == null || ceiling == null
        ? null
        : cushion(settings.startingCash, percent, ceiling: ceiling);

    return ListView(
      padding: const EdgeInsets.all(AppSpace.screenPadding),
      children: [
        Text(
          l10n.wizard_step(2),
          style: text.bodySmall?.copyWith(color: AppColors.muted),
        ),
        Text(l10n.wizard_how, style: AppText.title),
        const SizedBox(height: AppSpace.x4),
        for (final d in Difficulty.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.x3),
            child: _ChoiceCard(
              selected: draft.difficulty == d,
              onTap: () => wizard.chooseDifficulty(d),
              children: [
                Text(_difficultyName(l10n, d), style: text.titleMedium),
                if (d != Difficulty.surMesure)
                  for (final line in _summary(l10n, formats, presetSettings(d)))
                    Text(
                      line,
                      style: text.bodySmall?.copyWith(color: AppColors.muted),
                    ),
              ],
            ),
          ),
        if (draft.difficulty == Difficulty.surMesure) _CustomFields(draft),
        if (settings != null &&
            (settings.fixedFee.isPositive || !settings.fractionalShares)) ...[
          const SizedBox(height: AppSpace.x2),
          ChunkyCard(child: Text(l10n.wizard_small_budget)),
        ],
        const SizedBox(height: AppSpace.x4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.wizard_cushion),
          value: percent != null,
          onChanged: (on) => wizard.setCushion(on ? 20 : null),
        ),
        if (percent != null) ...[
          Wrap(
            spacing: AppSpace.x2,
            children: [
              for (final share in cushionShares)
                ChoiceChip(
                  label: Text(
                    formats.percent(
                      Decimal.fromInt(share).shift(-2),
                      decimals: 0,
                    ),
                  ),
                  selected: percent == share,
                  showCheckmark: false,
                  onSelected: (_) => wizard.setCushion(share),
                ),
            ],
          ),
          if (kept != null) ...[
            const SizedBox(height: AppSpace.x2),
            Text(l10n.wizard_cushion_amount(formats.money(kept.amount))),
            if (kept.capped)
              Text(
                l10n.wizard_cushion_capped(formats.money(ceiling!)),
                style: text.bodySmall?.copyWith(color: AppColors.muted),
              ),
          ],
        ],
        const SizedBox(height: AppSpace.x6),
        ChunkyButton(
          label: l10n.wizard_next,
          onPressed: draft.settingsValid ? wizard.next : null,
        ),
      ],
    );
  }
}

/// A chunky card the user picks, marked with a check once picked.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.onTap,
    required this.children,
  });

  final bool selected;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: ChunkyCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: AppSpace.x2),
                child: Icon(Icons.check_circle, color: AppColors.ink),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The « Sur mesure » fields, starting from Réaliste's values.
class _CustomFields extends ConsumerStatefulWidget {
  const _CustomFields(this.draft);
  final TripDraft draft;

  @override
  ConsumerState<_CustomFields> createState() => _CustomFieldsState();
}

class _CustomFieldsState extends ConsumerState<_CustomFields> {
  late final Map<SettingField, TextEditingController> _fields;

  @override
  void initState() {
    super.initState();
    final base = presetSettings(Difficulty.surMesure);
    String plain(Decimal value) => value.toString();
    final start = {
      SettingField.startingCash: plain(base.startingCash.amount),
      SettingField.contribution: plain(base.monthlyContribution.amount),
      SettingField.fxFee: plain(base.fxFeeRate.shift(2)),
      SettingField.fixedFee: plain(base.fixedFee.amount),
    };
    _fields = {
      for (final f in SettingField.values)
        f: TextEditingController(text: widget.draft.customText[f] ?? start[f]),
    };
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final wizard = ref.read(tripWizardProvider.notifier);
    final errors = widget.draft.settingErrors;
    String? message(SettingField field) => switch (errors[field]) {
      null => null,
      'number' => l10n.wizard_err_number,
      'starting_cash_range' => l10n.wizard_err_cash,
      'contribution_range' => l10n.wizard_err_contribution,
      'contribution_below_fee' => l10n.wizard_err_contribution_fee(
        formats.money(
          widget.draft.settings?.fixedFee ?? const Money.zero(Currency.eur),
        ),
      ),
      'fx_fee_range' => l10n.wizard_err_fx_fee,
      _ => l10n.wizard_err_fixed_fee,
    };

    return Column(
      children: [
        for (final (field, label) in [
          (SettingField.startingCash, l10n.wizard_field_cash),
          (SettingField.contribution, l10n.wizard_field_contribution),
          (SettingField.fxFee, l10n.wizard_field_fx_fee),
          (SettingField.fixedFee, l10n.wizard_field_fixed_fee),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.x3),
            child: TextField(
              controller: _fields[field],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: label,
                errorText: message(field),
                filled: true,
                fillColor: AppColors.surface,
                border: const OutlineInputBorder(),
              ),
              onChanged: (text) => wizard.setCustom(field, text),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.wizard_field_fractional),
          value: widget.draft.customFractional,
          onChanged: wizard.setFractional,
        ),
      ],
    );
  }
}

class _RecapStep extends ConsumerStatefulWidget {
  const _RecapStep({required this.draft});
  final TripDraft draft;

  @override
  ConsumerState<_RecapStep> createState() => _RecapStepState();
}

class _RecapStepState extends ConsumerState<_RecapStep> {
  final _name = TextEditingController();
  var _creating = false;

  String _defaultName(AppLocalizations l10n) {
    final preset = widget.draft.preset;
    if (preset != null) return presetTitle(l10n, preset);
    final d = widget.draft.start!;
    String two(int n) => n.toString().padLeft(2, '0');
    return l10n.wizard_name_custom('${two(d.day)}/${two(d.month)}/${d.year}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name.text.isEmpty) {
      _name.text =
          widget.draft.name ?? _defaultName(AppLocalizations.of(context));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _creating = true);
    try {
      final id = await ref
          .read(tripWizardProvider.notifier)
          .create(defaultName: _defaultName(l10n));
      if (mounted) context.go('/wallet/$id');
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final draft = widget.draft;
    final wizard = ref.read(tripWizardProvider.notifier);
    final start = draft.start!;
    final settings = draft.settings!;
    final ceiling = ref.watch(livretCeilingOnProvider(start)).value;
    final percent = draft.cushionPercent;
    final kept = percent == null || ceiling == null
        ? null
        : cushion(settings.startingCash, percent, ceiling: ceiling);
    final nameValid = tripName(_name.text) != null;

    Widget row(String label, List<String> values, int step) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: muted),
                for (final v in values) Text(v, style: text.bodyMedium),
              ],
            ),
          ),
          TextButton(
            onPressed: () => wizard.edit(step),
            child: Text(l10n.wizard_edit),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpace.screenPadding),
      children: [
        Text(l10n.wizard_step(3), style: muted),
        Text(l10n.wizard_recap, style: AppText.title),
        const SizedBox(height: AppSpace.x4),
        ChunkyCard(
          child: Column(
            children: [
              row(l10n.wizard_recap_start, [formats.date(start)], 1),
              row(l10n.wizard_recap_difficulty, [
                _difficultyName(l10n, draft.difficulty!),
                ..._summary(l10n, formats, settings),
              ], 2),
              row(l10n.wizard_recap_cushion, [
                kept == null
                    ? l10n.wizard_recap_none
                    : l10n.wizard_cushion_amount(formats.money(kept.amount)),
              ], 2),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.x4),
        TextField(
          controller: _name,
          maxLength: 30,
          decoration: InputDecoration(
            labelText: l10n.wizard_name,
            errorText: nameValid ? null : l10n.wizard_name_error,
            filled: true,
            fillColor: AppColors.surface,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            wizard.setName(value);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpace.x2),
        Text(l10n.wizard_stops, style: text.titleMedium),
        Text(l10n.wizard_stops_hint, style: muted),
        for (final (stop, label) in [
          (StopKind.portfolio, l10n.wizard_stop_portfolio),
          (StopKind.position, l10n.wizard_stop_position),
          (StopKind.orderFilled, l10n.wizard_stop_order),
          if (settings.monthlyContribution.isPositive)
            (StopKind.contribution, l10n.wizard_stop_contribution),
        ])
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            value: draft.stops.contains(stop),
            onChanged: (on) => wizard.setStop(stop, on),
          ),
        const SizedBox(height: AppSpace.x2),
        Text(l10n.wizard_known_only, style: muted),
        const SizedBox(height: AppSpace.x6),
        ChunkyButton(
          label: l10n.wizard_go(formats.date(start)),
          onPressed: nameValid && !_creating ? _create : null,
        ),
      ],
    );
  }
}
