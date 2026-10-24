import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/trip/trip_stop.dart';
import '../../../application/wallet/wallet_providers.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/wallet/stop_decision.dart';
import '../../../domain/wallet/trip_engine.dart';
import '../../widgets/chart_axis.dart';
import '../glossary/term_sheet.dart';
import 'trip_header.dart';
import 'trip_sheets.dart';

/// The glossary's word for a fall from a high (§4.4).
const _dropTerm = 'pire-baisse';

/// The automatic stop (BRIEF §4.5), as the art direction's « automatic
/// stop » draws it: the trip's header, then the event in one chunky card
/// (what happened, the fall against its threshold, the market meanwhile),
/// and the user's answer with its reason, kept in the journal (§4.13).
class StopScreen extends ConsumerStatefulWidget {
  const StopScreen({super.key, required this.walletId});

  final String walletId;

  @override
  ConsumerState<StopScreen> createState() => _StopScreenState();
}

class _StopScreenState extends ConsumerState<StopScreen> {
  final _why = TextEditingController();
  StopDecision? _choice;

  @override
  void dispose() {
    _why.dispose();
    super.dispose();
  }

  Future<void> _decide(StopDecision decision) async {
    final actions = ref.read(stopActionsProvider(widget.walletId).notifier);
    await actions.decide(decision, reason: _why.text);
    if (!mounted) return;
    final failure = ref.read(stopActionsProvider(widget.walletId)).error;
    if (failure is Failure) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure))));
      return;
    }
    context.go('/wallet/${widget.walletId}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final state = ref.watch(tripStopProvider(widget.walletId));
    final view = state.value;
    final busy = ref.watch(stopActionsProvider(widget.walletId)).isLoading;

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TripHeader(
                name: view?.name,
                date: view?.date,
                chip: l10n.stop_title,
                // An automatic stop: the alert colour (§10.2).
                chipColor: AppColors.alert,
              ),
              Expanded(
                child: switch (view) {
                  null when state.hasError => Center(
                    child: ErrorView(
                      failure: state.error is Failure
                          ? state.error! as Failure
                          : const ServerFailure(),
                      onRetry: () =>
                          ref.invalidate(tripStopProvider(widget.walletId)),
                    ),
                  ),
                  null => const Padding(
                    padding: EdgeInsets.all(AppSpace.screenPadding),
                    child: AsyncSkeleton(lines: 5),
                  ),
                  final v => ListView(
                    padding: const EdgeInsets.all(AppSpace.screenPadding),
                    children: [
                      _EventCard(v),
                      const SizedBox(height: AppSpace.x6),
                      if (v.dropStop) ...[
                        Text(l10n.stop_question, style: AppText.title),
                        const SizedBox(height: AppSpace.x3),
                        for (final (decision, title, up, down) in [
                          (
                            StopDecision.hold,
                            l10n.stop_hold,
                            l10n.stop_hold_up,
                            l10n.stop_hold_down,
                          ),
                          (
                            StopDecision.sellHalf,
                            l10n.stop_sell_half,
                            l10n.stop_sell_half_up,
                            l10n.stop_sell_half_down,
                          ),
                          (
                            StopDecision.sellAll,
                            l10n.stop_sell_all,
                            l10n.stop_sell_all_up,
                            l10n.stop_sell_all_down,
                          ),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.x3),
                            child: ChunkyChoice(
                              label: title,
                              labelStyle: AppText.titleSmall,
                              upside: up,
                              downside: down,
                              selected: _choice == decision,
                              onTap: () => setState(() => _choice = decision),
                            ),
                          ),
                        Text(l10n.stop_sells_next, style: muted),
                        const SizedBox(height: AppSpace.x4),
                      ],
                      // The label above the field; screen readers hear it
                      // as the field's.
                      ExcludeSemantics(
                        child: Text(l10n.stop_why, style: AppText.label),
                      ),
                      const SizedBox(height: AppSpace.x2),
                      Semantics(
                        label: l10n.stop_why,
                        child: TextField(
                          controller: _why,
                          maxLines: 3,
                          minLines: 2,
                          decoration: InputDecoration(
                            hintText: v.dropStop ? l10n.stop_why_example : null,
                            filled: true,
                            fillColor: AppColors.surface,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.x2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ExcludeSemantics(
                            child: Icon(
                              Icons.menu_book_outlined,
                              size: AppSpace.x4,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(width: AppSpace.x2),
                          Expanded(
                            child: Text(l10n.stop_journal_hint, style: muted),
                          ),
                        ],
                      ),
                      if (v.dropStop) ...[
                        const SizedBox(height: AppSpace.x2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              l10n.stop_before_choosing,
                              style: text.bodyMedium,
                            ),
                            TextButton(
                              onPressed: () =>
                                  showTermSheet(context, _dropTerm),
                              child: Text(l10n.stop_term_link),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpace.x4),
                      ChunkyButton(
                        label: v.dropStop
                            ? l10n.stop_confirm
                            : l10n.stop_continue,
                        onPressed: busy || (v.dropStop && _choice == null)
                            ? null
                            : () => _decide(_choice ?? StopDecision.carryOn),
                      ),
                      const SizedBox(height: AppSpace.x2),
                      Center(
                        child: TextButton(
                          onPressed: () async {
                            final o = await ref.read(
                              walletOverviewProvider(widget.walletId).future,
                            );
                            if (!context.mounted) return;
                            await showStopsSheet(
                              context,
                              walletId: widget.walletId,
                              current: o.stops,
                              contribution: o.monthlyContribution,
                            );
                          },
                          child: Text(l10n.stop_edit_stops),
                        ),
                      ),
                    ],
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The event in one chunky card: « Arrêt automatique », what happened as a
/// headline (the other reasons, if any, under it), and for a drop its chart
/// and what the market did meanwhile.
class _EventCard extends StatelessWidget {
  const _EventCard(this.v);
  final StopView v;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.stop_title,
            style: AppText.label.copyWith(color: AppColors.alertText),
          ),
          for (final (i, reason) in v.reasons.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? AppSpace.x1 : AppSpace.x2),
              child: Text(
                _sentence(l10n, formats, reason, v),
                style: i == 0 ? AppText.title : AppText.bodyStrong,
              ),
            ),
          if (v.chart case final chart? when chart.values.length >= 2) ...[
            const SizedBox(height: AppSpace.x4),
            _StopChart(chart),
            const SizedBox(height: AppSpace.x3),
            Text(
              [
                if (chart.market case final market?)
                  l10n.stop_market(formats.percent(market, signed: true)),
                l10n.stop_cash(formats.money(v.cash)),
              ].join(' '),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

String _sentence(
  AppLocalizations l10n,
  Formats formats,
  StopReason reason,
  StopView v,
) => switch (reason) {
  // Always set with a portfolio drop: money was put in.
  DrawdownStop() => l10n.stop_drawdown(
    formats.percent(v.portfolioLoss ?? Decimal.zero, signed: true),
  ),
  PositionLossStop(:final assetId, :final loss) => l10n.stop_position(
    v.assetNames[assetId] ?? assetId,
    formats.percent(loss, signed: true),
  ),
  OrderFilledStop(:final orderId) => l10n.stop_order(
    v.assetNames[orderId] ?? orderId,
  ),
  ContributionStop(:final amount) => l10n.stop_contribution(
    formats.money(amount),
  ),
};

/// What fell, filled lightly under its line and ending on a dot in the alert
/// colour, against its dashed threshold labelled « Ton seuil : −15 % », over
/// dated days.
class _StopChart extends StatelessWidget {
  const _StopChart(this.chart);
  final StopChart chart;

  static const _height = 160.0;

  /// The date axis under the plot (`dateAxis`).
  static const _axis = 24.0;

  /// The share of the plot kept under the threshold's start for its label.
  static const _labelRoom = 0.3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    // Doubles from here on: pixels, not money.
    final values = [for (final v in chart.values) v.toDouble()];
    final line = [for (final t in chart.threshold) t.toDouble()];
    final all = [...values, ...line];
    final low = all.reduce(math.min);
    final high = all.reduce(math.max);
    final margin = (high - low) * 0.1 + 1;
    final maxY = high + margin;
    final minY = math.min(
      low - margin,
      (line.first - _labelRoom * maxY) / (1 - _labelRoom),
    );
    final lineTop =
        (maxY - line.first) / (maxY - minY) * (_height - _axis) + AppSpace.x1;

    return Semantics(
      label: l10n.stop_chart_semantics(
        formats.amount(chart.values.first, Currency.eur),
        formats.amount(chart.values.last, Currency.eur),
        formats.amount(chart.threshold.last, Currency.eur),
      ),
      excludeSemantics: true,
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            Positioned.fill(
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: const FlGridData(show: false),
                  titlesData: dateAxis(
                    chart.dates,
                    formats,
                    style: AppText.caption.copyWith(color: AppColors.muted),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < line.length; i++)
                          FlSpot(i.toDouble(), line[i]),
                      ],
                      color: AppColors.alert,
                      barWidth: 1.5,
                      dashArray: const [6, 4],
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < values.length; i++)
                          FlSpot(i.toDouble(), values[i]),
                      ],
                      color: AppColors.primary,
                      barWidth: 2.5,
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                      // Where the fall stands now, past the threshold.
                      dotData: FlDotData(
                        checkToShowDot: (spot, _) =>
                            spot.x == values.length - 1,
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 5,
                          color: AppColors.alert,
                          strokeColor: AppColors.surface,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: lineTop,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpace.x2),
                  border: Border.all(color: AppColors.alert, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.x2,
                    vertical: 2,
                  ),
                  child: Text(
                    l10n.stop_threshold(
                      formats.percent(-chart.limit, signed: true, decimals: 0),
                    ),
                    style: AppText.label,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
