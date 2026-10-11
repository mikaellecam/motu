import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/dca/dca_simulator.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/domain/livret/livret_interest.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/dca_simulator.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_start.dart';
import 'package:finance_companion/presentation/features/dca/dca_screen.dart';
import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// 100 € a month in the world ETF, from the end of 2015 to September 2026:
// the monthly closes in euros frozen in the Actions & ETF pack, the Livret A
// on its real rates. Euro prices, so no currency fee.

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);
Decimal d(String s) => Decimal.parse(s);

final world = Asset(
  id: 'world',
  symbol: 'ACWI',
  name: 'ETF Monde',
  type: AssetType.etf,
  exchange: Exchange.nasdaq,
  currency: Currency.eur,
  region: 'world',
  listingDate: day(2008, 3, 28),
);

DcaResult result() {
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );
  final bars = [
    for (final (date, close) in pack.datasets['ds.acwi-eur-2016-m']!.points)
      PriceBar(
        date: date,
        open: close,
        high: close,
        low: close,
        close: close,
        volume: 0,
        currency: Currency.eur,
      ),
  ];
  final rules = TradingRules(
    fxFeeRate: d('0.0015'),
    fixedFee: const Money.zero(Currency.eur),
    fractionalShares: true,
  );
  final flows = [
    for (final b in bars) Flow(b.date, const Money(10000, Currency.eur)),
  ];
  final dca = investFlows(
    flows,
    bars: bars,
    fxRate: (_) => Decimal.one,
    rules: rules,
    end: bars.last.date,
  );
  final lumpSum = investFlows(
    [Flow(bars.first.date, dca.invested)],
    bars: bars,
    fxRate: (_) => Decimal.one,
    rules: rules,
    end: bars.last.date,
  );
  final livret = livretFlows(
    flows,
    rates: [
      for (final (from, rate) in [
        (day(2015, 8, 1), '0.0075'),
        (day(2020, 2, 1), '0.005'),
        (day(2022, 2, 1), '0.01'),
        (day(2022, 8, 1), '0.02'),
        (day(2023, 2, 1), '0.03'),
        (day(2025, 2, 1), '0.024'),
        (day(2025, 8, 1), '0.017'),
        (day(2026, 2, 1), '0.015'),
        (day(2026, 8, 1), '0.017'),
      ])
        LivretRate(from, d(rate)),
    ],
    ceilings: [
      LivretCeiling(day(2013, 1, 1), const Money(2295000, Currency.eur)),
    ],
    dates: [for (final v in dca.series) v.date],
  );
  final params = DcaParams(
    assetId: 'world',
    amount: const Money(10000, Currency.eur),
    frequency: DcaFrequency.monthly,
    start: bars.first.date,
  );
  return DcaResult(
    params: params,
    asset: world,
    end: bars.last.date,
    dca: dca,
    lumpSum: lumpSum,
    livret: livret,
    insight: dcaInsight(
      dca: dca,
      lumpSum: lumpSum,
      endPrice: Price(bars.last.close, Currency.eur),
    ),
  );
}

void main() {
  final r = result();
  final overrides = [
    dcaFormViewProvider.overrideWith(
      (ref) async => DcaFormView(
        form: ref.watch(dcaFormControllerProvider),
        assets: [world],
        years: 10,
        start: StartOk(r.params.start),
        amountErrors: const [],
        params: r.params,
      ),
    ),
    dcaRunProvider.overrideWith((ref, p) async => r),
  ];

  screenshot('m8-2-dca-form', const DcaScreen(), overrides: overrides);

  screenshot(
    'm8-2-dca-result',
    const DcaScreen(),
    size: const Size(390, 1500),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('Simuler'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -560));
      await tester.pumpAndSettle();
    },
  );
}
