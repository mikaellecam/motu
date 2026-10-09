import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
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
import 'package:finance_companion/domain/wallet/valuation.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(d(s), Currency.eur);
DateTime day(int m, int dd) => DateTime.utc(2026, m, dd);

final rules = TradingRules(
  fxFeeRate: d('0.0015'),
  fixedFee: eur('0'),
  fractionalShares: true,
);

Asset asset(String id, String name) => Asset(
  id: id,
  symbol: id.toUpperCase(),
  name: name,
  type: AssetType.stock,
  exchange: Exchange.nasdaq,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(1990),
);

final assets = {
  'apple': asset('apple', 'Apple'),
  'nvidia': asset('nvidia', 'Nvidia'),
};

Fill buy(String id, String qty, String price) => Fill(
  assetId: id,
  side: Side.buy,
  date: day(10, 1),
  quantity: Quantity.truncate(d(qty)),
  price: Price(d(price), Currency.usd),
  fxRate: d('0.9'),
  fees: eur('0'),
);

WalletState wallet({
  required Money cash,
  List<Fill> fills = const [],
  List<Order> pending = const [],
  required List<DailyValue> values,
}) => WalletState(
  id: 'live',
  kind: WalletKind.live,
  name: 'live',
  startDate: values.first.date,
  simDate: null,
  status: WalletStatus.active,
  params: WalletParams(
    rules: rules,
    monthlyContribution: eur('0'),
    stops: const StopConditions(),
  ),
  cash: cash,
  fills: fills,
  positions: positionsFrom(fills),
  pendingOrders: pending,
  values: values,
  livretMovements: const [],
  plans: const [],
);

DailyValue value(DateTime date, String v, [String flow = '0']) =>
    DailyValue(date: date, value: eur(v), flow: eur(flow));

ObservedPrice quote(String price, DateTime at) => ObservedPrice(
  PriceAsOf(Price(d(price), Currency.usd), day(10, 8), stale: false),
  at,
);

