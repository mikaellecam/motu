import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/missions.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';

DateTime day(int d) => DateTime.utc(2026, 10, d);

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  late WalletRepository wallets;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final wall = WallClock(DateTime.utc(2026, 10, 11, 9));
    final backend = FakeBackend()
      ..assets.add({
        ...FakeBackend().assets.first,
        'id': 'world',
        'type': 'etf',
        'region': 'world',
      });
    c = ProviderContainer(
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
      ],
    );
    wallets = c.read(walletRepositoryProvider);
    await wallets.ensureLiveWallet(wall.now());
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<void> buy(String asset) async {
    final order = Order(
      id: 'buy-$asset',
      assetId: asset,
      side: Side.buy,
      type: OrderType.market,
      size: QuantitySize(Quantity.whole(1)),
      createdAt: day(5),
    );
    await wallets.placeOrder('live', order);
    await wallets.recordFill(
      'live',
      order,
      Fill(
        assetId: asset,
        side: Side.buy,
        date: day(5),
        quantity: Quantity.whole(1),
        price: Price(Decimal.fromInt(100), Currency.usd),
        fxRate: Decimal.parse('0.9'),
        fees: const Money.zero(Currency.eur),
      ),
    );
  }

  Future<Map<String, int>> attempts() async => {
    for (final r in await db.learningDao.progress()) r.nodeId: r.attempts,
  };

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('missions complete by themselves, once each', () async {
    c.listen(missionTrackerProvider, (_, _) {});
    await settle();
    expect(await attempts(), isEmpty);

    // A stock is not an ETF.
    await buy('apple');
    await settle();
    expect(await attempts(), isEmpty);

    await buy('world');
    await settle();
    expect(await attempts(), {'ae.mission-first-etf': 1});

    await wallets.savePlan(
      'live',
      DcaPlan(
        id: 'p1',
        assetId: 'world',
        amount: Money.book(Decimal.fromInt(100), Currency.eur),
        frequency: DcaFrequency.monthly,
        start: day(12),
      ),
    );
    await settle();
    // The ETF mission is not saved again.
    expect(await attempts(), {'ae.mission-first-etf': 1, 'ae.mission-dca': 1});
  });

  test('what the sandbox satisfies right now', () async {
    c.listen(satisfiedMissionsProvider, (_, _) {});
    await buy('world');
    await settle();
    expect(await c.read(satisfiedMissionsProvider.future), {
      'ae.mission-first-etf',
    });
  });
}
