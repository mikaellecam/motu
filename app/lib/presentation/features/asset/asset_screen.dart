import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/asset/asset_page.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../domain/market/asset.dart';
import '../../../domain/market/market_calendar.dart';
import '../../../domain/wallet/position.dart';
import '../../widgets/cache_status_banner.dart';
import '../../widgets/sign_color.dart';
import '../glossary/term_sheet.dart';
import '../order/order_sheet.dart';

/// An asset as of a wallet's clock: price, chart, essentials, why it moved,
/// the wallet's position (BRIEF §4.8).
class AssetScreen extends ConsumerWidget {
  const AssetScreen({super.key, required this.assetId, this.walletId});

  final String assetId;
  final String? walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(assetOverviewProvider(assetId, walletId));
    Future<void> refresh() => ref
        .refresh(assetOverviewProvider(assetId, walletId).future)
        .then((_) {}, onError: (_) {});
    final overview = state.value;

    return Scaffold(
      appBar: AppBar(
        title: overview == null ? null : Text(overview.asset.name),
      ),
      bottomNavigationBar: overview != null && overview.tradable
          ? _TradeBar(overview)
          : null,
      body: switch (overview) {
        final o? => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.screenPadding),
            children: [
              CacheStatusBanner(onRetry: refresh),
              const SizedBox(height: AppSpace.x2),
              _Header(o),
              const SizedBox(height: AppSpace.x4),
              _ChartAndWhy(o, walletId: walletId),
              const SizedBox(height: AppSpace.x4),
              _Essentials(o),
              if (o.position != null) ...[
                const SizedBox(height: AppSpace.x4),
                _PositionCard(o),
              ],
            ],
          ),
        ),
        null when state.hasError => Center(
          child: ErrorView(
            failure: state.error is Failure
                ? state.error! as Failure
                : const ServerFailure(),
            onRetry: () =>
                ref.invalidate(assetOverviewProvider(assetId, walletId)),
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

TextStyle? _muted(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted);

class _Header extends StatelessWidget {
  const _Header(this.o);
  final AssetOverview o;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final exchange = switch (o.asset.exchange) {
      Exchange.nyse => l10n.exchange_nyse,
      Exchange.nasdaq => l10n.exchange_nasdaq,
      Exchange.otc => l10n.exchange_otc,
      Exchange.euronext => l10n.exchange_euronext,
    };
    final quoted = switch (o.asset.currency) {
      Currency.usd => l10n.asset_quoted_usd,
      Currency.eur => l10n.asset_quoted_eur,
    };
    final change = o.sessionChange;
    final observed = o.observedAt.toLocal();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [o.asset.symbol, exchange, quoted].join(' · '),
          style: _muted(context),
        ),
        const SizedBox(height: AppSpace.x1),
        Wrap(
          spacing: AppSpace.x3,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              formats.price(o.price),
              style: AppText.figureLarge.copyWith(color: AppColors.ink),
            ),
            if (o.asset.currency != Currency.eur)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  l10n.asset_eur_equivalent(
                    formats.amount(o.price.value * o.fxRate, Currency.eur),
                  ),
                  style: AppText.figure.copyWith(color: AppColors.muted),
                ),
              ),
          ],
        ),
        if (change != null)
          Text(
            l10n.asset_session_change(formats.percent(change, signed: true)),
            style: text.bodyLarge?.copyWith(
              color: signColor(change, ratio: true),
            ),
          ),
        Text(
          l10n.wallet_prices_as_of(
            formats.date(observed),
            formats.time(observed),
          ),
          style: _muted(context),
        ),
      ],
    );
  }
}

String _periodName(AppLocalizations l10n, AssetPeriod period) =>
    switch (period) {
      AssetPeriod.week => l10n.wallet_period_week_long,
      AssetPeriod.month => l10n.wallet_period_month_long,
      AssetPeriod.year => l10n.wallet_period_year_long,
      AssetPeriod.fiveYears => l10n.asset_period_five_years_long,
    };

