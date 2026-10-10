import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/asset/asset_page.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/market/quote.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/fake_frankfurter.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);

final apple = Asset(
  id: 'apple',
  symbol: 'AAPL',
  name: 'Apple',
  type: AssetType.stock,
  exchange: Exchange.nasdaq,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(1980),
);

/// Weekday closes from [from] to [to].
List<PriceBar> bars(
  DateTime from,
  DateTime to,
  Decimal Function(DateTime) close,
) => [
  for (var t = from; !t.isAfter(to); t = t.add(const Duration(days: 1)))
    if (t.weekday <= 5)
      PriceBar(
        date: t,
        open: close(t),
        high: close(t),
        low: close(t),
        close: close(t),
        volume: 1,
        currency: Currency.usd,
      ),
];

/// Apple: 100 $ until 2026, 150 $ in 2026, except a dip to 120 $ in May.
Decimal appleClose(DateTime t) => t.year < 2026
    ? d('100')
    : t.month == 5
    ? d('120')
    : d('150');

/// The world ETF: 50 $, then 55 $ in 2026.
Decimal worldClose(DateTime t) => t.year < 2026 ? d('50') : d('55');

/// 0,90 €/$ until 2026, 0,85 after.
Decimal fx(DateTime t) => t.year < 2026 ? d('0.9') : d('0.85');

Fill buy(DateTime date, String qty, String price, String rate) => Fill(
  assetId: 'apple',
  side: Side.buy,
  date: date,
  quantity: Quantity.truncate(d(qty)),
  price: Price(d(price), Currency.usd),
  fxRate: d(rate),
  fees: const Money.zero(Currency.eur),
);

