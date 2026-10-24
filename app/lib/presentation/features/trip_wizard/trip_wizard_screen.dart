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
import '../../widgets/section_title.dart';
import '../node/node_screen.dart';

/// The trip wizard (BRIEF §4.5), chunky « world » style, as the art
/// direction's « new trip » artboards draw it: the start date, the
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
    final draft = ref.watch(tripWizardProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(step: draft.step),
            Expanded(
              child: switch (draft.step) {
                1 => _DateStep(draft: draft, custom: _custom),
                2 => _DifficultyStep(draft: draft),
                _ => _RecapStep(draft: draft),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// On every step: close, the step bar, and the step in words.
class _Header extends StatelessWidget {
  const _Header({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenPadding,
        AppSpace.x3,
        AppSpace.screenPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ChunkyIconButton(
                icon: Icons.close,
                label: l10n.wizard_close,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/wallets'),
              ),
              const SizedBox(width: AppSpace.x3),
              Expanded(child: StepBar(done: step, of: 3)),
            ],
          ),
          const SizedBox(height: AppSpace.x3),
          Text(
            l10n.wizard_step(step),
            style: AppText.label.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

/// A step's content, scrolling, over « Retour » (from step 2) beside the
/// next action, always in reach.
class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    this.hint,
    required this.children,
    required this.next,
    this.onBack,
    this.nextFlex = 1,
  });

  final String title;
  final String? hint;
  final List<Widget> children;
  final Widget next;
  final VoidCallback? onBack;

  /// The next action's share of the width, « Retour » taking 1.
  final int nextFlex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.screenPadding),
            children: [
              Semantics(header: true, child: Text(title, style: AppText.title)),
              if (hint case final hint?) ...[
                const SizedBox(height: AppSpace.x1),
                Text(
                  hint,
                  style: AppText.body.copyWith(color: AppColors.muted),
                ),
              ],
              const SizedBox(height: AppSpace.x4),
              ...children,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenPadding,
            AppSpace.x2,
            AppSpace.screenPadding,
            AppSpace.screenPadding,
          ),
          child: Row(
            children: [
              if (onBack != null) ...[
                Expanded(
                  child: ChunkyButton(
                    label: l10n.wizard_back,
                    kind: ChunkyButtonKind.secondary,
                    onPressed: onBack,
                  ),
                ),
                const SizedBox(width: AppSpace.x3),
              ],
              Expanded(flex: nextFlex, child: next),
            ],
          ),
        ),
      ],
    );
  }
}

