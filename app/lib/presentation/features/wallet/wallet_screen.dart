import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/trip/trip_runner.dart';
import '../../../application/trip/trip_stop.dart';
import '../../../application/trip/trip_summary.dart';
import '../../../application/wallet/live_catch_up.dart';
import '../../../application/wallet/wallet_overview.dart';
import '../../../application/wallet/wallet_providers.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../domain/market/asset.dart';
import '../../../domain/wallet/valuation.dart';
import '../../../domain/wallet/wallet.dart';
import '../../widgets/asset_avatar.dart';
import '../companion/companion_card.dart';
import '../order/order_screen.dart';
import '../trip/trip_sheets.dart';
import 'livret_card.dart';
import '../../widgets/cache_status_banner.dart';
import '../../widgets/sign_color.dart';

/// A wallet's value, chart, allocation and positions (BRIEF §4.7). Same
/// layout for the live wallet and trips.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key, required this.walletId});

  final String walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(walletOverviewProvider(walletId));
    final overview = state.value;
    // The live wallet first catches up with the sessions that closed.
    Future<void> refresh() async {
      if (overview?.kind == WalletKind.live) {
        await ref.read(liveCatchUpProvider.notifier).run();
      }
      await ref.refresh(walletOverviewProvider(walletId).future).then((_) {});
    }

    final trip = overview?.kind == WalletKind.trip;
    return Scaffold(
      appBar: AppBar(
        leading: trip
            ? IconButton(
                tooltip: l10n.trip_exit,
                icon: const Icon(Icons.close),
                onPressed: () => context.go('/wallets'),
              )
            : null,
        title: overview == null
            ? null
            : Text(
                overview.kind == WalletKind.live
                    ? l10n.wallet_live_name
                    : overview.name,
              ),
      ),
      bottomNavigationBar: trip ? _TimeControls(overview!) : null,
      body: switch (overview) {
        final o? => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.screenPadding),
            children: [
              CacheStatusBanner(onRetry: refresh),
              const SizedBox(height: AppSpace.x2),
              if (o.kind == WalletKind.trip) ...[
                _TripHeader(o),
                const SizedBox(height: AppSpace.x4),
              ],
              _Header(o),
              const SizedBox(height: AppSpace.x4),
              _Tiles(o),
              const SizedBox(height: AppSpace.x4),
              // A finished trip no longer trades.
              if (o.status != WalletStatus.finished) ...[
                FilledButton(
                  onPressed: () => context.go('/explore?wallet=${o.id}'),
                  child: Text(l10n.wallet_invest),
                ),
                const SizedBox(height: AppSpace.x4),
              ],
              WalletCompanionCard(walletId: o.id),
              if (o.pendingOrders.isNotEmpty) ...[
                _PendingCard(o),
                const SizedBox(height: AppSpace.x4),
              ],
              _ChartCard(walletId),
              const SizedBox(height: AppSpace.x4),
              _AllocationCard(o),
              const SizedBox(height: AppSpace.x4),
              _PositionsCard(o),
              const SizedBox(height: AppSpace.x4),
              LivretCard(
                walletId: o.id,
                canMove: o.status != WalletStatus.finished,
              ),
            ],
          ),
        ),
        null when state.hasError => Center(
          child: ErrorView(
            failure: state.error is Failure
                ? state.error! as Failure
                : const ServerFailure(),
            onRetry: () => ref.invalidate(walletOverviewProvider(walletId)),
          ),
        ),
        null => const Padding(
          padding: EdgeInsets.all(AppSpace.screenPadding),
          child: AsyncSkeleton(lines: 6),
        ),
      },
    );
  }
}

Formats _formats(BuildContext context) =>
    Formats(Localizations.localeOf(context).languageCode);