WalletState wallet(List<Fill> fills) => WalletState(
  id: 'live',
  kind: WalletKind.live,
  name: 'live',
  startDate: day(2026, 1, 1),
  simDate: null,
  status: WalletStatus.active,
  params: WalletParams(
    rules: TradingRules(
      fxFeeRate: Decimal.zero,
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
);

void main() {
  final history = bars(day(2021, 9, 1), day(2026, 10, 7), appleClose);
  final world = bars(day(2021, 9, 1), day(2026, 10, 7), worldClose);
  final fills = [
    buy(day(2026, 3, 2), '10', '100', '0.9'),
    buy(day(2026, 6, 1), '5', '120', '0.85'),
  ];
  final asOf = DateTime.utc(2026, 10, 8, 15);
  final quote = Quote(
    Price(d('200'), Currency.usd),
    DateTime.utc(2026, 10, 8, 14, 45),
    marketOpen: true,
  );

  AssetOverview overview({Quote? live, DateTime? at}) => buildAssetOverview(
    asset: apple,
    wallet: wallet(fills),
    asOf: at ?? asOf,
    bars: history,
    benchmark: world,
    quote: live,
    closeObservedAt: DateTime.utc(2026, 10, 7, 20),
    fx: fx,
    uiLevel: 1,
  );

  group('overview', () {
    test('a live quote: its time, and the move since the last close', () {
      final o = overview(live: quote);
      expect(o.price.value, d('200'));
      expect(o.observedAt, quote.asOf);
      expect(o.fxRate, d('0.85'));
      expect(o.sessionChange, ratio(d('50'), d('150')));
    });

    test('no quote: the last close, moved from the one before', () {
      final o = overview();
      expect(o.price.value, d('150'));
      expect(o.observedAt, DateTime.utc(2026, 10, 7, 20));
      expect(o.sessionChange, Decimal.zero);
    });

    test('a year: performance, volatility, worst drop, the dollar', () {
      final o = overview(live: quote);
      expect(o.yearChange, d('1')); // 100 $ → 200 $
      expect(o.yearDrawdown.depth, d('-0.2')); // 150 $ → 120 $ in May
      expect(o.yearDrawdown.troughDate!.month, 5);
      expect(o.volatility, isNotNull);
      expect(o.fxYearChange, simpleReturn(d('0.9'), d('0.85')));
    });

    test('the position: value, P&L and the part the dollar made', () {
      final p = overview(live: quote).position!;
      expect(p.quantity, Quantity.whole(15));
      expect(p.value, d('2550')); // 15 × 200 $ × 0,85
      expect(p.pnl, d('1140')); // paid 900 € + 510 €
      expect(p.pnlRatio, ratio(d('1140'), d('1410')));
      // Bought at 1 410 € for 1 600 $ (0,88125 €/$ on average).
      expect(p.currencyEffect, d('-93.75'));
    });

    test('no shares, no position block', () {
      final o = buildAssetOverview(
        asset: apple,
        wallet: wallet(const []),
        asOf: asOf,
        bars: history,
        benchmark: world,
        quote: null,
        closeObservedAt: null,
        fx: fx,
        uiLevel: 1,
      );
      expect(o.position, isNull);
      expect(o.buys, isEmpty);
    });

    test('a trip in 2000: no rate a year back, so no dollar move', () {
      final early = bars(day(2000, 1, 3), day(2000, 6, 1), (_) => d('100'));
      final o = buildAssetOverview(
        asset: apple,
        wallet: wallet(const []),
        asOf: day(2000, 6, 1),
        bars: early,
        benchmark: early,
        quote: null,
        closeObservedAt: null,
        fx: (t) => t.isBefore(day(2000, 1, 3))
            ? throw DataUnavailableFailure(t)
            : d('1.01'),
        uiLevel: 1,
      );
      expect(o.fxYearChange, isNull);
      expect(o.yearChange, isNull);
      expect(
        assetChartFor(o, AssetPeriod.fiveYears).dates.first,
        day(2000, 1, 3),
      );
    });

    test('nothing known: data unavailable', () {
      expect(
        () => buildAssetOverview(
          asset: apple,
          wallet: wallet(const []),
          asOf: asOf,
          bars: const [],
          benchmark: world,
          quote: null,
          closeObservedAt: null,
          fx: fx,
          uiLevel: 1,
        ),
        throwsA(isA<DataUnavailableFailure>()),
      );
    });
  });

  group('chart', () {
    final o = overview(live: quote);

    test('periods open on the last close before them', () {
      expect(assetChartFor(o, AssetPeriod.week).dates.first, day(2026, 10, 1));
      expect(assetChartFor(o, AssetPeriod.month).dates.first, day(2026, 9, 8));
      expect(assetChartFor(o, AssetPeriod.year).dates.first, day(2025, 10, 8));
      expect(
        assetChartFor(o, AssetPeriod.fiveYears).dates.first,
        day(2021, 10, 8),
      );
    });

    test('buys sit on the chart day of the fill, at its price', () {
      final year = assetChartFor(o, AssetPeriod.year);
      expect(
        [for (final b in year.buys) year.dates[b.index]],
        [day(2026, 3, 2), day(2026, 6, 1)],
      );
      expect([for (final b in year.buys) b.price], [d('100'), d('120')]);
      expect(assetChartFor(o, AssetPeriod.month).buys, isEmpty);
    });

    test('the worst drop of the period', () {
      expect(assetChartFor(o, AssetPeriod.year).drawdown.depth, d('-0.2'));
      expect(assetChartFor(o, AssetPeriod.week).drawdown.depth, Decimal.zero);
    });

    test('the world ETF rebased to the first close, on demand', () {
      expect(assetChartFor(o, AssetPeriod.year).benchmark, isNull);
      final chart = assetChartFor(o, AssetPeriod.year, benchmark: true);
      expect(chart.benchmark!.first, chart.closes.first);
      // +10 % for the ETF in 2026: 100 $ → 110 $.
      expect(chart.benchmark!.last, d('110'));
    });

    test('why it moved: the market, the dollar, the rest', () {
      final m = assetChartFor(o, AssetPeriod.year).decomposition!;
      expect(m.local, d('1')); // 100 $ → 200 $
      expect(m.market, d('0.1')); // 50 $ → 55 $
      expect(m.currency, simpleReturn(d('0.9'), d('0.85')));
      expect(m.market + m.currency + m.specific, m.total);
    });
  });

  group('provider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final wall = WallClock(DateTime.utc(2026, 10, 8, 12));
      final backend = FakeBackend()
        ..assets.add({
          'id': 'world',
          'symbol': 'ACWI',
          'name': 'iShares MSCI ACWI ETF',
          'type': 'etf',
          'exchange': 'nasdaq',
          'currency': 'USD',
          'region': 'world',
          'listingDate': '2008-03-28',
        })
        ..closes['world'] = {
          '2026-10-05': '50',
          '2026-10-06': '51',
          '2026-10-07': '52',
        };
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          liveClockProvider.overrideWithValue(wall),
          marketRepositoryProvider.overrideWithValue(
            MarketRepository(
              db,
              BackendApi('http://backend.test', adapter: backend),
              wallClock: wall,
            ),
          ),
          fxServiceProvider.overrideWithValue(
            FxService(
              db,
              FrankfurterApi(adapter: FakeFrankfurter()),
              wallClock: wall,
            ),
          ),
        ],
      );
      await WalletRepository(db).ensureLiveWallet(wall.now());
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('the live wallet scope: last close, rate, no position', () async {
      final o = await container.read(
        assetOverviewProvider('apple', null).future,
      );
      expect(o.walletId, 'live');
      expect(o.price.value, d('102'));
      expect(o.fxRate, d('0.8547'));
      expect(o.observedAt, DateTime.utc(2026, 10, 7, 20));
      expect(o.position, isNull);
      expect(o.uiLevel, 1);
      final chart = await container.read(
        assetChartProvider('apple', null, AssetPeriod.week, true).future,
      );
      expect(chart.dates, hasLength(3));
      expect(chart.benchmark!.first, d('100'));
    });

    test('an unknown asset is not found', () async {
      await expectLater(
        container.read(assetOverviewProvider('nope', null).future),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });
}
