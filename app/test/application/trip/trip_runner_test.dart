import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_runner.dart';
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

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);
Decimal d(String s) => Decimal.parse(s);

void main() {
  group('step targets', () {
    bool tripDay(DateTime t) => t.weekday <= 5 && t != day(2026, 11, 26);

    test('a day: the next trip day', () {
      expect(
        stepTarget(TripStep.day, day(2026, 10, 7), isTripDay: tripDay),
        day(2026, 10, 8),
      );
      expect(
        stepTarget(TripStep.day, day(2026, 10, 9), isTripDay: tripDay),
        day(2026, 10, 12),
        reason: 'Friday',
      );
      expect(
        stepTarget(TripStep.day, day(2026, 11, 25), isTripDay: tripDay),
        day(2026, 11, 27),
        reason: 'holiday',
      );
    });

    test('a week and a month', () {
      expect(
        stepTarget(TripStep.week, day(2026, 10, 9), isTripDay: tripDay),
        day(2026, 10, 16),
      );
      expect(
        stepTarget(TripStep.month, day(2026, 1, 31), isTripDay: tripDay),
        day(2026, 2, 28),
      );
      expect(
        stepTarget(TripStep.month, day(2028, 1, 31), isTripDay: tripDay),
        day(2028, 2, 29),
      );
      expect(
        stepTarget(TripStep.month, day(2026, 12, 15), isTripDay: tripDay),
        day(2027, 1, 15),
      );
    });
  });

  group('runner', () {
    late AppDatabase db;
    late ProviderContainer container;
    late WalletRepository wallets;

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
          stops: const StopConditions(orderFilled: true),
        ),
        createdAt: wall.now(),
      );
      container.listen(tripRunnerProvider('trip'), (_, _) {});
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test(
      'a day: the pending order fills, the day is booked, the trip stops',
      () async {
        // Apple closes at 101 $ on 10-06 (open = close in the fake).
        await wallets.placeOrder(
          'trip',
          Order(
            id: 'o1',
            assetId: 'apple',
            side: Side.buy,
            type: OrderType.limit,
            size: QuantitySize(Quantity.whole(10)),
            limitPrice: Price(d('101.5'), Currency.usd),
            createdAt: day(2026, 10, 5),
          ),
        );
        await container
            .read(tripRunnerProvider('trip').notifier)
            .advance(TripStep.day);
        final advance = container.read(tripRunnerProvider('trip')).value!;
        expect(advance.state.date, day(2026, 10, 6));
        expect(advance.events.whereType<OrderFilled>(), hasLength(1));
        expect(advance.stop.single, isA<OrderFilledStop>());

        final trip = await wallets.load('trip');
        expect(trip.simDate, day(2026, 10, 6));
        expect(trip.status, WalletStatus.stopped);
        expect(trip.positions['apple']!.quantity, Quantity.whole(10));
        expect(
          [for (final v in trip.values) v.date],
          [day(2026, 10, 5), day(2026, 10, 6)],
        );
      },
    );

    test(
      'past the last close: as far as the data goes, then the end',
      () async {
        await container
            .read(tripRunnerProvider('trip').notifier)
            .advance(TripStep.month);
        final advance = container.read(tripRunnerProvider('trip')).value!;
        expect(advance.endOfData, isTrue);
        expect(advance.state.date, day(2026, 10, 7));
        final trip = await wallets.load('trip');
        expect(trip.simDate, day(2026, 10, 7));
        // BRIEF §4.5: the trip ends on the last available trading day.
        expect(trip.status, WalletStatus.finished);
        expect(trip.values, hasLength(3));
      },
    );
  });
}
