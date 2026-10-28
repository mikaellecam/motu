import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/livret_line.dart';
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
import 'package:finance_companion/core/widgets/chunky.dart';
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

/// [onLivret]: 3 000 € moved to the Livret in the spring, 21,25 € of
/// interest earned on it this year.
WalletOverview overview({
  List<Order> pending = const [],
  bool onLivret = false,
  List<PlanView> plans = const [],
  bool fresh = false,
}) {
  final rules = TradingRules(
    fxFeeRate: d('0.0015'),
    fixedFee: eur(0),
    fractionalShares: true,
  );
  final fills = [
    // A fresh wallet: nothing bought yet (M11-4).
    if (!fresh)
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
      cash: onLivret ? cash - eur(3000) : cash,
      fills: fills,
      positions: positionsFrom(fills),
      pendingOrders: pending,
      values: fresh
          ? [
              DailyValue(
                date: DateTime.utc(2026, 10, 8),
                value: eur(50000),
                flow: eur(50000),
              ),
            ]
          : path(51050),
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
    livret: onLivret ? d('3021.25') : Decimal.zero,
    plans: plans,
  );
}

/// The Livret line of [overview]: 3 000 € on it, 21,25 € of interest this
/// year.
final livret = livretLineProvider.overrideWith(
  (ref, id) async => LivretLine(
    day: DateTime.utc(2026, 10, 8),
    balance: eur(3000),
    accrued: d('21.25'),
    rate: d('0.017'),
    ceiling: eur(22950),
    availableCash: (await ref.watch(walletOverviewProvider(id).future))
        .availableCash,
  ),
);

final overrides = [
  livret,
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
      livret,
      ...overrides.skip(3),
      cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
      walletOverviewProvider.overrideWith(
        (ref, id) async => overview(pending: pending),
      ),
    ],
  );
  // Two plans (M9-41): the world ETF every month since July, Apple every
  // week from Friday.
  screenshot(
    'm9-41-wallet-plans',
    const WalletScreen(walletId: 'live'),
    size: const Size(390, 900),
    overrides: [
      livret,
      ...overrides.skip(3),
      cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
      walletOverviewProvider.overrideWith(
        (ref, id) async => overview(
          plans: [
            PlanView(
              plan: DcaPlan(
                id: 'live-1',
                assetId: 'world',
                amount: eur(200),
                frequency: DcaFrequency.monthly,
                start: DateTime.utc(2026, 7, 2),
              ),
              asset: assets['world']!,
              next: DateTime.utc(2026, 11, 2),
            ),
            PlanView(
              plan: DcaPlan(
                id: 'live-2',
                assetId: 'apple',
                amount: eur(50),
                frequency: DcaFrequency.weekly,
                start: DateTime.utc(2026, 10, 9),
              ),
              asset: assets['apple']!,
              next: DateTime.utc(2026, 10, 9),
            ),
          ],
        ),
      ),
    ],
  );
  screenshot(
    'm4-2-wallet',
    const WalletScreen(walletId: 'live'),
    size: const Size(390, 1560),
    overrides: overrides,
  );
  // Before the first buy (M11-4): the bare island, and a plot waiting.
  screenshot(
    'm11-4-wallet-empty',
    const WalletScreen(walletId: 'live'),
    size: const Size(390, 1400),
    overrides: [
      livret,
      cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
      walletOverviewProvider.overrideWith(
        (ref, id) async => overview(fresh: true),
      ),
      walletChartProvider.overrideWith(
        (ref, args) async => chartFor(overview(fresh: true).series, args.$2),
      ),
    ],
  );
  // Relaunched offline (BRIEF §6.4): the last prices, dated, under the banner.
  screenshot(
    'm9-5-wallet-offline',
    const WalletScreen(walletId: 'live'),
    size: const Size(390, 760),
    overrides: [
      livret,
      ...overrides.skip(2),
      cacheStatusProvider.overrideWith(
        (ref) => Stream.value(Offline(DateTime.utc(2026, 10, 7, 20, 5))),
      ),
    ],
  );
  screenshot(
    'm4-2-wallet-benchmark',
    const WalletScreen(walletId: 'live'),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('3M'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChunkyChip, 'ETF Monde'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(find.byType(ListView), const Offset(0, -330));
    },
  );

  final onLivret = [
    livret,
    cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
    walletOverviewProvider.overrideWith(
      (ref, id) async => overview(onLivret: true),
    ),
    ...overrides.skip(3),
  ];
  Future<void> toLivret(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.widgetWithText(ChunkyButton, 'Verser'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
  }

  screenshot(
    'm8-1-livret',
    const WalletScreen(walletId: 'live'),
    overrides: onLivret,
    act: toLivret,
  );

  screenshot(
    'm8-1-livret-sheet',
    const WalletScreen(walletId: 'live'),
    overrides: onLivret,
    act: (tester) async {
      await toLivret(tester);
      await tester.tap(find.widgetWithText(ChunkyButton, 'Verser'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField), '25000');
    },
  );
}
