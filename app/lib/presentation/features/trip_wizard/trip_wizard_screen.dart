import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/trip/trip_wizard.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/wallet/trip_start.dart';

/// The trip wizard (BRIEF §4.5), chunky « world » style. Step 1, the start
/// date; steps 2 and 3 come with M5-2.
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
        _ => const SizedBox.shrink(),
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
    final (title, teaser) = switch (option.preset) {
      TripPreset.dotcom => (
        l10n.wizard_preset_dotcom,
        l10n.wizard_teaser_dotcom,
      ),
      TripPreset.lehman => (
        l10n.wizard_preset_lehman,
        l10n.wizard_teaser_lehman,
      ),
      TripPreset.covid => (l10n.wizard_preset_covid, l10n.wizard_teaser_covid),
      TripPreset.inflation => (
        l10n.wizard_preset_inflation,
        l10n.wizard_teaser_inflation,
      ),
      final p => (l10n.wizard_years_ago(p.years!), null),
    };

    return Semantics(
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
