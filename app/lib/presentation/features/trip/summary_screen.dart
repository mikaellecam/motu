import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/trip/trip_summary.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../domain/wallet/stop_decision.dart';
import '../../widgets/sign_color.dart';
import '../glossary/term_sheet.dart';

/// The end of a trip (BRIEF §4.5): its time-weighted return against the
/// same money elsewhere, the journal replayed with what happened next, and
/// the glossary terms met.
class TripSummaryScreen extends ConsumerWidget {
  const TripSummaryScreen({super.key, required this.walletId});

  final String walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final formats = Formats(language);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final state = ref.watch(tripSummaryProvider(walletId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.summary_title)),
      body: switch (state.value) {
        null when state.hasError => Center(
          child: ErrorView(
            failure: state.error is Failure
                ? state.error! as Failure
                : const ServerFailure(),
            onRetry: () => ref.invalidate(tripSummaryProvider(walletId)),
          ),
        ),
        null => const Padding(
          padding: EdgeInsets.all(AppSpace.screenPadding),
          child: AsyncSkeleton(lines: 6),
        ),
        final s => ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            Text(s.name, style: AppText.title),
            Text(
              l10n.summary_period(formats.date(s.start), formats.date(s.end)),
              style: muted,
            ),
            Text(
              l10n.summary_money_in(formats.money(s.moneyIn)),
              style: text.bodyMedium,
            ),
            const SizedBox(height: AppSpace.x4),
            _Section(
              title: l10n.summary_compare_title,
              children: [
                Text(l10n.summary_compare_note, style: muted),
                for (final row in s.outcomes) ...[
                  const Divider(height: AppSpace.x4),
                  _OutcomeTile(row, livretCapped: s.livretCapped),
                ],
              ],
            ),
            const SizedBox(height: AppSpace.x4),
            _Section(
              title: l10n.summary_journal_title,
              children: [
                if (s.journal.isEmpty)
                  Text(l10n.summary_journal_empty, style: text.bodyMedium),
                for (final (i, line) in s.journal.indexed) ...[
                  if (i > 0) const Divider(height: AppSpace.x4),
                  _ReplayTile(line),
                ],
              ],
            ),
            if (s.terms.isNotEmpty) ...[
              const SizedBox(height: AppSpace.x4),
              _Section(
                title: l10n.summary_terms_title,
                children: [
                  Wrap(
                    spacing: AppSpace.x2,
                    runSpacing: AppSpace.x2,
                    children: [
                      for (final term in s.terms)
                        ActionChip(
                          label: Text(term.title.of(language)),
                          onPressed: () => showTermSheet(context, term.id),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.titleSmall),
          const SizedBox(height: AppSpace.x2),
          ...children,
        ],
      ),
    ),
  );
}

/// One outcome: what it is, where the money ended, and its time-weighted
/// return (signed, colored to match).
class _OutcomeTile extends StatelessWidget {
  const _OutcomeTile(this.row, {required this.livretCapped});
  final OutcomeRow row;
  final bool livretCapped;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final (label, detail) = switch (row.outcome) {
      Outcome.you => (l10n.summary_you, null),
      Outcome.world => (l10n.summary_world, l10n.summary_world_detail),
      Outcome.livret => (
        l10n.summary_livret,
        livretCapped ? l10n.summary_livret_capped : l10n.summary_livret_detail,
      ),
      Outcome.worst => (
        l10n.summary_worst,
        l10n.summary_worst_detail(formats.date(row.date!)),
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.bodyStrong),
              if (detail != null)
                Text(
                  detail,
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpace.x3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formats.amount(row.value, Currency.eur),
              style: AppText.figure.copyWith(color: AppColors.ink),
            ),
            Text(
              formats.percent(row.twr, signed: true),
              style: text.bodyMedium?.copyWith(
                color: signColor(row.twr, ratio: true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A journal entry: the day, what the user did and why, then what happened.
class _ReplayTile extends StatelessWidget {
  const _ReplayTile(this.line);
  final ReplayLine line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final entry = line.entry;
    final filled = line.sold.isEmpty ? 'other' : 'yes';
    final assets = line.sold.join(', ');
    final decision = StopDecision.values
        .where((d) => d.id == entry.decision)
        .firstOrNull;
    final sentence = switch (decision) {
      StopDecision.hold => l10n.replay_hold,
      StopDecision.sellHalf => l10n.replay_sell_half(filled, assets),
      StopDecision.sellAll => l10n.replay_sell_all(filled, assets),
      StopDecision.carryOn => l10n.replay_continue,
      null => null,
    };
    final moved = switch (line.moved) {
      null => null,
      final change when entry.isSell => (
        l10n.replay_sold_moved(formats.percent(change, signed: true)),
        change,
      ),
      final change => (
        l10n.replay_hold_moved(formats.percent(change, signed: true)),
        change,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.wallets_trip_date(formats.date(entry.date)),
          style: text.bodySmall?.copyWith(color: AppColors.muted),
        ),
        if (sentence != null) Text(sentence, style: text.bodyLarge),
        if (entry.reason case final reason?)
          Text(
            l10n.replay_reason(reason),
            style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
          ),
        if (moved case (final sentence, final change))
          Text(
            sentence,
            style: text.bodyMedium?.copyWith(
              color: signColor(change, ratio: true),
            ),
          ),
      ],
    );
  }
}
