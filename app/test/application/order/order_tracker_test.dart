import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/order/order_tracker.dart';
import 'package:finance_companion/application/providers.dart';
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
import 'package:finance_companion/domain/wallet/order_matcher.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/fake_frankfurter.dart';

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  late AppDatabase db;
  late WallClock wall;
  late ProviderContainer c;
  late WalletRepository wallets;
  const live = WalletRepository.liveWalletId;

  // Nasdaq opens at 13:30 UTC in October 2026.
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    wall = WallClock(DateTime.utc(2026, 10, 8, 12));
    final backend = FakeBackend();
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(wall),
        marketRepositoryProvider.overrideWithValue(
          MarketRepository(
            db,
            BackendApi('http://t', adapter: backend),
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
    wallets = c.read(walletRepositoryProvider);
    await wallets.ensureLiveWallet(DateTime.utc(2026, 10, 5, 9));
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Order buy(String id, {DateTime? at, Price? limit}) => Order(
    id: id,
    assetId: 'apple',
    side: Side.buy,
    type: limit == null ? OrderType.market : OrderType.limit,
    size: AmountSize(const Money(50000, Currency.eur)),
    limitPrice: limit,
    createdAt: at ?? DateTime.utc(2026, 10, 7, 21),
  );

  Future<OrderView> view(String id) {
    c.listen(orderTrackerProvider(id), (_, _) {});
    return c.read(orderTrackerProvider(id).future);
  }

  test('a market order sent after the close waits for the next open', () async {
    await wallets.placeOrder(live, buy('o1'));
    final v = await view('o1');
    expect(v.detail.status, OrderStatus.pending);
    expect(v.asset.id, 'apple');
    expect(v.trip, isFalse);
    expect(v.opensAt, DateTime.utc(2026, 10, 8, 13, 30));
    expect(v.opened, isFalse);
  });

  test('once its session opened, it waits for the close', () async {
    wall.t = DateTime.utc(2026, 10, 8, 14);
    await wallets.placeOrder(live, buy('o1'));
    final v = await view('o1');
    expect(v.opensAt, DateTime.utc(2026, 10, 8, 13, 30));
    expect(v.opened, isTrue);
  });

  test('a limit order waits for its price, not for an open', () async {
    await wallets.placeOrder(
      live,
      buy('o2', limit: Price(Decimal.parse('90'), Currency.usd)),
    );
    final v = await view('o2');
    expect(v.opensAt, isNull);
    expect(v.opened, isFalse);
  });

  test('a market order filled at the quote has no open to wait for', () async {
    final order = buy('o3', at: DateTime.utc(2026, 10, 7, 15));
    await wallets.executeOrder(
      live,
      order,
      Fill(
        orderId: 'o3',
        assetId: 'apple',
        side: Side.buy,
        date: DateTime.utc(2026, 10, 7, 15),
        quantity: Quantity.whole(4),
        price: Price(Decimal.parse('125'), Currency.usd),
        fxRate: Decimal.parse('0.9'),
        fees: const Money(68, Currency.eur),
      ),
    );
    final v = await view('o3');
    expect(v.detail.status, OrderStatus.filled);
    expect(v.detail.fill!.quantity, Quantity.whole(4));
    expect(v.opensAt, isNull);
  });

  test('a trip order goes when the trip moves on', () async {
    await wallets.createWallet(
      id: 'trip',
      kind: WalletKind.trip,
      name: 'Octobre',
      startDate: day(2026, 10, 5),
      startingCash: const Money(1000000, Currency.eur),
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: Decimal.zero,
          fixedFee: const Money.zero(Currency.eur),
          fractionalShares: true,
        ),
        monthlyContribution: const Money.zero(Currency.eur),
        stops: const StopConditions(),
      ),
      createdAt: wall.now(),
    );
    await wallets.placeTripOrder(
      'trip',
      buy('t1', at: day(2026, 10, 5)),
      simDate: day(2026, 10, 5),
    );
    final v = await view('t1');
    expect(v.trip, isTrue);
    expect(v.opensAt, isNull);
  });

  test('cancelling frees what the order held back', () async {
    await wallets.placeOrder(live, buy('o1'));
    c.listen(walletOverviewProvider(live), (_, _) {});
    expect((await c.read(walletOverviewProvider(live).future)).pendingOrders, [
      isA<({Order order, dynamic asset})>().having(
        (p) => p.order.id,
        'id',
        'o1',
      ),
    ]);
    await view('o1');

    await c.read(orderTrackerProvider('o1').notifier).cancel();
    final v = await c.read(orderTrackerProvider('o1').future);
    expect(v.detail.status, OrderStatus.cancelled);
    expect(v.detail.cancelReason, CancelReason.byUser);
    final overview = await c.read(walletOverviewProvider(live).future);
    expect(overview.pendingOrders, isEmpty);
    expect(overview.availableCash, const Money(5000000, Currency.eur));
  });

  test('an order filled in the meantime stays filled', () async {
    await wallets.placeOrder(live, buy('o1'));
    await view('o1');
    await wallets.recordFill(
      live,
      buy('o1'),
      Fill(
        orderId: 'o1',
        assetId: 'apple',
        side: Side.buy,
        date: day(2026, 10, 8),
        quantity: Quantity.whole(4),
        price: Price(Decimal.parse('125'), Currency.usd),
        fxRate: Decimal.parse('0.9'),
        fees: const Money(68, Currency.eur),
      ),
    );
    await c.read(orderTrackerProvider('o1').notifier).cancel();
    final v = await c.read(orderTrackerProvider('o1').future);
    expect(v.detail.status, OrderStatus.filled);
  });

  test('an unknown order is not found', () async {
    c.listen(orderTrackerProvider('nope'), (_, _) {});
    await expectLater(
      c.read(orderTrackerProvider('nope').future),
      throwsA(isA<NotFoundFailure>()),
    );
  });
}
