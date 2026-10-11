import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/live_catch_up.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/fake_frankfurter.dart';

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);
Decimal d(String s) => Decimal.parse(s);

void main() {
  late AppDatabase db;
  late WallClock wall;
  late FakeBackend backend;
  late ProviderContainer container;
  late WalletRepository wallets;
  const live = WalletRepository.liveWalletId;

  // Nasdaq, October 2026 (New York on summer time): 13:30 to 20:00 UTC.
  // Apple and the world ETF close at 100/101/102 and 50/51/52 from Monday
  // 5 to Wednesday 7; the fake's bars open where they close.
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Thursday 8, before the open: Wednesday is the last closed session.
    wall = WallClock(DateTime.utc(2026, 10, 8, 12));
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
    container = ProviderContainer(
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
    wallets = WalletRepository(db);
    // Created on Monday 5 during the session.
    await wallets.ensureLiveWallet(DateTime.utc(2026, 10, 5, 15));
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> run() => container.read(liveCatchUpProvider.notifier).run();

  Order buy(String id, DateTime createdAt, {Price? limit}) => Order(
    id: id,
    assetId: 'apple',
    side: Side.buy,
    type: limit == null ? OrderType.market : OrderType.limit,
    size: QuantitySize(Quantity.whole(10)),
    limitPrice: limit,
    createdAt: createdAt,
  );

  test('a market order sent after the close fills at the next open', () async {
    // Monday 21:00 UTC: Nasdaq closed at 20:00.
    await wallets.placeOrder(live, buy('o1', DateTime.utc(2026, 10, 5, 21)));
    await run();

    final detail = (await wallets.orderDetail('o1'))!;
    expect(detail.status, OrderStatus.filled);
    expect(detail.fill!.date, day(2026, 10, 6));
    expect(detail.fill!.price, Price(d('101'), Currency.usd));
    final wallet = await wallets.load(live);
    expect(wallet.positions['apple']!.quantity, Quantity.whole(10));
    expect(wallet.pendingOrders, isEmpty);
  });

  test('a limit set mid-session waits for the next session', () async {
    // Tuesday 15:00 UTC, Nasdaq open: Tuesday's bar (101) already crossed
    // the limit, but that session's prices came before the order.
    await wallets.placeOrder(
      live,
      buy(
        'o2',
        DateTime.utc(2026, 10, 6, 15),
        limit: Price(d('105'), Currency.usd),
      ),
    );
    await run();

    final detail = (await wallets.orderDetail('o2'))!;
    expect(detail.status, OrderStatus.filled);
    expect(detail.fill!.date, day(2026, 10, 7));
    expect(detail.fill!.price, Price(d('102'), Currency.usd));
  });

  test(
    'each closed session gets its value; a second run changes nothing',
    () async {
      await run();
      final values = (await wallets.load(live)).values;
      expect(
        [for (final v in values) v.date],
        [day(2026, 10, 5), day(2026, 10, 6), day(2026, 10, 7)],
      );
      expect(values.last.value, const Money(5000000, Currency.eur));
      expect(values.last.flow.isZero, isTrue);
      expect(container.read(liveCatchUpProvider).value, isNotNull);

      await run();
      expect((await wallets.load(live)).values, hasLength(3));
      expect(container.read(liveCatchUpProvider).value, isNull);
    },
  );

  test('two runs at once book the sessions once', () async {
    await wallets.placeOrder(live, buy('o1', DateTime.utc(2026, 10, 5, 21)));
    await Future.wait([run(), run()]);
    // The second run waits out the first instead of booking it again.
    expect(container.read(liveCatchUpProvider).hasError, isFalse);
    final wallet = await wallets.load(live);
    expect(wallet.values, hasLength(3));
    expect(wallet.positions['apple']!.quantity, Quantity.whole(10));
  });

  test('a session still open is left for later', () async {
    // Wednesday 19:00 UTC: Nasdaq closes at 20:00.
    wall.t = DateTime.utc(2026, 10, 7, 19);
    await wallets.placeOrder(
      live,
      buy(
        'o2',
        DateTime.utc(2026, 10, 6, 15),
        limit: Price(d('105'), Currency.usd),
      ),
    );
    await run();
    final wallet = await wallets.load(live);
    expect([for (final v in wallet.values) v.date].last, day(2026, 10, 6));
    expect(wallet.pendingOrders.single.id, 'o2');
  });

  test(
    'offline: nothing is booked and the failure stays in the state',
    () async {
      await wallets.placeOrder(live, buy('o1', DateTime.utc(2026, 10, 5, 21)));
      backend.offline = true;
      await run();
      expect(container.read(liveCatchUpProvider).hasError, isTrue);
      final wallet = await wallets.load(live);
      expect(wallet.values, hasLength(1));
      expect(wallet.pendingOrders.single.id, 'o1');
    },
  );
}