/// The chart card and « Pourquoi ça bouge ? », which follows its period.
class _ChartAndWhy extends ConsumerStatefulWidget {
  const _ChartAndWhy(this.o, {required this.walletId});
  final AssetOverview o;
  final String? walletId;

  @override
  ConsumerState<_ChartAndWhy> createState() => _ChartAndWhyState();
}

class _ChartAndWhyState extends ConsumerState<_ChartAndWhy> {
  var _period = AssetPeriod.year;
  var _benchmark = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final chart = ref
        .watch(
          assetChartProvider(
            widget.o.asset.id,
            widget.walletId,
            _period,
            _benchmark,
          ),
        )
        .value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<AssetPeriod>(
                  showSelectedIcon: false,
                  segments: [
                    for (final (period, label) in [
                      (AssetPeriod.week, l10n.wallet_period_week),
                      (AssetPeriod.month, l10n.wallet_period_month),
                      (AssetPeriod.year, l10n.wallet_period_year),
                      (AssetPeriod.fiveYears, l10n.asset_period_five_years),
                    ])
                      ButtonSegment(value: period, label: Text(label)),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) => setState(() => _period = s.single),
                ),
                const SizedBox(height: AppSpace.x4),
                SizedBox(
                  height: 180,
                  child: chart == null
                      ? const AsyncSkeleton(lines: 3)
                      : _PriceChart(widget.o, chart, _period),
                ),
                if (chart != null) ...[
                  const SizedBox(height: AppSpace.x2),
                  Wrap(
                    spacing: AppSpace.x4,
                    runSpacing: AppSpace.x1,
                    children: [
                      if (chart.buys.isNotEmpty)
                        _Legend(l10n.asset_your_buys, color: AppColors.primary),
                      if (chart.drawdown.troughDate != null)
                        _Legend(
                          l10n.asset_worst_drop(
                            _formats(context)
                                .percent(chart.drawdown.depth, signed: true),
                          ),
                          color: AppColors.alert,
                        ),
                      if (chart.benchmark != null)
                        _Legend(
                          l10n.wallet_benchmark_world,
                          color: AppColors.ink,
                          dashed: true,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpace.x2),
                Wrap(
                  spacing: AppSpace.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(l10n.wallet_compare, style: text.bodyMedium),
                    FilterChip(
                      label: Text(l10n.wallet_benchmark_world),
                      selected: _benchmark,
                      showCheckmark: false,
                      onSelected: (on) => setState(() => _benchmark = on),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (chart?.decomposition != null) ...[
          const SizedBox(height: AppSpace.x4),
          _WhyCard(widget.o, chart!, _period),
        ],
      ],
    );
  }
}

class _PriceChart extends StatelessWidget {
  const _PriceChart(this.o, this.chart, this.period);
  final AssetOverview o;
  final AssetChart chart;
  final AssetPeriod period;

  @override
  Widget build(BuildContext context) {
    if (chart.closes.length < 2) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    // Doubles from here on: pixels, not money.
    final closes = [for (final c in chart.closes) c.toDouble()];
    final benchmark = chart.benchmark;
    final all = [
      ...closes,
      if (benchmark != null) ...[for (final b in benchmark) b.toDouble()],
      for (final b in chart.buys) b.price.toDouble(),
    ];
    final low = all.reduce((a, b) => a < b ? a : b);
    final high = all.reduce((a, b) => a > b ? a : b);
    final margin = (high - low) * 0.1 + 0.01;
    final drawdown = chart.drawdown;
    final drop = [
      for (final date in [drawdown.peakDate, drawdown.troughDate])
        if (date != null) chart.dates.indexOf(date),
    ];

    return Semantics(
      label: l10n.asset_chart_semantics(
        formats.elision(o.asset.name),
        o.asset.name,
        _periodName(l10n, period),
        formats.price(Price(chart.closes.first, o.price.currency)),
        formats.price(Price(chart.closes.last, o.price.currency)),
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
            if (benchmark != null)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < benchmark.length; i++)
                    FlSpot(i.toDouble(), benchmark[i].toDouble()),
                ],
                color: AppColors.ink,
                barWidth: 1.5,
                dashArray: const [6, 4],
                dotData: const FlDotData(show: false),
              ),
            LineChartBarData(
              spots: [
                for (var i = 0; i < closes.length; i++)
                  FlSpot(i.toDouble(), closes[i]),
              ],
              color: AppColors.primary,
              barWidth: 2,
              dotData: FlDotData(
                checkToShowDot: (spot, _) => drop.contains(spot.x.toInt()),
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: AppColors.alert,
                  strokeWidth: 0,
                ),
              ),
            ),
            // Buys: dots at the price paid, no line.
            if (chart.buys.isNotEmpty)
              LineChartBarData(
                spots: [
                  for (final b in chart.buys)
                    FlSpot(b.index.toDouble(), b.price.toDouble()),
                ],
                barWidth: 0,
                color: AppColors.primary.withValues(alpha: 0),
                dotData: FlDotData(
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 4.5,
                    color: AppColors.surface,
                    strokeColor: AppColors.primary,
                    strokeWidth: 2.5,
                  ),
                ),
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
      if (dashed)
        for (var i = 0; i < 3; i++)
          Container(
            width: 5,
            height: 2,
            margin: const EdgeInsets.only(right: 2),
            color: color,
          )
      else
        Container(
          width: AppSpace.x2,
          height: AppSpace.x2,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      const SizedBox(width: AppSpace.x1),
      Text(label, style: _muted(context)),
    ],
  );
}