/// One of the wizard's choices: quiet until chosen, then a toy block. Its
/// radio says which one is chosen, never colour alone. A [pill] is a short
/// one, side by side with others.
class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.onTap,
    required this.child,
    this.pill = false,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final border = selected ? AppShape.chunkyBorder : 2.0;
    // The same room inside, whichever the border.
    final inside =
        (pill ? AppSpace.x2 : AppSpace.x3) + AppShape.chunkyBorder - border;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSpace.minTarget),
            padding: EdgeInsets.symmetric(
              horizontal: inside + (pill ? AppSpace.x1 : 0),
              vertical: inside,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(
                pill ? AppSpace.x8 : AppShape.flatCardRadius,
              ),
              border: Border.all(
                color: selected ? AppColors.ink : AppColors.line,
                width: border,
              ),
              boxShadow: [
                if (selected)
                  const BoxShadow(
                    color: AppColors.ink,
                    offset: Offset(0, AppShape.chunkyButtonShadow),
                  ),
              ],
            ),
            child: Row(
              mainAxisSize: pill ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: pill
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? AppColors.ink : AppColors.muted,
                  ),
                ),
                const SizedBox(width: AppSpace.x3),
                if (pill) child else Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
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

    Widget option(PresetOption o) => _Option(
      selected: draft.preset == o.preset,
      pill: !o.preset.historic,
      onTap: () {
        custom.clear();
        wizard.choose(o);
      },
      child: o.preset.historic
          ? _Moment(o, catalogueSize: dates.catalogueSize)
          : _Shortcut(o, catalogueSize: dates.catalogueSize),
    );
    final check = draft.check;
    final wrong =
        draft.custom.trim().isNotEmpty && check != null && check is! StartOk;
    const alertBorder = OutlineInputBorder(
      borderSide: BorderSide(color: AppColors.alertText, width: 2),
    );

    return _Page(
      title: l10n.wizard_when,
      hint: l10n.wizard_when_hint,
      next: ChunkyButton(
        label: l10n.wizard_next,
        onPressed: draft.start == null ? null : wizard.next,
      ),
      children: [
        SectionTitle(l10n.wizard_history),
        for (final o in dates.presets)
          if (o.preset.historic) ...[
            option(o),
            const SizedBox(height: AppSpace.x3),
          ],
        SectionTitle(l10n.wizard_quick, top: AppSpace.x2),
        Wrap(
          spacing: AppSpace.x2,
          runSpacing: AppSpace.x2,
          children: [
            for (final o in dates.presets)
              if (!o.preset.historic) option(o),
          ],
        ),
        const SizedBox(height: AppSpace.x3),
        _Option(
          selected: draft.typing,
          onTap: () => wizard.type(custom.text),
          child: Row(
            children: [
              const ExcludeSemantics(
                child: Icon(Icons.calendar_today_outlined, size: 20),
              ),
              const SizedBox(width: AppSpace.x2),
              Expanded(
                child: Text(
                  l10n.wizard_custom_choose,
                  style: AppText.bodyStrong,
                ),
              ),
            ],
          ),
        ),
        if (draft.typing) ...[
          const SizedBox(height: AppSpace.x5),
          TextField(
            controller: custom,
            // Opened by a tap: ready to type.
            autofocus: draft.custom.isEmpty,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              labelText: l10n.wizard_start_date,
              hintText: l10n.wizard_custom_hint,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              filled: true,
              fillColor: AppColors.surface,
              suffixIcon: const ExcludeSemantics(
                child: Icon(Icons.calendar_today_outlined),
              ),
              border: const OutlineInputBorder(),
              enabledBorder: wrong ? alertBorder : null,
              focusedBorder: wrong ? alertBorder : null,
            ),
            onChanged: wizard.type,
          ),
          _CustomVerdict(draft: draft, catalogue: dates),
        ],
      ],
    );
  }
}

/// A historic moment: its name and day, its teaser, what existed then.
class _Moment extends StatelessWidget {
  const _Moment(this.option, {required this.catalogueSize});

