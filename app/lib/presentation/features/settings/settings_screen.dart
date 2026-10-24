import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/settings/settings.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../widgets/section_title.dart';

/// Settings (BRIEF §4.14): language, level, the questionnaire, the data
/// cache, the simulation, the live wallet's reset, and what the app is.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(settingsViewProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings_title)),
      body: switch (view) {
        AsyncValue(:final value?) => _Settings(value),
        AsyncValue(:final error?) => Center(
          child: ErrorView(
            failure: error is Failure ? error : const StorageFailure(),
            onRetry: () => ref.invalidate(settingsViewProvider),
          ),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(AppSpace.screenPadding),
          child: AsyncSkeleton(lines: 8),
        ),
      },
    );
  }
}

class _Settings extends ConsumerWidget {
  const _Settings(this.v);
  final SettingsView v;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final actions = ref.read(settingsControllerProvider.notifier);
    void tell(String message) =>
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));

    final last = v.cache.lastFetch?.toLocal();
    final megabytes =
        (Decimal.fromInt(v.cache.bytes) / Decimal.fromInt(1024 * 1024))
            .toDecimal(scaleOnInfinitePrecision: 2);
    String euros(Money m) => formats.amount(m.amount, m.currency, decimals: 0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenPadding,
        0,
        AppSpace.screenPadding,
        AppSpace.screenPadding,
      ),
      children: [
        SectionTitle(top: AppSpace.x6, l10n.settings_language),
        _Group([
          _Choice<String>(
            label: l10n.settings_language_choice,
            value: v.settings.language ?? 'device',
            choices: [
              ('device', l10n.settings_language_device),
              ('fr', l10n.settings_language_fr),
              ('en', l10n.settings_language_en),
            ],
            onChosen: (s) => actions.setLanguage(s == 'device' ? null : s),
          ),
        ]),

        SectionTitle(top: AppSpace.x6, l10n.settings_level),
        _Group([
          Padding(
            padding: _padding,
            child: Text(
              l10n.settings_level_value(v.level),
              style: AppText.bodyStrong,
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
            title: Text(l10n.settings_show_all),
            subtitle: Text(l10n.settings_show_all_note),
            value: v.settings.showAll,
            onChanged: actions.setShowAll,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
            title: Text(l10n.settings_retake),
            subtitle: Text(l10n.settings_retake_note),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/onboarding'),
          ),
        ]),

        SectionTitle(top: AppSpace.x6, l10n.settings_data),
        _Group([
          Padding(
            padding: _padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  last == null
                      ? l10n.settings_never_updated
                      : l10n.settings_last_update(
                          formats.date(last),
                          formats.time(last),
                        ),
                  style: text.bodyMedium,
                ),
                Text(
                  l10n.settings_cache(
                    v.cache.histories,
                    formats.number(
                      Decimal.fromInt(v.cache.closes),
                      decimals: 0,
                    ),
                    l10n.settings_size_mb(
                      formats.number(megabytes, decimals: 1),
                    ),
                  ),
                  style: muted,
                ),
              ],
            ),
          ),
          Padding(
            padding: _padding,
            // Stacked: « Actualiser maintenant » does not fit half a card.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    await actions.refreshNow();
                    tell(l10n.settings_refreshed);
                  },
                  label: Text(l10n.settings_refresh),
                ),
                const SizedBox(height: AppSpace.x2),
                OutlinedButton(
                  onPressed: () async {
                    await actions.clearCache();
                    tell(l10n.settings_cleared);
                  },
                  child: Text(l10n.settings_clear),
                ),
              ],
            ),
          ),
        ]),

        SectionTitle(top: AppSpace.x6, l10n.settings_simulation),
        _Group([
          _Choice<Money>(
            label: l10n.settings_capital,
            note: l10n.settings_capital_note,
            value: v.startingCash,
            choices: [
              for (final amount in startingCashChoices) (amount, euros(amount)),
            ],
            onChosen: actions.setStartingCash,
          ),
          _Choice<Decimal>(
            label: l10n.settings_fx_fee,
            note: l10n.settings_fx_fee_note,
            value: v.fxFee,
            choices: [
              for (final rate in fxFeeChoices) (rate, formats.percent(rate)),
            ],
            onChosen: actions.setFxFee,
          ),
        ]),
        const SizedBox(height: AppSpace.x4),
        // The one setting that loses something: an alert border, a warning
        // icon and its own words, never colour alone.
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.alertText,
            side: const BorderSide(color: AppColors.alertText, width: 1.5),
          ),
          icon: const Icon(Icons.warning_amber_rounded),
          onPressed: () => _reset(context, ref, formats.money(v.startingCash)),
          label: Text(l10n.settings_reset),
        ),
        const SizedBox(height: AppSpace.x2),
        Text(l10n.settings_reset_note(euros(v.startingCash)), style: muted),

        SectionTitle(top: AppSpace.x6, l10n.settings_about),
        _Group([
          Padding(
            padding: _padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, line) in [
                  l10n.settings_about_money,
                  l10n.settings_about_advice,
                  l10n.settings_about_sources,
                ].indexed) ...[
                  if (i > 0) const SizedBox(height: AppSpace.x2),
                  Text(line, style: text.bodyMedium),
                ],
              ],
            ),
          ),
        ]),
      ],
    );
  }

  /// « Réinitialiser le portefeuille live », once confirmed.
  Future<void> _reset(
    BuildContext context,
    WidgetRef ref,
    String capital,
  ) async {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settings_reset_title),
        content: Text(l10n.settings_reset_body(capital)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(material.cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.alertText),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.settings_reset_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(settingsControllerProvider.notifier).resetLiveWallet();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.settings_reset_done)));
  }
}

/// A flat card of rows, a line between each (money family, §10.1).
class _Group extends StatelessWidget {
  const _Group(this.rows);
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const Divider(height: 1),
          row,
        ],
      ],
    ),
  );
}

/// Inside a card: a line of text, as wide as a row.
const _padding = EdgeInsets.symmetric(
  horizontal: AppSpace.x4,
  vertical: AppSpace.x3,
);

/// One setting: its name, the value it has (and what it does) under it;
/// tapped, the values to pick from. Fits any text size.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.choices,
    required this.onChosen,
    this.note,
  });

  final String label;
  final T value;
  final List<(T, String)> choices;
  final ValueChanged<T> onChosen;
  final String? note;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(label),
        children: [
          RadioGroup<T>(
            groupValue: value,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (v, text) in choices)
                  RadioListTile<T>(value: v, title: Text(text)),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null && picked != value) onChosen(picked);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shown = choices.firstWhere((c) => c.$1 == value).$2;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(shown, style: AppText.bodyStrong.copyWith(color: AppColors.ink)),
          if (note case final note?)
            Text(note, style: text.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ),
      trailing: const Icon(Icons.unfold_more),
      onTap: () => _pick(context),
    );
  }
}