class _WhyCard extends StatelessWidget {
  const _WhyCard(this.o, this.chart, this.period);
  final AssetOverview o;
  final AssetChart chart;
  final AssetPeriod period;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final m = chart.decomposition!;
    final parts = [
      (l10n.asset_why_market, m.market, AppColors.allocationShade(0)),
      if (o.asset.currency != Currency.eur)
        (l10n.asset_why_currency, m.currency, AppColors.allocationShade(2)),
      (l10n.asset_why_rest(o.asset.name), m.specific, AppColors.muted),
    ];
    final scale = parts.fold(Decimal.zero, (sum, p) => sum + p.$2.abs());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.asset_why_title, style: text.titleMedium),
            Text(
              l10n.asset_why_total(
                formats.percent(m.total, signed: true),
                _periodName(l10n, period),
              ),
              style: text.bodyMedium?.copyWith(
                color: signColor(m.total, ratio: true),
              ),
            ),
            if (scale > Decimal.zero) ...[
              const SizedBox(height: AppSpace.x3),
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpace.x1),
                  child: SizedBox(
                    height: AppSpace.x3,
                    child: Row(
                      children: [
                        for (final (_, value, color) in parts)
                          if (_flex(value, scale) case final flex when flex > 0)
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
            ],
            const SizedBox(height: AppSpace.x2),
            for (final (label, value, color) in parts)
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
                    Expanded(child: Text(label, style: text.bodyMedium)),
                    Text(
                      formats.percent(value, signed: true),
                      style: text.bodyMedium?.copyWith(
                        color: signColor(value, ratio: true),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A part's share of the bar, in thousandths.
  static int _flex(Decimal value, Decimal scale) => ratio(
    value.abs() * Decimal.fromInt(1000),
    scale,
  ).round().toBigInt().toInt();
}

class _Essentials extends StatelessWidget {
  const _Essentials(this.o);
  final AssetOverview o;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final unknown = l10n.explorer_risk_unknown;
    final band = switch (o.riskBand) {
      1 => l10n.asset_band_1,
      2 => l10n.asset_band_2,
      3 => l10n.asset_band_3,
      4 => l10n.asset_band_4,
      5 => l10n.asset_band_5,
      _ => null,
    };
    final volatility = o.volatility;
    final fxChange = o.fxYearChange;
    final performance = o.yearChange;

    // Each tile opens its term's sheet, about this asset (BRIEF §4.4).
    final tiles = [
      (
        'performance',
        l10n.asset_tile_performance,
        performance == null
            ? unknown
            : formats.percent(performance, signed: true),
        performance == null ? null : signColor(performance, ratio: true),
      ),
      (
        'volatilite',
        l10n.asset_tile_volatility,
        band == null || volatility == null
            ? unknown
            : o.uiLevel < 2
            ? band
            : l10n.asset_volatility_figure(band, formats.percent(volatility)),
        null,
      ),
      (
        'pire-baisse',
        l10n.asset_tile_drawdown,
        l10n.explorer_year_change(
          formats.percent(o.yearDrawdown.depth, signed: true),
        ),
        null,
      ),
      (
        'risque-de-change',
        l10n.asset_tile_fx,
        o.asset.currency == Currency.eur
            ? l10n.asset_fx_none
            : fxChange == null
            ? unknown
            : l10n.asset_fx_usd(formats.percent(fxChange, signed: true)),
        null,
      ),
    ];

    Widget tile((String, String, String, Color?) t) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showTermSheet(context, t.$1, assetId: o.asset.id),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.$2, style: _muted(context)),
              const SizedBox(height: AppSpace.x1),
              Text(
                t.$3,
                style: AppText.figure.copyWith(color: t.$4 ?? AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );

    // Two by two, each row as tall as its tallest tile.
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSpace.x3),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tile(tiles[i])),
                const SizedBox(width: AppSpace.x3),
                Expanded(child: tile(tiles[i + 1])),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard(this.o);
  final AssetOverview o;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final p = o.position!;
    final count = p.quantity.toDecimal();
    final quantity = switch (o.asset.type) {
      AssetType.stock => l10n.wallet_quantity_stock(
        formats.countForm(count),
        formats.quantity(p.quantity),
      ),
      AssetType.etf => l10n.wallet_quantity_etf(
        formats.countForm(count),
        formats.quantity(p.quantity),
      ),
    };
    final ratio = p.pnlRatio;
    final pnl = [
      formats.amount(p.pnl, Currency.eur, signed: true),
      if (ratio != null) '(${formats.percent(ratio, signed: true)})',
    ].join(' ');

    Widget row(
      String label,
      String value, {
      Color? color,
      bool indent = false,
    }) => Padding(
      padding: EdgeInsets.only(
        top: AppSpace.x1,
        bottom: AppSpace.x1,
        left: indent ? AppSpace.x4 : 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: indent ? _muted(context) : text.bodyMedium,
            ),
          ),
          const SizedBox(width: AppSpace.x2),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppText.figure.copyWith(color: color ?? AppColors.ink),
            ),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.asset_position_title, style: text.titleMedium),
            const SizedBox(height: AppSpace.x2),
            row(l10n.asset_position_quantity, quantity),
            row(
              l10n.asset_position_value,
              formats.amount(p.value, Currency.eur),
            ),
            row(l10n.asset_position_pnl, pnl, color: signColor(p.pnl)),
            row(
              l10n.asset_position_fx,
              formats.amount(p.currencyEffect, Currency.eur, signed: true),
              color: signColor(p.currencyEffect),
              indent: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// « Acheter · Vendre » (BRIEF §4.8): the order sheet, then what it did.
/// « Vendre » only with a position.
class _TradeBar extends StatelessWidget {
  const _TradeBar(this.o);
  final AssetOverview o;

  Future<void> _trade(BuildContext context, Side side) async {
    final message = await showOrderSheet(
      context,
      assetId: o.asset.id,
      walletId: o.walletId,
      side: side,
    );
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenPadding,
          AppSpace.x2,
          AppSpace.screenPadding,
          AppSpace.x2,
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => _trade(context, Side.buy),
                child: Text(l10n.asset_buy),
              ),
            ),
            if (o.position != null) ...[
              const SizedBox(width: AppSpace.x3),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _trade(context, Side.sell),
                  child: Text(l10n.asset_sell),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
