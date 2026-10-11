import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/fake_frankfurter.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int m, int dd) => DateTime.utc(2026, m, dd);

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late WallClock wall;
  late ProviderContainer container;
  late WalletRepository wallets;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend()
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
    // Thursday 2026-10-08, 08:00 in New York.
    wall = WallClock(DateTime.utc(2026, 10, 8, 12));
    container = ProviderContainer(
      // A failure surfaces as is instead of being retried.
      retry: (_, _) => null,
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
    wallets = container.read(walletRepositoryProvider);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Buys 10 Apple at 100 $ on 2026-10-05 (0,85251 €/$, no fee).
  Future<void> buyApple(String walletId) async {
    final order = Order(
      id: 'o-$walletId',
      assetId: 'apple',
      side: Side.buy,
      type: OrderType.market,
      size: QuantitySize(Quantity.whole(10)),
      createdAt: day(10, 5),
    );
    await wallets.placeOrder(walletId, order);
    await wallets.recordFill(
      walletId,
      order,
      Fill(
        assetId: 'apple',
        side: Side.buy,
        date: day(10, 5),
        quantity: Quantity.whole(10),
        price: Price(d('100'), Currency.usd),
        fxRate: d('0.85251'),
        fees: const Money.zero(Currency.eur),
      ),
    );
  }

  test('the live wallet is priced from quotes, today', () async {
    final id = await wallets.ensureLiveWallet(DateTime.utc(2026, 10, 5, 9));
    await buyApple(id);
    backend.quotes['apple'] = {
      'assetId': 'apple',
      'price': '102',
      'currency': 'USD',
      'asOf': '2026-10-07T20:00:00Z',
      'marketOpen': false,
    };

    final o = await container.read(walletOverviewProvider(id).future);
    expect(o.asOf, wall.now());
    // 10 × 102 $ × 0,8547 (the last rate, 10-07).
    expect(o.invested, d('871.794'));
    expect(o.availableCash, Money.book(d('49147.49'), Currency.eur));
    expect(o.total, d('50019.284'));
    expect(o.pricesAsOf, DateTime.utc(2026, 10, 7, 20));
    expect([for (final v in o.series) v.date], [day(10, 5), day(10, 8)]);
  });

  test('a trip is priced from closes on its simulated day', () async {
    await wallets.createWallet(
      id: 'trip',
      kind: WalletKind.trip,
      name: 'Octobre',
      startDate: day(10, 5),
      startingCash: Money.book(d('10000'), Currency.eur),
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: d('0.0015'),
          fixedFee: const Money.zero(Currency.eur),
          fractionalShares: true,
        ),
        monthlyContribution: const Money.zero(Currency.eur),
        stops: const StopConditions(),
      ),
      createdAt: wall.now(),
    );
    await buyApple('trip');

    final o = await container.read(walletOverviewProvider('trip').future);
    expect(o.asOf, day(10, 5));
    // The 10-05 close, 100 $, at that day's 0,85251.
    expect(o.invested, d('852.51'));
    // 16:00 in New York.
    expect(o.pricesAsOf, DateTime.utc(2026, 10, 5, 20));
    expect(backend.to('/v1/quotes'), isEmpty, reason: 'trips never use quotes');
  });

  test('benchmarks receive the same money on the same days', () async {
    final id = await wallets.ensureLiveWallet(DateTime.utc(2026, 10, 5, 9));

    final world = await container.read(
      walletChartProvider(id, ChartPeriod.all, Benchmark.world).future,
    );
    expect(world.dates, [day(10, 5), day(10, 8)]);
    // 50 000 € less the 0,15 % FX fee, bought at the 10-05 close…
    expect(world.benchmark!.first, lessThan(d('50000')));
    expect(world.benchmark!.first, greaterThan(d('49900')));
    // …and worth more after the ETF rose 4 % (in dollars).
    expect(world.benchmark!.last, greaterThan(world.benchmark!.first));

    final livret = await container.read(
      walletChartProvider(id, ChartPeriod.all, Benchmark.livret).future,
    );
    // Deposits earn from the next fortnight: nothing yet.
    expect(livret.benchmark, [d('50000'), d('50000')]);

    final none = await container.read(
      walletChartProvider(id, ChartPeriod.all, null).future,
    );
    expect(none.benchmark, isNull);
    expect(none.moneyIn, [d('50000'), d('50000')]);
  });

  test('a failing read reaches the chart as its own failure', () async {
    // No such wallet: the overview fails, and so does the chart with it.
    for (final benchmark in [null, Benchmark.world]) {
      await expectLater(
        container.read(
          walletChartProvider('nope', ChartPeriod.all, benchmark).future,
        ),
        throwsA(isA<NotFoundFailure>()),
        reason: '$benchmark',
      );
    }
  });
}
