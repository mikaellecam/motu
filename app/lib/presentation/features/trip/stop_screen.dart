import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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
import 'trip_sheets.dart';

/// The automatic stop (BRIEF §4.5): why the trip stopped, the fall against
/// its stop line, and the user's answer, kept in the journal (§4.13).
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
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(tripStopProvider(widget.walletId));
    final view = state.value;
    final busy = ref.watch(stopActionsProvider(widget.walletId)).isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.stop_title)),
      body: switch (view) {
        null when state.hasError => Center(
          child: ErrorView(
            failure: state.error is Failure
                ? state.error! as Failure
                : const ServerFailure(),
            onRetry: () => ref.invalidate(tripStopProvider(widget.walletId)),
          ),
        ),
        null => const Padding(
          padding: EdgeInsets.all(AppSpace.screenPadding),
          child: AsyncSkeleton(lines: 5),
        ),
        final v => ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            Text(
              l10n.wallets_trip_date(formats.date(v.date)),
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpace.x2),
            for (final reason in v.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.x2),
                child: Text(
                  _sentence(l10n, formats, reason, v.assetNames),
                  style: text.titleMedium,
                ),
              ),
            if (v.chart case final chart?) ...[
              const SizedBox(height: AppSpace.x2),
              _StopChartCard(chart),
            ],
            const SizedBox(height: AppSpace.x4),
            if (v.dropStop) ...[
              Text(l10n.stop_question, style: AppText.title),
              const SizedBox(height: AppSpace.x2),
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
                  child: _ChoiceCard(
                    title: title,
                    up: up,
                    down: down,
                    selected: _choice == decision,
                    onTap: () => setState(() => _choice = decision),
                  ),
                ),
              Text(
                l10n.stop_sells_next,
                style: text.bodySmall?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpace.x4),
            ],
            TextField(
              controller: _why,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                labelText: l10n.stop_why,
                filled: true,
                fillColor: AppColors.surface,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpace.x4),
            ChunkyButton(
              label: v.dropStop ? l10n.stop_confirm : l10n.stop_continue,
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
    );
  }
}

String _sentence(
  AppLocalizations l10n,
  Formats formats,
  StopReason reason,
  Map<String, String> names,
) => switch (reason) {
  DrawdownStop(:final value, :final threshold) => l10n.stop_drawdown(
    formats.money(value),
    formats.money(threshold),
  ),
  PositionLossStop(:final assetId, :final loss) => l10n.stop_position(
    names[assetId] ?? assetId,
    formats.percent(loss, signed: true),
  ),
  OrderFilledStop(:final orderId) => l10n.stop_order(names[orderId] ?? orderId),
  ContributionStop(:final amount) => l10n.stop_contribution(
    formats.money(amount),
  ),
};

/// One answer, with what it gains and what it risks.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.up,
    required this.down,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String up;
  final String down;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget line(IconData icon, String label) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: AppSpace.x4, color: AppColors.muted),
        ),
        const SizedBox(width: AppSpace.x2),
        Expanded(child: Text(label, style: text.bodyMedium)),
      ],
    );
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
                    const SizedBox(height: AppSpace.x1),
                    line(Icons.add, up),
                    line(Icons.remove, down),
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

class _StopChartCard extends StatelessWidget {
  const _StopChartCard(this.chart);
  final StopChart chart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (chart.values.length < 2) return const SizedBox.shrink();
    // Doubles from here on: pixels, not money.
    final values = [for (final v in chart.values) v.toDouble()];
    final line = [for (final t in chart.threshold) t.toDouble()];
    final all = [...values, ...line];
    final low = all.reduce((a, b) => a < b ? a : b);
    final high = all.reduce((a, b) => a > b ? a : b);
    final margin = (high - low) * 0.1 + 1;
    final formats = Formats(Localizations.localeOf(context).languageCode);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 160,
              child: Semantics(
                label: l10n.stop_chart_semantics(
                  formats.amount(chart.values.first, Currency.eur),
                  formats.amount(chart.values.last, Currency.eur),
                  formats.amount(chart.threshold.last, Currency.eur),
                ),
                excludeSemantics: true,
                child: LineChart(
                  LineChartData(
                    minY: low - margin,
                    maxY: high + margin,
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
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
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.x2),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 5,
                    height: 2,
                    margin: const EdgeInsets.only(right: 2),
                    color: AppColors.alert,
                  ),
                const SizedBox(width: AppSpace.x1),
                Text(
                  l10n.stop_line,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
