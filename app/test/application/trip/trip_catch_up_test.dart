import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_catch_up.dart';
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
  late AppDatabase db;
  late ProviderContainer container;
  late WalletRepository wallets;
  late FakeBackend backend;
  late WallClock wall;

  // Nasdaq, October 2026: closes at 20:00 UTC (21:00 from 2 November). The
  // data covers Monday 5 to Wednesday 7; Thursday 8 has not opened yet.
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
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
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> createTrip(
    String id, {
    StopConditions stops = const StopConditions(),
    Money contribution = const Money.zero(Currency.eur),
  }) async {
    await wallets.createWallet(
      id: id,
      kind: WalletKind.trip,
      name: id,
      startDate: day(2026, 10, 5),
      startingCash: const Money(1000000, Currency.eur),
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: Decimal.zero,
          fixedFee: const Money.zero(Currency.eur),
          fractionalShares: true,
        ),
        monthlyContribution: contribution,
        stops: stops,
      ),
      createdAt: wall.now(),
    );
    container.listen(tripRunnerProvider(id), (_, _) {});
  }

  /// Moves trip [id] by [step] with its time controls.
  Future<void> step(String id, TripStep step) =>
      container.read(tripRunnerProvider(id).notifier).advance(step);

  /// Trip [id] at today: on Wednesday 7, the last closed session.
  Future<void> atToday(String id) async {
    await step(id, TripStep.month);
    expect((await wallets.load(id)).reachedToday, isTrue);
  }

  /// The sessions from [from] to [to] closed: their bars are served.
  void sessionsClose(DateTime from, DateTime to) {
    for (var t = from; !t.isAfter(to); t = t.add(const Duration(days: 1))) {
      if (t.weekday > 5) continue;
      final key = t.toIso8601String().substring(0, 10);
      backend.closes['world']![key] = '53';
      backend.closes['apple']![key] = '103';
    }
  }

  Future<void> catchUp([String? walletId]) =>
      container.read(tripCatchUpProvider.notifier).run(walletId);

  Order buy(String id, {Price? limit, DateTime? createdAt}) => Order(
    id: id,
    assetId: 'apple',
    side: Side.buy,
    type: limit == null ? OrderType.market : OrderType.limit,
    size: QuantitySize(Quantity.whole(10)),
    limitPrice: limit,
    createdAt: createdAt ?? day(2026, 10, 7),
  );

  test('a trip behind today stays where it is', () async {
    await createTrip('trip');
    await step('trip', TripStep.day);
    sessionsClose(day(2026, 10, 8), day(2026, 10, 8));
    wall.t = DateTime.utc(2026, 10, 8, 21);

    await catchUp();
    final trip = await wallets.load('trip');
    expect((trip.simDate, trip.reachedToday), (day(2026, 10, 6), false));
    expect(trip.values, hasLength(2));
  });

  test('at today with no new session: nothing moves', () async {
    await createTrip('trip');
    await atToday('trip');
    // Thursday 19:00 UTC: its session is still open.
    wall.t = DateTime.utc(2026, 10, 8, 19);

    await catchUp();
    expect(container.read(tripCatchUpProvider).hasError, isFalse);
    final trip = await wallets.load('trip');
    expect(trip.simDate, day(2026, 10, 7));
    expect(trip.values, hasLength(3));
  });

  test('sessions closed since: the trip goes to the last one, its order fills '
      'and its contribution arrives', () async {
    await createTrip('monthly', contribution: const Money(20000, Currency.eur));
    await createTrip('other');
    await atToday('monthly');
    await atToday('other');
    await wallets.placeOrder('monthly', buy('o1'));
    sessionsClose(day(2026, 10, 8), day(2026, 11, 2));
    // Monday 2 November 22:00 UTC: Nasdaq (winter time) closed at 21:00.
    wall.t = DateTime.utc(2026, 11, 2, 22);

    // The trip's pull-to-refresh: that trip only.
    await catchUp('monthly');
    final trip = await wallets.load('monthly');
    expect(trip.simDate, day(2026, 11, 2));
    expect((trip.status, trip.reachedToday), (WalletStatus.active, true));
    final detail = (await wallets.orderDetail('o1'))!;
    expect(detail.status, OrderStatus.filled);
    expect(detail.fill!.date, day(2026, 10, 8));
    expect(trip.values.last.date, day(2026, 11, 2));
    expect(trip.values.last.flow, const Money(20000, Currency.eur));
    expect((await wallets.load('other')).simDate, day(2026, 10, 7));

    // At launch: every trip at today.
    await catchUp();
    expect((await wallets.load('other')).simDate, day(2026, 11, 2));
    expect(
      (await wallets.load('monthly')).values,
      hasLength(trip.values.length),
    );
  });

  test('an order placed during a session waits for the next one', () async {
    // The live wallet's rule (M4-6): Thursday's session opened at 13:30 UTC,
    // before the order, and its prices were known when it was placed.
    await createTrip('trip');
    await atToday('trip');
    wall.t = DateTime.utc(2026, 10, 8, 15);
    await wallets.placeOrder('trip', buy('o3', createdAt: wall.now()));
    sessionsClose(day(2026, 10, 8), day(2026, 10, 9));
    wall.t = DateTime.utc(2026, 10, 9, 22);

    await catchUp();
    expect((await wallets.orderDetail('o3'))!.fill!.date, day(2026, 10, 9));
  });

  test('a stop during the catch-up stops the trip on its day', () async {
    await createTrip('trip', stops: const StopConditions(orderFilled: true));
    await atToday('trip');
    await wallets.placeOrder(
      'trip',
      buy('o1', limit: Price(d('103.5'), Currency.usd)),
    );
    sessionsClose(day(2026, 10, 8), day(2026, 10, 9));
    wall.t = DateTime.utc(2026, 10, 9, 21);

    await catchUp();
    var trip = await wallets.load('trip');
    expect(
      (trip.simDate, trip.status),
      (day(2026, 10, 8), WalletStatus.stopped),
    );
    expect(trip.stopReasons.single, isA<OrderFilledStop>());

    // Stopped, it waits for the user's decision.
    await catchUp();
    trip = await wallets.load('trip');
    expect(trip.simDate, day(2026, 10, 8));
  });

  test('offline: nothing moves, the failure stays in the state', () async {
    await createTrip('trip');
    await atToday('trip');
    sessionsClose(day(2026, 10, 8), day(2026, 10, 8));
    wall.t = DateTime.utc(2026, 10, 8, 21);
    backend.offline = true;

    await catchUp();
    expect(container.read(tripCatchUpProvider).hasError, isTrue);
    final trip = await wallets.load('trip');
    expect(
      (trip.simDate, trip.status),
      (day(2026, 10, 7), WalletStatus.active),
    );
    expect(trip.values, hasLength(3));
  });

  test('a finished trip stays finished', () async {
    await createTrip('trip');
    await atToday('trip');
    await wallets.finish('trip');
    sessionsClose(day(2026, 10, 8), day(2026, 10, 8));
    wall.t = DateTime.utc(2026, 10, 8, 21);

    await catchUp();
    final trip = await wallets.load('trip');
    expect(
      (trip.simDate, trip.status),
      (day(2026, 10, 7), WalletStatus.finished),
    );
  });
}