class _Header extends StatelessWidget {
  const _Header(this.o);
  final WalletOverview o;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final ratio = o.changeRatio;
    final change = [
      formats.amount(o.change, Currency.eur, signed: true),
      if (ratio != null) '(${formats.percent(ratio, signed: true)})',
    ].join(' ');
    final pricesAsOf = o.pricesAsOf?.toLocal();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formats.amount(o.total, Currency.eur),
          style: AppText.figureLarge.copyWith(color: AppColors.ink),
        ),
        Text(
          l10n.wallet_change_since_start(change),
          style: text.bodyLarge?.copyWith(color: signColor(o.change)),
        ),
        if (pricesAsOf != null)
          Text(
            l10n.wallet_prices_as_of(
              formats.date(pricesAsOf),
              formats.time(pricesAsOf),
            ),
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
      ],
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles(this.o);
  final WalletOverview o;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Tile(
              l10n.wallet_invested,
              formats.amount(o.invested, Currency.eur),
            ),
          ),
          const SizedBox(width: AppSpace.x3),
          Expanded(
            child: _Tile(
              l10n.wallet_cash_available,
              formats.money(o.availableCash),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.amount);
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpace.x1),
            Text(amount, style: AppText.figure.copyWith(color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends ConsumerStatefulWidget {
  const _ChartCard(this.walletId);
  final String walletId;

  @override
  ConsumerState<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends ConsumerState<_ChartCard> {
  var _period = ChartPeriod.all;
  Benchmark? _benchmark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final chart = ref.watch(
      walletChartProvider(widget.walletId, _period, _benchmark),
    );
    final benchmarkName = switch (_benchmark) {
      Benchmark.world => l10n.wallet_benchmark_world,
      Benchmark.livret => l10n.wallet_benchmark_livret,
      null => null,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<ChartPeriod>(
              showSelectedIcon: false,
              segments: [
                for (final (period, label) in [
                  (ChartPeriod.week, l10n.wallet_period_week),
                  (ChartPeriod.month, l10n.wallet_period_month),
                  (ChartPeriod.quarter, l10n.wallet_period_quarter),
                  (ChartPeriod.year, l10n.wallet_period_year),
                  (ChartPeriod.all, l10n.wallet_period_all),
                ])
                  ButtonSegment(value: period, label: Text(label)),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.single),
            ),
            const SizedBox(height: AppSpace.x4),
            SizedBox(
              height: 180,
              child: switch (chart) {
                AsyncValue(value: final data?) => _Chart(data, _period),
                AsyncValue(error: final error?) => ErrorView(
                  failure: error is Failure ? error : const ServerFailure(),
                  onRetry: () => ref.invalidate(
                    walletChartProvider(widget.walletId, _period, _benchmark),
                  ),
                ),
                _ => const AsyncSkeleton(lines: 3),
              },
            ),
            const SizedBox(height: AppSpace.x2),
            Wrap(
              spacing: AppSpace.x4,
              children: [
                _Legend(
                  l10n.wallet_chart_money_in,
                  color: AppColors.muted,
                  dashed: true,
                ),
                if (benchmarkName != null)
                  _Legend(benchmarkName, color: AppColors.ink),
              ],
            ),
            const SizedBox(height: AppSpace.x2),
            Wrap(
              spacing: AppSpace.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.wallet_compare, style: text.bodyMedium),
                for (final (benchmark, label) in [
                  (Benchmark.world, l10n.wallet_benchmark_world),
                  (Benchmark.livret, l10n.wallet_benchmark_livret),
                ])
                  FilterChip(
                    label: Text(label),
                    selected: _benchmark == benchmark,
                    showCheckmark: false,
                    onSelected: (on) =>
                        setState(() => _benchmark = on ? benchmark : null),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart(this.data, this.period);
  final ChartData data;
  final ChartPeriod period;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    if (data.dates.isEmpty) return const SizedBox.shrink();
    if (data.dates.length < 2) {
      return Center(
        child: Text(
          l10n.wallet_chart_starts(formats.date(data.dates.first)),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.muted),
        ),
      );
    }
    // Doubles from here on: pixels, not money.
    List<FlSpot> spots(List<Decimal> values) => [
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i].toDouble()),
    ];
    final all = [...data.values, ...data.moneyIn, ...?data.benchmark];
    final low = all.reduce((a, b) => a < b ? a : b).toDouble();
    final high = all.reduce((a, b) => a > b ? a : b).toDouble();
    final margin = (high - low) * 0.1 + 1;
    final periodName = switch (period) {
      ChartPeriod.week => l10n.wallet_period_week_long,
      ChartPeriod.month => l10n.wallet_period_month_long,
      ChartPeriod.quarter => l10n.wallet_period_quarter_long,
      ChartPeriod.year => l10n.wallet_period_year_long,
      ChartPeriod.all => l10n.wallet_period_all_long,
    };

    return Semantics(
      label: l10n.wallet_chart_semantics(
        periodName,
        formats.amount(data.values.first, Currency.eur),
        formats.amount(data.values.last, Currency.eur),
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
              spots: spots(data.moneyIn),
              color: AppColors.muted,
              barWidth: 1.5,
              dashArray: const [6, 4],
              dotData: const FlDotData(show: false),
            ),
            if (data.benchmark case final benchmark?)
              LineChartBarData(
                spots: spots(benchmark),
                color: AppColors.ink,
                barWidth: 1.5,
                dotData: const FlDotData(show: false),
              ),
            LineChartBarData(
              spots: spots(data.values),
              color: AppColors.primary,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, {required this.color, this.dashed = false});
  final String label;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < (dashed ? 3 : 1); i++)
            Container(
              width: dashed ? 5 : 16,
              height: 2,
              margin: const EdgeInsets.only(right: 2),
              color: color,
            ),
        ],
      ),
      const SizedBox(width: AppSpace.x1),
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AppColors.muted),
      ),
    ],
  );
}

