import 'dart:async';
import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_runner.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/presentation/features/wallet/wallet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'screenshot.dart';

// A « Réaliste » trip that left on 15 September 2008, three weeks in.
// Values are illustrative.

class _Idle extends TripRunner {
  @override
  FutureOr<TripAdvance?> build(String walletId) => null;
}

Decimal d(String s) => Decimal.parse(s);
Money eur(num v) => Money.book(d(v.toStringAsFixed(2)), Currency.eur);
DateTime day(int m, int dd) => DateTime.utc(2008, m, dd);

Asset _asset(String id, String name, AssetType type) => Asset(
  id: id,
  symbol: id.toUpperCase(),
  name: name,
  type: type,
  exchange: Exchange.nyse,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(2000),
);

WalletOverview _trip({WalletStatus status = WalletStatus.active}) {
  Fill buy(String id, String qty, String price) => Fill(
    assetId: id,
    side: Side.buy,
    date: day(9, 15),
    quantity: Quantity.truncate(d(qty)),
    price: Price(d(price), Currency.usd),
    fxRate: d('0.7058'),
    fees: Money.book(
      d(qty) * d(price) * d('0.7058') * d('0.0015'),
      Currency.eur,
    ),
  );
  final fills = [buy('sp500', '40', '120.18'), buy('coca-cola', '50', '52.21')];
  var cash = eur(10000);
  for (final f in fills) {
    cash = cash - f.notional - f.fees;
  }
  final days = [
    for (
      var t = day(9, 15);
      !t.isAfter(day(10, 3));
      t = t.add(const Duration(days: 1))
    )
      if (t.weekday <= 5) t,
  ];
  return buildOverview(
    wallet: WalletState(
      id: 'lehman',
      kind: WalletKind.trip,
      name: 'Crise financière',
      startDate: day(9, 15),
      simDate: day(10, 3),
      status: status,
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: d('0.0015'),
          fixedFee: eur(0),
          fractionalShares: true,
        ),
        monthlyContribution: eur(200),
        stops: const StopConditions(),
        difficulty: 'realiste',
      ),
      cash: cash,
      fills: fills,
      positions: positionsFrom(fills),
      pendingOrders: const [],
      values: [
        for (var i = 0; i < days.length; i++)
          DailyValue(
            date: days[i],
            value: eur(10000 - 38 * i + 60 * sin(i / 1.5)),
            flow: eur(i == 0 ? 10000 : 0),
          ),
      ],
      livretMovements: const [],
      plans: const [],
    ),
    asOf: day(10, 3),
    assets: {
      'sp500': _asset('sp500', 'SPDR S&P 500 ETF Trust', AssetType.etf),
      'coca-cola': _asset('coca-cola', 'Coca-Cola', AssetType.stock),
    },
    prices: {
      for (final (id, price) in [('sp500', '110.79'), ('coca-cola', '51.85')])
        id: ObservedPrice(
          PriceAsOf(Price(d(price), Currency.usd), day(10, 3), stale: false),
          DateTime.utc(2008, 10, 3, 20),
        ),
    },
    fxRates: {Currency.usd: d('0.7223')},
    livret: Decimal.zero,
  );
}

void main() {
  List<Override> overrides(WalletOverview o) => [
    cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
    walletOverviewProvider.overrideWith((ref, id) async => o),
    // Monday 3 November: the 1st is a Saturday.
    nextContributionProvider.overrideWith(
      (ref, id) async =>
          o.status == WalletStatus.finished ? null : DateTime.utc(2008, 11, 3),
    ),
    walletChartProvider.overrideWith(
      (ref, args) async => chartFor(o.series, args.$2),
    ),
    tripRunnerProvider.overrideWith2((_) => _Idle()),
  ];

  screenshot(
    'm5-3-trip-wallet',
    const WalletScreen(walletId: 'lehman'),
    size: const Size(390, 1500),
    overrides: overrides(_trip()),
  );
  // What changes in a phone's height when the trip stopped by itself, and
  // once it ended.
  for (final (name, status) in [
    ('m9-32-trip-wallet-stopped', WalletStatus.stopped),
    ('m9-32-trip-wallet-finished', WalletStatus.finished),
  ]) {
    screenshot(
      name,
      const WalletScreen(walletId: 'lehman'),
      overrides: overrides(_trip(status: status)),
    );
  }
}
