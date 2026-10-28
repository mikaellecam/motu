import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/trip/trip_catch_up.dart';
import '../../../application/trip/trip_runner.dart';
import '../../../application/trip/trip_stop.dart';
import '../../../application/trip/trip_summary.dart';
import '../../../application/wallet/dca_plans.dart';
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
import '../../../core/widgets/chunky.dart';
import '../../../domain/market/asset.dart';
import '../../../domain/wallet/valuation.dart';
import '../../../domain/wallet/wallet.dart';
import '../../widgets/chart_axis.dart';
import '../../widgets/chart_legend.dart';
import '../../widgets/section_title.dart';
import '../../widgets/asset_avatar.dart';
import '../companion/companion_card.dart';
import '../order/order_screen.dart';
import '../trip/trip_header.dart';
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
    // The live wallet, or a trip at today, first catches up with the
    // sessions that closed.
    Future<void> refresh() async {
      if (overview?.kind == WalletKind.live) {
        await ref.read(liveCatchUpProvider.notifier).run();
      } else if (overview?.kind == WalletKind.trip) {
        await ref.read(tripCatchUpProvider.notifier).run(walletId);
      }
      await ref.refresh(walletOverviewProvider(walletId).future).then((_) {});
    }

    final content = switch (overview) {
      final o? => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            CacheStatusBanner(onRetry: refresh),
            const SizedBox(height: AppSpace.x2),
            _Header(o),
            if (o.kind == WalletKind.trip) _NextContribution(o),
            const SizedBox(height: AppSpace.x4),
            _Tiles(o),
            const SizedBox(height: AppSpace.x4),
            // A finished trip no longer trades.
            if (o.status != WalletStatus.finished) ...[
              ChunkyButton(
                label: l10n.wallet_invest,
                onPressed: () => context.go('/explore?wallet=${o.id}'),
              ),
              const SizedBox(height: AppSpace.x4),
            ],
            WalletCompanionCard(walletId: o.id),
            if (o.pendingOrders.isNotEmpty) ...[
              _PendingCard(o),
              const SizedBox(height: AppSpace.x4),
            ],
            if (o.plans.isNotEmpty) ...[
              _PlansCard(o),
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
    };

    // A trip has its own header in place of the app bar, and its time
    // controls under the screen (BRIEF §4.5).
    if (overview case final o? when o.kind == WalletKind.trip) {
      return Scaffold(
        bottomNavigationBar: _TimeControls(o),
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TripHeader(o),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: ChunkyBackButton.leadingOf(context),
        leadingWidth: ChunkyBackButton.width,
        title: overview == null ? null : Text(l10n.wallet_live_name),
      ),
      body: content,
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
            ChunkySegmented(
              segments: [
                (ChartPeriod.week, l10n.wallet_period_week),
                (ChartPeriod.month, l10n.wallet_period_month),
                (ChartPeriod.quarter, l10n.wallet_period_quarter),
                (ChartPeriod.year, l10n.wallet_period_year),
                (ChartPeriod.all, l10n.wallet_period_all),
              ],
              selected: _period,
              onChanged: (period) => setState(() => _period = period),
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
                ChartLegend(
                  l10n.wallet_chart_money_in,
                  color: AppColors.muted,
                  dashed: true,
                ),
                if (benchmarkName != null)
                  ChartLegend(benchmarkName, color: AppColors.ink),
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
                  ChunkyChip(
                    label: label,
                    selected: _benchmark == benchmark,
                    onTap: () => setState(
                      () => _benchmark = _benchmark == benchmark
                          ? null
                          : benchmark,
                    ),
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
          titlesData: dateAxis(
            data.dates,
            formats,
            style: AppText.caption.copyWith(color: AppColors.muted),
          ),
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
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              // Where the wallet stands now.
              dotData: FlDotData(
                checkToShowDot: (spot, _) => spot.x == data.values.length - 1,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: AppColors.primary,
                  strokeColor: AppColors.surface,
                  strokeWidth: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

    return TitledSection(
      title: l10n.wallet_allocation_title,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
    return TitledSection(
      title: l10n.wallet_pending_title,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (:order, :asset, reserved: _) in o.pendingOrders)
                InkWell(
                  onTap: () =>
                      context.push('/wallet/${o.id}/order/${order.id}'),
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
      ),
    );
  }
}

/// « Versements programmés » (M9-41): each active DCA plan with its amount,
/// frequency and next purchase, and « Arrêter ».
class _PlansCard extends ConsumerWidget {
  const _PlansCard(this.o);
  final WalletOverview o;

  Future<void> _stop(BuildContext context, WidgetRef ref, PlanView p) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.wallet_plan_stop_title),
        content: Text(l10n.wallet_plan_stop_body(p.asset.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.wallet_plan_stop_keep),
          ),
          ChunkyButton(
            label: l10n.wallet_plan_stop,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(planActionsProvider(o.id).notifier).stop(p.plan.id);
    } on Failure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Alive while the list shows, so a stop can refresh the wallet.
    ref.watch(planActionsProvider(o.id));
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    return TitledSection(
      title: l10n.wallet_plans_title,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in o.plans)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.x3,
                    vertical: AppSpace.x2,
                  ),
                  child: Row(
                    children: [
                      AssetAvatar(p.asset),
                      const SizedBox(width: AppSpace.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.asset.name, style: text.titleMedium),
                            Text(
                              l10n.wallet_plan_amount(
                                formats.money(p.plan.amount),
                                p.plan.frequency.name,
                              ),
                              style: AppText.figure.copyWith(
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              l10n.wallet_plan_next(formats.dayMonth(p.next)),
                              style: muted,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _stop(context, ref, p),
                        child: Text(l10n.wallet_plan_stop),
                      ),
                    ],
                  ),
                ),
            ],
          ),
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
    return TitledSection(
      title: l10n.wallet_positions_title,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              AssetAvatar(p.asset),
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

/// The trip's header (BRIEF §4.5) with its difficulty, and its automatic
/// stops until it ends.
class _TripHeader extends StatelessWidget {
  const _TripHeader(this.o);
  final WalletOverview o;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TripHeader(
      name: o.name,
      date: o.asOf,
      chip: switch (o.difficulty) {
        'decouverte' => l10n.difficulty_decouverte,
        'realiste' => l10n.difficulty_realiste,
        'serre' => l10n.difficulty_serre,
        'sur-mesure' => l10n.difficulty_sur_mesure,
        _ => null,
      },
      actions: [
        if (o.status != WalletStatus.finished)
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.x2),
            child: ChunkyIconButton(
              icon: Icons.tune,
              label: l10n.trip_stops,
              onPressed: () => showStopsSheet(
                context,
                walletId: o.id,
                current: o.stops,
                contribution: o.monthlyContribution,
              ),
            ),
          ),
      ],
    );
  }
}