class _AllocationCard extends StatelessWidget {
  const _AllocationCard(this.o);
  final WalletOverview o;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final names = {for (final p in o.positions) p.asset.id: p.asset.name};
    var rank = 0;
    final slices = [
      for (final line in o.allocation)
        switch (line) {
          PositionLine(:final assetId) => (
            names[assetId]!,
            AppColors.allocationShade(rank++),
            line.weight,
          ),
          CashLine() => (
            l10n.wallet_allocation_cash,
            AppColors.line,
            line.weight,
          ),
          LivretLine() => (
            l10n.wallet_allocation_livret,
            AppColors.muted,
            line.weight,
          ),
        },
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.wallet_allocation_title, style: text.titleMedium),
            const SizedBox(height: AppSpace.x3),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpace.x1),
                child: SizedBox(
                  height: AppSpace.x3,
                  child: Row(
                    children: [
                      for (final (_, color, weight) in slices)
                        if ((weight * Decimal.fromInt(1000))
                                .round()
                                .toBigInt()
                                .toInt()
                            case final flex when flex > 0)
                          Expanded(
                            flex: flex,
                            child: Container(
                              margin: const EdgeInsets.only(right: 2),
                              color: color,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.x3),
            for (final (name, color, weight) in slices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.x1),
                child: Row(
                  children: [
                    Container(
                      width: AppSpace.x3,
                      height: AppSpace.x3,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: AppSpace.x2),
                    Expanded(child: Text(name, style: text.bodyMedium)),
                    Text(formats.percent(weight), style: text.bodyMedium),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// « Ordres en attente » (decided 2026-10-11): each opens its order screen.
class _PendingCard extends StatelessWidget {
  const _PendingCard(this.o);
  final WalletOverview o;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
              child: Text(l10n.wallet_pending_title, style: text.titleMedium),
            ),
            const SizedBox(height: AppSpace.x2),
            for (final (:order, :asset, reserved: _) in o.pendingOrders)
              InkWell(
                onTap: () => context.push('/wallet/${o.id}/order/${order.id}'),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.x3,
                      vertical: AppSpace.x2,
                    ),
                    child: Row(
                      children: [
                        Expanded(child: OrderHeading(order, asset)),
                        const ExcludeSemantics(
                          child: Icon(
                            Icons.chevron_right,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
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

class _PositionsCard extends StatelessWidget {
  const _PositionsCard(this.o);
  final WalletOverview o;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
              child: Text(l10n.wallet_positions_title, style: text.titleMedium),
            ),
            const SizedBox(height: AppSpace.x2),
            if (o.positions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
                child: Text(
                  l10n.wallet_positions_empty,
                  style: text.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ),
            for (final p in o.positions) _PositionRow(p, walletId: o.id),
          ],
        ),
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow(this.p, {required this.walletId});
  final PositionView p;
  final String walletId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final count = p.quantity.toDecimal();
    final quantity = switch (p.asset.type) {
      AssetType.stock => l10n.wallet_quantity_stock(
        formats.countForm(count),
        formats.quantity(p.quantity),
      ),
      AssetType.etf => l10n.wallet_quantity_etf(
        formats.countForm(count),
        formats.quantity(p.quantity),
      ),
    };
    final pnl = p.pnlRatio;

    return InkWell(
      onTap: () => context.push('/asset/${p.asset.id}?wallet=$walletId'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x3,
            vertical: AppSpace.x2,
          ),
          child: Row(
            children: [
              AssetAvatar(p.asset.name),
              const SizedBox(width: AppSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.asset.name, style: text.titleMedium),
                    Text(
                      quantity,
                      style: text.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formats.amount(p.value, Currency.eur),
                    style: AppText.figure.copyWith(color: AppColors.ink),
                  ),
                  if (pnl != null)
                    Text(
                      formats.percent(pnl, signed: true),
                      style: text.bodySmall?.copyWith(
                        color: signColor(pnl, ratio: true),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A trip's header (BRIEF §4.5): its clock, name and difficulty, and the
/// simulated day, on a neutral card: being in a trip shows in the content,
/// never as a tint.
class _TripHeader extends StatelessWidget {
  const _TripHeader(this.o);
  final WalletOverview o;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final difficulty = switch (o.difficulty) {
      'decouverte' => l10n.difficulty_decouverte,
      'realiste' => l10n.difficulty_realiste,
      'serre' => l10n.difficulty_serre,
      'sur-mesure' => l10n.difficulty_sur_mesure,
      _ => null,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: AppSpace.minTarget,
                height: AppSpace.minTarget,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(
                    AppShape.flatButtonRadius,
                  ),
                ),
                child: const Icon(Icons.schedule, color: AppColors.ink),
              ),
            ),
            const SizedBox(width: AppSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpace.x2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(o.name, style: text.titleMedium),
                      if (difficulty != null)
                        Chip(
                          label: Text(difficulty),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  Text(formats.date(o.asOf), style: AppText.title),
                ],
              ),
            ),
            if (o.status != WalletStatus.finished)
              IconButton(
                tooltip: l10n.trip_stops,
                icon: const Icon(Icons.tune),
                onPressed: () => showStopsSheet(
                  context,
                  walletId: o.id,
                  current: o.stops,
                  contribution: o.monthlyContribution,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// +1 jour, +1 semaine, +1 mois, « Avancer jusqu'à… » and « Terminer le
/// voyage » (BRIEF §4.5). Off while time moves and once the trip stopped by
/// itself; a finished trip (by hand, or at the end of the data) leads to its
/// summary instead.
class _TimeControls extends ConsumerWidget {
  const _TimeControls(this.o);
  final WalletOverview o;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final runner = ref.watch(tripRunnerProvider(o.id));
    final stopRoute = '/wallet/${o.id}/stop/${stopEventId(o.asOf)}';
    final summaryRoute = '/wallet/${o.id}/summary';
    // A stop opens its screen as soon as the advance lands, the end of the
    // data the summary.
    ref.listen(tripRunnerProvider(o.id), (previous, next) {
      final advance = next.value;
      if (previous?.isLoading != true || advance == null) return;
      if (advance.stop.isNotEmpty) {
        context.push('/wallet/${o.id}/stop/${stopEventId(advance.state.date)}');
      } else if (advance.endOfData) {
        context.push(summaryRoute);
      }
    });
    final finishing = ref.watch(tripFinishProvider(o.id)).isLoading;
    final moving = runner.isLoading || finishing;
    final stopped = o.status == WalletStatus.stopped;
    final canMove = !moving && !stopped;
    final note = switch ((stopped, runner.error)) {
      (true, _) => (l10n.wallets_status_stopped, AppColors.alertText),
      (_, final Failure f) => (failureMessage(context, f), AppColors.alertText),
      _ => null,
    };

    if (o.status == WalletStatus.finished) {
      return _ControlsCard(
        children: [
          Text(
            l10n.trip_finished(_formats(context).date(o.asOf)),
            style: text.bodyMedium,
          ),
          const SizedBox(height: AppSpace.x2),
          FilledButton(
            onPressed: () => context.push(summaryRoute),
            child: Text(l10n.trip_see_summary),
          ),
        ],
      );
    }

    return _ControlsCard(
      children: [
        if (note case (final message, final color)) ...[
          Text(message, style: text.bodySmall?.copyWith(color: color)),
          const SizedBox(height: AppSpace.x2),
        ],
        Row(
          children: [
            for (final (step, label) in [
              (TripStep.day, l10n.trip_step_day),
              (TripStep.week, l10n.trip_step_week),
              (TripStep.month, l10n.trip_step_month),
            ]) ...[
              if (step != TripStep.day) const SizedBox(width: AppSpace.x2),
              Expanded(
                child: OutlinedButton(
                  // Three to a row at phone width: no wrapping.
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.x2,
                    ),
                  ),
                  onPressed: canMove
                      ? () => ref
                            .read(tripRunnerProvider(o.id).notifier)
                            .advance(step)
                      : null,
                  child: Text(label),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.x2),
        Row(
          children: [
            Expanded(
              child: stopped
                  ? FilledButton(
                      onPressed: () => context.push(stopRoute),
                      child: Text(l10n.trip_see_stop),
                    )
                  : TextButton(
                      onPressed: canMove
                          ? () => showForwardSheet(
                              context,
                              walletId: o.id,
                              from: o.asOf,
                            )
                          : null,
                      child: Text(l10n.trip_forward),
                    ),
            ),
            const SizedBox(width: AppSpace.x2),
            Expanded(
              child: TextButton(
                onPressed: moving ? null : () => _finish(context, ref),
                child: Text(l10n.trip_finish),
              ),
            ),
          ],
        ),
        if (moving) ...[
          const SizedBox(height: AppSpace.x2),
          Semantics(
            label: l10n.trip_moving,
            child: const LinearProgressIndicator(),
          ),
        ],
      ],
    );
  }

  /// « Terminer le voyage », once confirmed, then the summary.
  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.trip_finish_title),
        content: Text(l10n.trip_finish_body(_formats(context).date(o.asOf))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(material.cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.trip_finish_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final finish = tripFinishProvider(o.id);
    await ref.read(finish.notifier).finish();
    if (!context.mounted) return;
    if (ref.read(finish).error case final Failure failure) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure))));
      return;
    }
    context.push('/wallet/${o.id}/summary');
  }
}

/// The card under a trip that holds its time controls.
class _ControlsCard extends StatelessWidget {
  const _ControlsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenPadding,
        AppSpace.x2,
        AppSpace.screenPadding,
        AppSpace.x2,
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}