  final PresetOption option;
  final int catalogueSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final teaser = switch (option.preset) {
      TripPreset.dotcom => l10n.wizard_teaser_dotcom,
      TripPreset.lehman => l10n.wizard_teaser_lehman,
      TripPreset.covid => l10n.wizard_teaser_covid,
      _ => l10n.wizard_teaser_inflation,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The day on the right, or under the name when both don't fit.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpace.x2,
          children: [
            Text(presetTitle(l10n, option.preset), style: AppText.titleSmall),
            Text(_formats(context).date(option.date), style: AppText.label),
          ],
        ),
        const SizedBox(height: AppSpace.x1),
        Text(teaser, style: AppText.body),
        const SizedBox(height: AppSpace.x1),
        Text(
          l10n.wizard_available(option.available, catalogueSize),
          style: AppText.caption.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

/// « Il y a N ans », with what existed then.
class _Shortcut extends StatelessWidget {
  const _Shortcut(this.option, {required this.catalogueSize});

  final PresetOption option;
  final int catalogueSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(presetTitle(l10n, option.preset), style: AppText.label),
        Text(
          l10n.wizard_available_short(option.available, catalogueSize),
          style: AppText.caption.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

/// What the typed date gives: an error in an alert box, or the day the trip
/// moves to and how many assets existed then.
class _CustomVerdict extends ConsumerWidget {
  const _CustomVerdict({required this.draft, required this.catalogue});

  final TripDraft draft;
  final WizardDates catalogue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    if (draft.custom.trim().isEmpty) return const SizedBox.shrink();

    final error = switch (draft.check) {
      StartUnreadable() => l10n.wizard_date_unreadable,
      StartBeforeFloor(:final floor) => l10n.wizard_date_before_floor(
        formats.date(floor),
      ),
      StartTooRecent(:final latest) => l10n.wizard_date_too_recent(
        formats.date(latest),
      ),
      _ => null,
    };
    final lesson = draft.check is StartBeforeFloor
        ? ref.watch(lessonBeforeProvider(parseDay(draft.custom)!)).value
        : null;
    final lines = <Widget>[
      if (error != null)
        AlertMessage(
          error,
          action: lesson == null
              ? null
              : TextButton(
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
      if (draft.check case StartOk(:final date, :final rolledFrom)) ...[
        if (rolledFrom != null)
          Text(
            l10n.wizard_date_rolled(
              formats.date(rolledFrom),
              formats.date(date),
            ),
            style: AppText.body,
          ),
        Text(
          l10n.wizard_available(
            catalogue.availableOn(date),
            catalogue.catalogueSize,
          ),
          style: AppText.caption.copyWith(color: AppColors.muted),
        ),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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

Formats _formats(BuildContext context) =>
    Formats(Localizations.localeOf(context).languageCode);

/// Whole euros without cents (« 50 000 € »), cents when there are some.
String _euros(Formats formats, Money money) => formats.amount(
  money.amount,
  money.currency,
  decimals: money.amount.isInteger ? 0 : 2,
);

/// « Sans frais », « Frais de change 0,15 % », « 1 € par ordre + change
/// 0,15 % ».
String _fees(AppLocalizations l10n, Formats formats, TripSettings s) {
  final percent = s.fxFeeRate.shift(2);
  final fx = s.fxFeeRate == Decimal.zero
      ? null
      : formats.percent(s.fxFeeRate, decimals: percent.scale.clamp(0, 2));
  final fixed = s.fixedFee.isPositive ? _euros(formats, s.fixedFee) : null;
  return switch ((fixed, fx)) {
    (null, null) => l10n.wizard_no_fees,
    (null, final fx?) => l10n.wizard_fx_fee(fx),
    (final fixed?, null) => l10n.wizard_fixed_fee(fixed),
    (final fixed?, final fx?) => l10n.wizard_fees(fixed, fx),
  };
}

/// A difficulty's settings, one fact per chip.
List<String> _facts(AppLocalizations l10n, Formats formats, TripSettings s) => [
  _euros(formats, s.startingCash),
  if (s.monthlyContribution.isPositive)
    l10n.wizard_contribution(_euros(formats, s.monthlyContribution)),
  _fees(l10n, formats, s),
  s.fractionalShares ? l10n.wizard_fractional : l10n.wizard_whole,
];

class _DifficultyStep extends ConsumerWidget {
  const _DifficultyStep({required this.draft});
  final TripDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final wizard = ref.read(tripWizardProvider.notifier);
    final settings = draft.settings;
    final start = draft.start!;
    final ceiling = ref.watch(livretCeilingOnProvider(start)).value;
    final percent = draft.cushionPercent;
    final kept = settings == null || percent == null || ceiling == null
        ? null
        : cushion(settings.startingCash, percent, ceiling: ceiling);

    return _Page(
      title: l10n.wizard_how,
      hint: l10n.wizard_departure(formats.date(start)),
      onBack: wizard.back,
      next: ChunkyButton(
        label: l10n.wizard_next,
        onPressed: draft.settingsValid ? wizard.next : null,
      ),
      children: [
        for (final d in Difficulty.values) ...[
          _Option(
            selected: draft.difficulty == d,
            onTap: () => wizard.chooseDifficulty(d),
            child: _DifficultyText(d),
          ),
          const SizedBox(height: AppSpace.x3),
        ],
        if (draft.difficulty == Difficulty.surMesure) _CustomFields(draft),
        if (settings != null &&
            (settings.fixedFee.isPositive || !settings.fractionalShares)) ...[
          LessonCard(
            label: l10n.companion_kicker,
            children: [Text(l10n.wizard_small_budget, style: AppText.body)],
          ),
          const SizedBox(height: AppSpace.x4),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.x4,
              AppSpace.x1,
              AppSpace.x4,
              AppSpace.x3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    Text(
                      l10n.wizard_cushion_amount(_euros(formats, kept.amount)),
                    ),
                    if (kept.capped)
                      Text(
                        l10n.wizard_cushion_capped(_euros(formats, ceiling!)),
                        style: AppText.caption.copyWith(color: AppColors.muted),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A difficulty: its name and meter, its tagline, its settings as chips.
class _DifficultyText extends StatelessWidget {
  const _DifficultyText(this.difficulty);

  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (level, tagline) = switch (difficulty) {
      Difficulty.decouverte => (1, l10n.wizard_tagline_decouverte),
      Difficulty.realiste => (2, l10n.wizard_tagline_realiste),
      Difficulty.serre => (3, l10n.wizard_tagline_serre),
      Difficulty.surMesure => (null, l10n.wizard_tagline_sur_mesure),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _difficultyName(l10n, difficulty),
                style: AppText.titleSmall,
              ),
            ),
            if (level != null) _Meter(level),
          ],
        ),
        const SizedBox(height: AppSpace.x1),
        Text(tagline, style: AppText.body),
        if (difficulty != Difficulty.surMesure) ...[
          const SizedBox(height: AppSpace.x2),
          Wrap(
            spacing: AppSpace.x2,
            runSpacing: AppSpace.x2,
            children: [
              for (final fact in _facts(
                l10n,
                _formats(context),
                presetSettings(difficulty),
              ))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.x3,
                    vertical: AppSpace.x1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.page,
                    borderRadius: BorderRadius.circular(AppSpace.x3),
                  ),
                  child: Text(fact, style: AppText.caption),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Three rising bars, [level] of them filled; screen readers hear it.
class _Meter extends StatelessWidget {
  const _Meter(this.level);

  final int level;

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.of(context).wizard_level(level),
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 10,
            height: 8.0 + 5 * i,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: i < level ? AppColors.ink : AppColors.surface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.ink, width: 2),
            ),
          ),
      ],
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
    final muted = AppText.caption.copyWith(color: AppColors.muted);
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
    final moment = switch (draft.preset) {
      final p? when p.historic => presetTitle(l10n, p),
      _ => null,
    };
    final name = _difficultyName(l10n, draft.difficulty!);
    final cash = _euros(formats, settings.startingCash);

    // A label, its value in bold, and « Modifier » back to its [step].
    Widget row(String label, String value, {int? step}) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: muted)),
          const SizedBox(width: AppSpace.x3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.x2),
              child: Text(value, style: AppText.bodyStrong),
            ),
          ),
          if (step != null)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2),
              ),
              onPressed: () => wizard.edit(step),
              child: Text(l10n.wizard_edit),
            ),
        ],
      ),
    );
    final rows = [
      row(
        l10n.wizard_recap_start,
        moment == null
            ? formats.date(start)
            : l10n.wizard_start_moment(formats.date(start), moment),
        step: 1,
      ),
      row(
        l10n.wizard_recap_budget,
        settings.monthlyContribution.isPositive
            ? l10n.wizard_budget_monthly(
                name,
                cash,
                _euros(formats, settings.monthlyContribution),
              )
            : l10n.wizard_budget(name, cash),
        step: 2,
      ),
      row(l10n.wizard_recap_fees, _fees(l10n, formats, settings)),
      row(
        l10n.wizard_recap_shares,
        settings.fractionalShares ? l10n.wizard_fractional : l10n.wizard_whole,
      ),
      row(
        l10n.wizard_recap_cushion,
        kept == null
            ? l10n.wizard_recap_none
            : l10n.wizard_cushion_amount(_euros(formats, kept.amount)),
        step: 2,
      ),
      row(l10n.wizard_recap_end, l10n.wizard_end_any),
    ];

    return _Page(
      title: l10n.wizard_recap,
      onBack: wizard.back,
      nextFlex: 2,
      next: ChunkyButton(
        label: l10n.wizard_go(formats.date(start)),
        onPressed: nameValid && !_creating ? _create : null,
      ),
      children: [
        ChunkyCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x4,
            vertical: AppSpace.x1,
          ),
          child: Column(
            children: [
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1),
                r,
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.x6),
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
        TitledSection(
          title: l10n.wizard_stops,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x4,
                AppSpace.x3,
                AppSpace.x4,
                AppSpace.x1,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.wizard_stops_hint, style: AppText.label),
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
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.x4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: Icon(Icons.schedule, size: 18, color: AppColors.muted),
            ),
            const SizedBox(width: AppSpace.x2),
            Expanded(child: Text(l10n.wizard_known_only, style: muted)),
          ],
        ),
      ],
    );
  }
}
