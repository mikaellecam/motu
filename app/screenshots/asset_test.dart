import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/asset/asset_page.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/presentation/features/asset/asset_screen.dart';
import 'package:finance_companion/presentation/features/asset/stability_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// Apple in the live wallet on 7 October 2026, from the backfilled history
// (fixtures/apple.json: closes of Apple and the world ETF, USD→EUR rates).
// Two buys at the real closes and rates of their days.

final _data = jsonDecode(
  File('screenshots/fixtures/apple.json').readAsStringSync(),
) as Map<String, dynamic>;

DateTime _date(String s) => DateTime.parse('${s}T00:00:00Z');

List<PriceBar> _bars(String key) => [
  for (final [date, close] in (_data[key] as List).cast<List>())
    PriceBar(
      date: _date(date as String),
      open: Decimal.parse(close as String),
      high: Decimal.parse(close),
      low: Decimal.parse(close),
      close: Decimal.parse(close),
      volume: 0,
      currency: Currency.usd,
    ),
];

final _rates = [
  for (final [date, rate] in (_data['usd_eur'] as List).cast<List>())
    (_date(date as String), Decimal.parse(rate as String)),
];

Decimal _fx(DateTime day) => _rates.lastWhere((r) => !r.$1.isAfter(day)).$2;

AssetOverview _overview() {
  final apple = _bars('apple');
  Fill buy(String date, String qty) {
    final day = _date(date);
    return Fill(
      assetId: 'apple',
      side: Side.buy,
      date: day,
      quantity: Quantity.truncate(Decimal.parse(qty)),
      price: Price(
        apple.lastWhere((b) => !b.date.isAfter(day)).close,
        Currency.usd,
      ),
      fxRate: _fx(day),
      fees: const Money.zero(Currency.eur),
    );
  }

  final fills = [buy('2026-03-02', '10'), buy('2026-06-01', '5')];
  return buildAssetOverview(
    asset: Asset(
      id: 'apple',
      symbol: 'AAPL',
      name: 'Apple',
      type: AssetType.stock,
      exchange: Exchange.nasdaq,
      currency: Currency.usd,
      region: 'us',
      listingDate: DateTime.utc(1980, 12, 12),
    ),
    wallet: WalletState(
      id: 'live',
      kind: WalletKind.live,
      name: 'live',
      startDate: DateTime.utc(2026, 1, 5),
      simDate: null,
      status: WalletStatus.active,
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: Decimal.parse('0.0015'),
          fixedFee: const Money.zero(Currency.eur),
          fractionalShares: true,
        ),
        monthlyContribution: const Money.zero(Currency.eur),
        stops: const StopConditions(),
      ),
      cash: const Money.zero(Currency.eur),
      fills: fills,
      positions: positionsFrom(fills),
      pendingOrders: const [],
      values: const [],
      livretMovements: const [],
      plans: const [],
    ),
    asOf: DateTime.utc(2026, 10, 7, 21),
    bars: apple,
    benchmark: _bars('world'),
    quote: null,
    closeObservedAt: DateTime.utc(2026, 10, 7, 20),
    fx: _fx,
    uiLevel: 2,
  );
}

void main() {
  final o = _overview();
  final overrides = [
    cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
    assetOverviewProvider.overrideWith((ref, args) async => o),
    assetChartProvider.overrideWith((ref, args) async {
      final (_, _, period, benchmark) = args;
      return assetChartFor(o, period, benchmark: benchmark);
    }),
  ];
  // The accessibility pass (M9-3): text at 130 %, nothing cut off.
  screenshot(
    'm9-3-asset-130',
    const AssetScreen(assetId: 'apple'),
    size: const Size(390, 2250),
    textScale: 1.3,
    overrides: overrides,
  );

  screenshot(
    'm4-4-asset',
    const AssetScreen(assetId: 'apple'),
    size: const Size(390, 1640),
    overrides: overrides,
  );
  // « Stabilité passée » (M9-36), scrolled to the top of the screen.
  screenshot(
    'm9-36-asset-score',
    const AssetScreen(assetId: 'apple'),
    overrides: overrides,
    act: (tester) async {
      final card = find.byType(StabilityCard);
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(card);
    },
  );
  screenshot(
    'm4-4-asset-5y-benchmark',
    const AssetScreen(assetId: 'apple'),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('5A'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'ETF Monde'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
