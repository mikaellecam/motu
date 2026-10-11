import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/presentation/features/wallet/wallet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// A live wallet three months in: four positions bought on 2 July, valued on
// 8 October 2026. Fixed data, no network.

Decimal d(String s) => Decimal.parse(s);
Money eur(num v) => Money.book(d(v.toStringAsFixed(2)), Currency.eur);

Asset asset(String id, String name, AssetType type, Exchange exchange) => Asset(
  id: id,
  symbol: id.toUpperCase(),
  name: name,
  type: type,
  exchange: exchange,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(2000),
);

final assets = {
  'world': asset('world', 'ETF Monde', AssetType.etf, Exchange.nasdaq),
  'apple': asset('apple', 'Apple', AssetType.stock, Exchange.nasdaq),
  'asml': asset('asml', 'ASML', AssetType.stock, Exchange.nasdaq),
  'coca-cola': asset('coca-cola', 'Coca-Cola', AssetType.stock, Exchange.nyse),
};

// (asset, quantity, bought at, now) in dollars.
const holdings = [
  ('world', '150', '120', '131.2'),
  ('apple', '20', '210', '236.4'),
  ('asml', '4', '700', '689.5'),
  ('coca-cola', '30.5', '70', '68.4'),
];

final start = DateTime.utc(2026, 7, 1);
final today = DateTime.utc(2026, 10, 8);

List<DateTime> weekdays() => [
  for (var t = start; t.isBefore(today); t = t.add(const Duration(days: 1)))
    if (t.weekday <= 5) t,
];

/// A wavy path from 50 000 € to [end].
List<DailyValue> path(num end, {double wave = 450}) {
  final days = weekdays();
  return [
    for (var i = 0; i < days.length; i++)
      DailyValue(
        date: days[i],
        value: eur(
          50000 +
              (end - 50000) * i / days.length +
              wave * sin(i / 3.5) * (i / days.length),
        ),
        flow: eur(i == 0 ? 50000 : 0),
      ),
  ];
}

WalletOverview overview({List<Order> pending = const []}) {
  final rules = TradingRules(
    fxFeeRate: d('0.0015'),
    fixedFee: eur(0),
    fractionalShares: true,
  );
  final fills = [
    for (final (id, qty, price, _) in holdings)
      Fill(
        assetId: id,
        side: Side.buy,
        date: DateTime.utc(2026, 7, 2),
        quantity: Quantity.truncate(d(qty)),
        price: Price(d(price), Currency.usd),
        fxRate: d('0.8612'),
        fees: Money.book(
          d(qty) * d(price) * d('0.8612') * d('0.0015'),
          Currency.eur,
        ),
      ),
  ];
  var cash = eur(50000);
  for (final f in fills) {
    cash = cash - f.notional - f.fees;
  }
  return buildOverview(
    wallet: WalletState(
      id: 'live',
      kind: WalletKind.live,
      name: 'live',
      startDate: start,
      simDate: null,
      status: WalletStatus.active,
      params: WalletParams(
        rules: rules,
        monthlyContribution: eur(0),
        stops: const StopConditions(),
      ),
      cash: cash,
      fills: fills,
      positions: positionsFrom(fills),
      pendingOrders: pending,
      values: path(51050),
      livretMovements: const [],
      plans: const [],
    ),
    asOf: DateTime.utc(2026, 10, 8, 13, 0),
    assets: assets,
    prices: {
      for (final (id, _, _, now) in holdings)
        id: ObservedPrice(
          PriceAsOf(
            Price(d(now), Currency.usd),
            DateTime.utc(2026, 10, 7),
            stale: false,
          ),
          DateTime.utc(2026, 10, 7, 20),
        ),
    },
    fxRates: {Currency.usd: d('0.8547')},
    livret: Decimal.zero,
  );
}

final overrides = [
  cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
  walletOverviewProvider.overrideWith((ref, id) async => overview()),
  walletChartProvider.overrideWith((ref, args) async {
    final (_, period, benchmark) = args;
    return chartFor(
      overview().series,
      period,
      benchmark: benchmark == null
          ? null
          : [
              for (final v in path(51600, wave: 650))
                ValuePoint(v.date, v.value.amount, eur(50000)),
            ],
    );
  }),
];

// Sent on Wednesday evening, the Nasdaq and the NYSE closed: a 500 € buy of
// Apple at the open, a limit sell of Coca-Cola.
final pending = [
  Order(
    id: 'o1',
    assetId: 'apple',
    side: Side.buy,
    type: OrderType.market,
    size: AmountSize(eur(500)),
    createdAt: DateTime.utc(2026, 10, 7, 21),
  ),
  Order(
    id: 'o2',
    assetId: 'coca-cola',
    side: Side.sell,
    type: OrderType.limit,
    size: QuantitySize(Quantity.whole(10)),
    limitPrice: Price(d('72'), Currency.usd),
    createdAt: DateTime.utc(2026, 10, 7, 21, 5),
  ),
];

void main() {
  screenshot(
    'm4-6-wallet-pending',
    const WalletScreen(walletId: 'live'),
    size: const Size(390, 760),
    overrides: [
      ...overrides.skip(2),
      cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
      walletOverviewProvider.overrideWith(
        (ref, id) async => overview(pending: pending),
      ),
    ],
  );
  screenshot(
    'm4-2-wallet',
    const WalletScreen(walletId: 'live'),
    size: const Size(390, 1560),
    overrides: overrides,
  );
  screenshot(
    'm4-2-wallet-benchmark',
    const WalletScreen(walletId: 'live'),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('3M'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'ETF Monde'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(find.byType(ListView), const Offset(0, -330));
    },
  );
}