/// « Prochain versement : +200 € le 2 mars », when the trip has one.
class _NextContribution extends ConsumerWidget {
  const _NextContribution(this.o);
  final WalletOverview o;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Until it is known, or if the calendar cannot be read: no line.
    final next = ref.watch(nextContributionProvider(o.id)).value;
    if (next == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final amount = o.monthlyContribution.amount;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.x1),
      child: Row(
        children: [
          const ExcludeSemantics(
            child: Icon(
              Icons.calendar_today_outlined,
              size: AppSpace.x4,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: AppSpace.x2),
          Expanded(
            child: Text(
              l10n.trip_next_contribution(
                formats.amount(
                  amount,
                  o.monthlyContribution.currency,
                  signed: true,
                  decimals: amount.isInteger ? 0 : 2,
                ),
                formats.dayMonth(next),
              ),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// « Avancer le temps » (BRIEF §4.5): +1 jour, +1 semaine, +1 mois and
/// « Avancer jusqu'à… », with « Terminer le voyage » by the title. Off while
/// time moves, once the trip stopped by itself, which leads to its stop
/// instead, and at today, when the trip goes on by itself; a finished trip
/// leads to its summary.
class _TimeControls extends ConsumerWidget {
  const _TimeControls(this.o);
  final WalletOverview o;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final runner = ref.watch(tripRunnerProvider(o.id));
    final stopRoute = '/wallet/${o.id}/stop/${stopEventId(o.asOf)}';
    final summaryRoute = '/wallet/${o.id}/summary';
    // A stop opens its screen as soon as the advance lands.
    ref.listen(tripRunnerProvider(o.id), (previous, next) {
      final advance = next.value;
      if (previous?.isLoading != true || advance == null) return;
      if (advance.stop.isNotEmpty) {
        context.push('/wallet/${o.id}/stop/${stopEventId(advance.state.date)}');
      }
    });
    final finishing = ref.watch(tripFinishProvider(o.id)).isLoading;
    final catchingUp =
        o.reachedToday && ref.watch(tripCatchUpProvider).isLoading;
    final moving = runner.isLoading || finishing || catchingUp;
    final stopped = o.status == WalletStatus.stopped;
    // At today, prices ahead are not known yet: no step is left to take.
    final canMove = !moving && !stopped && !o.reachedToday;
    final note = switch ((stopped, runner.error)) {
      (true, _) => l10n.wallets_status_stopped,
      (_, final Failure f) => failureMessage(context, f),
      _ => null,
    };

    if (o.status == WalletStatus.finished) {
      return _ControlsCard(
        children: [
          _ControlsTitle(l10n.trip_finished(_formats(context).date(o.asOf))),
          const SizedBox(height: AppSpace.x3),
          ChunkyButton(
            label: l10n.trip_see_summary,
            onPressed: () => context.push(summaryRoute),
          ),
        ],
      );
    }

    return _ControlsCard(
      children: [
        _ControlsTitle(
          l10n.trip_time_title,
          action: TextButton(
            onPressed: moving ? null : () => _finish(context, ref),
            child: Text(l10n.trip_finish),
          ),
        ),
        const SizedBox(height: AppSpace.x2),
        if (note != null) ...[
          AlertMessage(note),
          const SizedBox(height: AppSpace.x3),
        ] else if (o.reachedToday) ...[
          Text(
            l10n.trip_at_today,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpace.x3),
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
                child: ChunkyButton(
                  label: label,
                  kind: ChunkyButtonKind.secondary,
                  compact: true,
                  onPressed: canMove
                      ? () => ref
                            .read(tripRunnerProvider(o.id).notifier)
                            .advance(step)
                      : null,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.x2),
        if (stopped)
          ChunkyButton(
            label: l10n.trip_see_stop,
            onPressed: () => context.push(stopRoute),
          )
        else
          ChunkyButton(
            label: l10n.trip_forward,
            onPressed: canMove
                ? () => showForwardSheet(
                    context,
                    walletId: o.id,
                    from: o.asOf,
                    stops: o.stops,
                    contribution: o.monthlyContribution,
                  )
                : null,
          ),
        if (moving) ...[
          const SizedBox(height: AppSpace.x3),
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
          ChunkyButton(
            label: l10n.trip_finish_confirm,
            onPressed: () => Navigator.pop(context, true),
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

/// The chunky card under a trip that holds its time controls.
class _ControlsCard extends StatelessWidget {
  const _ControlsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x3,
        AppSpace.x2,
        AppSpace.x3,
        AppSpace.x4,
      ),
      child: ChunkyCard(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

/// The card's title by a clock, and its [action] on the right (under it
/// when large text leaves no room).
class _ControlsTitle extends StatelessWidget {
  const _ControlsTitle(this.title, {this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ExcludeSemantics(
            child: Icon(
              Icons.schedule,
              size: AppSpace.x5,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: AppSpace.x2),
          Flexible(
            child: Semantics(
              header: true,
              child: Text(title, style: AppText.titleXSmall),
            ),
          ),
        ],
      ),
      ?action,
    ],
  );
}
