import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/learning/content.dart';
import '../../../application/learning/island_path.dart';
import '../../../application/trip/trip_summary.dart';
import '../../../application/wallet/living_island.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/wallet/stop_decision.dart';
import '../../widgets/sign_color.dart';
import '../glossary/term_sheet.dart';
import '../map/archipelago.dart';
import '../map/living_island.dart';

/// The end of a trip (BRIEF §4.5), on the sea as the art direction's « end
/// of trip » draws it: the island with the city the trip built, its
/// time-weighted return against the same money elsewhere as bars round
/// zero, the journal replayed with what happened next and the glossary terms
/// met, then « Rejouer avec une autre difficulté » or back to the wallets.
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
    // The trip's own city, on the island the lessons greened.
    final buildings = drawnBuildings(
      ref.watch(walletIslandProvider(walletId)).value ?? const [],
    );
    final lessons = ref.watch(islandPathProvider(actionsEtfIsland)).value;
    final back = ChunkyIconButton(
      icon: Icons.chevron_left,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () => Navigator.maybePop(context),
    );

    return Scaffold(
      // World screens sit on the sea (BRIEF §10.2).
      backgroundColor: AppColors.sea,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SafeArea(
          bottom: false,
          child: switch (state.value) {
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
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screenPadding,
                0,
                AppSpace.screenPadding,
                AppSpace.screenPadding,
              ),
              children: [
                SizedBox(
                  height: 230,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: ArchipelagoPainter(
                            buildings: buildings,
                            only: archipelago.firstWhere(
                              (i) => i.id == IslandId.actionsEtf,
                            ),
                            grown: switch (lessons) {
                              final path? when path.nodes.isNotEmpty =>
                                path.done / path.nodes.length,
                              _ => 1,
                            },
                          ),
                        ),
                      ),
                      Positioned(left: 0, top: AppSpace.x3, child: back),
                    ],
                  ),
                ),
                ChunkyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.summary_end_label(s.name),
                        style: AppText.label.copyWith(color: AppColors.primary),
                      ),
                      const SizedBox(height: AppSpace.x1),
                      Text(
                        l10n.summary_period(
                          formats.date(s.start),
                          formats.date(s.end),
                        ),
                        style: AppText.title,
                      ),
                      const SizedBox(height: AppSpace.x1),
                      Text(
                        l10n.summary_money_in(formats.money(s.moneyIn)),
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: AppSpace.x2),
                      for (final row in s.outcomes)
                        _OutcomeTile(
                          row,
                          livretCapped: s.livretCapped,
                          // Every bar on one scale: the widest return.
                          scale: s.outcomes
                              .map((o) => o.twr.abs())
                              .reduce((a, b) => a > b ? a : b),
                        ),
                      const SizedBox(height: AppSpace.x2),
                      Text(l10n.summary_compare_note, style: muted),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.x4),
                ChunkyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const ExcludeSemantics(
                            child: Icon(
                              Icons.menu_book_outlined,
                              size: AppSpace.x4 + AppSpace.x1,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpace.x2),
                          Text(
                            l10n.summary_journal_title,
                            style: AppText.label.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.x2),
                      if (s.journal.isEmpty)
                        Text(
                          l10n.summary_journal_empty,
                          style: text.bodyMedium,
                        ),
                      for (final (i, line) in s.journal.indexed) ...[
                        if (i > 0) const Divider(height: AppSpace.x4),
                        _ReplayTile(line),
                      ],
                      if (s.terms.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.x4),
                        Text(
                          l10n.summary_terms_title,
                          style: AppText.label.copyWith(color: AppColors.ink),
                        ),
                        const SizedBox(height: AppSpace.x2),
                        Wrap(
                          spacing: AppSpace.x2,
                          runSpacing: AppSpace.x2,
                          children: [
                            for (final term in s.terms)
                              ChunkyChip(
                                label: term.title.of(language),
                                onTap: () => showTermSheet(context, term.id),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.x6),
                ChunkyButton(
                  label: l10n.summary_replay,
                  // The same start, a difficulty to choose (the wizard's
                  // second step).
                  onPressed: () => context.push(
                    Uri(
                      path: '/wallets/new',
                      queryParameters: {
                        'step': '2',
                        'date': s.start.toIso8601String().substring(0, 10),
                      },
                    ).toString(),
                  ),
                ),
                const SizedBox(height: AppSpace.x3),
                ChunkyButton(
                  label: l10n.summary_back_wallets,
                  kind: ChunkyButtonKind.secondary,
                  onPressed: () => context.go('/wallets'),
                ),
              ],
            ),
          },
        ),
      ),
    );
  }
}

/// One outcome: what it is, its time-weighted return (signed, colored to
/// match) and where the money ended, over a bar from zero, every bar on the
/// same [scale] (the widest return).
class _OutcomeTile extends StatelessWidget {
  const _OutcomeTile(
    this.row, {
    required this.livretCapped,
    required this.scale,
  });
  final OutcomeRow row;
  final bool livretCapped;
  final Decimal scale;

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
    final color = signColor(row.twr, ratio: true);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                    formats.percent(row.twr, signed: true),
                    style: AppText.bodyStrong.copyWith(color: color),
                  ),
                  Text(
                    formats.amount(row.value, Currency.eur),
                    style: AppText.figure.copyWith(color: AppColors.ink),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpace.x1),
          // The figures above say it all: the bar is for the eye.
          ExcludeSemantics(
            child: _Bar(
              share: scale == Decimal.zero
                  ? 0
                  : (row.twr / scale).toDouble().clamp(-1.0, 1.0),
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A return as a bar from the middle line: right for a gain, left for a
/// loss, [share] (−1 to 1) of half the track.
class _Bar extends StatelessWidget {
  const _Bar({required this.share, required this.color});
  final double share;
  final Color color;

  static const _height = 14.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _height,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final half = constraints.maxWidth / 2;
        final length = half * share.abs();
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(_height / 2),
                ),
              ),
            ),
            if (length > 0)
              Positioned(
                left: share >= 0 ? half : half - length,
                width: length,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppSpace.x1),
                    border: Border.all(color: AppColors.ink, width: 2),
                  ),
                ),
              ),
            Positioned(
              left: half - 1,
              width: 2,
              top: 0,
              bottom: 0,
              child: const ColoredBox(color: AppColors.ink),
            ),
          ],
        );
      },
    ),
  );
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
      // A trip order noted in the journal (M4-5).
      null => switch (entry.decision) {
        'buy' => l10n.replay_order_buy(filled, assets),
        'sell' => l10n.replay_order_sell(filled, assets),
        _ => null,
      },
    };
    final moved = switch (line.moved) {
      null => null,
      final change when entry.isSell || entry.isOrder => (
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