void main() {
  final asOf = DateTime.utc(2026, 10, 8, 15, 30);

  group('overview', () {
    // Bought 10 Apple at 200 $ and 2 Nvidia at 100 $ (0,9 €/$): 1 980 €.
    final fills = [buy('nvidia', '2', '100'), buy('apple', '10', '200')];
    final pendingBuy = Order(
      id: 'o1',
      assetId: 'apple',
      side: Side.buy,
      type: OrderType.limit,
      size: QuantitySize(Quantity.whole(5)),
      limitPrice: Price(d('180'), Currency.usd),
      createdAt: day(10, 7),
    );
    final w = wallet(
      cash: eur('48020'),
      fills: fills,
      pending: [pendingBuy],
      values: [value(day(10, 1), '50000', '50000'), value(day(10, 7), '50100')],
    );
    final prices = {
      'apple': quote('220', DateTime.utc(2026, 10, 8, 15)),
      'nvidia': quote('150', DateTime.utc(2026, 10, 8, 14, 45)),
    };
    final o = buildOverview(
      wallet: w,
      asOf: asOf,
      assets: assets,
      prices: prices,
      fxRates: {Currency.usd: d('0.85')},
      livret: Decimal.zero,
    );

    test('value, Investi as market value, change on the money put in', () {
      // Apple 10 × 220 × 0,85 = 1 870 €; Nvidia 2 × 150 × 0,85 = 255 €.
      expect(o.invested, d('2125'));
      expect(o.total, d('50145'));
      expect(o.moneyIn, eur('50000'));
      expect(o.change, d('145'));
      expect(o.changeRatio, d('0.0029'));
    });

    test('available cash leaves out what pending buys hold back', () {
      final held = cashToReserve(
        pendingBuy,
        rules: rules,
        referencePrice: Price(d('220'), Currency.usd),
        fxRate: d('0.85'),
      );
      expect(held.isPositive, isTrue);
      expect(o.availableCash, eur('48020') - held);
    });

    test('positions and allocation largest first, then cash', () {
      expect([for (final p in o.positions) p.asset.id], ['apple', 'nvidia']);
      expect(o.positions.first.quantity, Quantity.whole(10));
      // 1 870 € for 1 800 € paid.
      expect(o.positions.first.pnlRatio, ratio(d('70'), d('1800')));
      expect(o.allocation, hasLength(3));
      expect((o.allocation[0] as PositionLine).assetId, 'apple');
      expect((o.allocation[1] as PositionLine).assetId, 'nvidia');
      expect(o.allocation[2], isA<CashLine>());
    });

    test('today joins the series with the current value', () {
      expect(
        [for (final v in o.series) v.date],
        [day(10, 1), day(10, 7), day(10, 8)],
      );
      expect(o.series.last.value, eur('50145'));
      expect(o.series.last.flow, eur('0'));
    });

    test('the prices date from the oldest one shown', () {
      expect(o.pricesAsOf, DateTime.utc(2026, 10, 8, 14, 45));
    });
  });

  test('a day already stored is replaced, its flow kept', () {
    final o = buildOverview(
      wallet: wallet(
        cash: eur('50000'),
        values: [value(day(10, 8), '50000', '50000')],
      ),
      asOf: asOf,
      assets: assets,
      prices: const {},
      fxRates: const {},
      livret: Decimal.zero,
    );
    expect(o.series, hasLength(1));
    expect(o.series.single.flow, eur('50000'));
    expect(o.pricesAsOf, isNull);
    expect(o.invested, Decimal.zero);
    expect(o.change, Decimal.zero);
    expect(o.changeRatio, Decimal.zero);
    expect(o.allocation.single, isA<CashLine>());
  });

  test('with contributions the change is time-weighted', () {
    // +10 % on day 2, then 100 € more on day 3 and no move.
    final o = buildOverview(
      wallet: wallet(
        cash: eur('1200'),
        values: [
          value(day(10, 1), '1000', '1000'),
          value(day(10, 2), '1100'),
          value(day(10, 8), '1200', '100'),
        ],
      ),
      asOf: asOf,
      assets: assets,
      prices: const {},
      fxRates: const {},
      livret: Decimal.zero,
    );
    expect(o.moneyIn, eur('1100'));
    expect(o.change, d('100'));
    expect(o.changeRatio, d('0.1'));
  });

  test('values dated after asOf are left out', () {
    final o = buildOverview(
      wallet: wallet(
        cash: eur('1000'),
        values: [value(day(10, 1), '1000', '1000'), value(day(10, 9), '5000')],
      ),
      asOf: asOf,
      assets: assets,
      prices: const {},
      fxRates: const {},
      livret: Decimal.zero,
    );
    expect([for (final v in o.series) v.date], [day(10, 1), day(10, 8)]);
  });

  test('the Livret is a line of its own', () {
    final o = buildOverview(
      wallet: wallet(
        cash: eur('900'),
        values: [value(day(10, 1), '1000', '1000')],
      ),
      asOf: asOf,
      assets: assets,
      prices: const {},
      fxRates: const {},
      livret: d('100.25'),
    );
    expect(o.total, d('1000.25'));
    expect(o.allocation.last, isA<LivretLine>());
  });

  group('chart', () {
    // Every day from 1 September to 8 October; 500 € more on 1 October.
    final series = [
      for (
        var t = DateTime.utc(2026, 9, 1);
        !t.isAfter(day(10, 8));
        t = t.add(const Duration(days: 1))
      )
        value(
          t,
          t == DateTime.utc(2026, 9, 1)
              ? '1000'
              : (t.isBefore(day(10, 1)) ? '1010' : '1520'),
          t == DateTime.utc(2026, 9, 1)
              ? '1000'
              : (t == day(10, 1) ? '500' : '0'),
        ),
    ];

    test('periods count back from the last day, opening the day before', () {
      expect(chartFor(series, ChartPeriod.week).dates.first, day(10, 1));
      expect(chartFor(series, ChartPeriod.month).dates.first, day(9, 8));
      expect(
        chartFor(series, ChartPeriod.year).dates.first,
        DateTime.utc(2026, 9, 1),
      );
      expect(chartFor(series, ChartPeriod.all).dates, hasLength(38));
    });

    test('a period with a missing day opens on the last day before it', () {
      // A new wallet: created on 1 September, valued again today only.
      final sparse = [
        value(DateTime.utc(2026, 9, 1), '1000', '1000'),
        value(day(10, 8), '1100'),
      ];
      final week = chartFor(sparse, ChartPeriod.week);
      expect(week.dates, [DateTime.utc(2026, 9, 1), day(10, 8)]);
      expect(week.values, [d('1000'), d('1100')]);
    });

    test('a month back from the 31st lands on the shorter month\'s end', () {
      final march = [
        value(DateTime.utc(2026, 2, 27), '1', '1'),
        value(DateTime.utc(2026, 2, 28), '1'),
        value(DateTime.utc(2026, 3, 31), '1'),
      ];
      expect(
        chartFor(march, ChartPeriod.month).dates.first,
        DateTime.utc(2026, 2, 28),
      );
    });

    test('the baseline is the money put in so far', () {
      final week = chartFor(series, ChartPeriod.week);
      expect(week.moneyIn.first, d('1500'));
      final month = chartFor(series, ChartPeriod.month);
      expect(month.moneyIn.first, d('1000'));
      final all = chartFor(series, ChartPeriod.all);
      expect(all.moneyIn.first, d('1000'));
      expect(all.moneyIn[29], d('1000'));
      expect(all.moneyIn[30], d('1500'));
      expect(all.values.last, d('1520'));
      expect(all.benchmark, isNull);
    });

    test('a benchmark matches each day with its last point, cash before', () {
      final chart = chartFor(
        series,
        ChartPeriod.all,
        benchmark: [
          ValuePoint(DateTime.utc(2026, 9, 3), d('1001'), eur('1000')),
          ValuePoint(DateTime.utc(2026, 9, 7), d('1004'), eur('1000')),
        ],
      );
      expect(chart.benchmark!.take(8).toList(), [
        d('1000'),
        d('1000'),
        d('1001'),
        d('1001'),
        d('1001'),
        d('1001'),
        d('1004'),
        d('1004'),
      ]);
    });

    test('empty series, empty chart', () {
      expect(chartFor(const [], ChartPeriod.all).dates, isEmpty);
    });
  });

  test('external flows: the starting cash and the contributions', () {
    final flows = externalFlows([
      value(day(10, 1), '1000', '1000'),
      value(day(10, 2), '1100'),
      value(day(10, 3), '1300', '200'),
    ]);
    expect(
      [for (final f in flows) (f.date, f.amount)],
      [(day(10, 1), eur('1000')), (day(10, 3), eur('200'))],
    );
  });
}
