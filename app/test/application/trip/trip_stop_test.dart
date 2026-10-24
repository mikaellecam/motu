import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_stop.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/stop_decision.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/fake_frankfurter.dart';

DateTime day(int d) => DateTime.utc(2026, 10, d);
Decimal dec(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(dec(s), Currency.eur);

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late WalletRepository wallets;
  late FakeBackend backend;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final wall = WallClock(DateTime.utc(2026, 10, 8, 12));
    backend = FakeBackend();
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
      startDate: day(5),
      startingCash: eur('10000'),
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: Decimal.zero,
          fixedFee: const Money.zero(Currency.eur),
          fractionalShares: false,
        ),
        monthlyContribution: const Money.zero(Currency.eur),
        stops: StopConditions(drawdown: dec('0.15'), positionLoss: dec('0.20')),
      ),
      createdAt: day(8),
    );
    // 10 Apple bought on 10-05 at 100 $ (0,85251 €/$).
    final order = Order(
      id: 'o1',
      assetId: 'apple',
      side: Side.buy,
      type: OrderType.market,
      size: QuantitySize(Quantity.whole(10)),
      createdAt: day(5),
    );
    await wallets.placeOrder('trip', order);
    await wallets.recordFill(
      'trip',
      order,
      Fill(
        assetId: 'apple',
        side: Side.buy,
        date: day(5),
        quantity: Quantity.whole(10),
        price: Price(dec('100'), Currency.usd),
        fxRate: dec('0.85251'),
        fees: const Money.zero(Currency.eur),
      ),
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> stopWith(List<StopReason> reasons) async {
    final before = await wallets.tripState('trip', livretRates: const []);
    await wallets.saveAdvance(
      'trip',
      TripAdvance(
        state: before.copyWith(
          date: day(7),
          values: [
            ...before.values,
            DailyValue(date: day(6), value: eur('9000'), flow: eur('0')),
            DailyValue(date: day(7), value: eur('8400'), flow: eur('0')),
          ],
        ),
        events: const [],
        stop: reasons,
        endOfData: false,
      ),
      before: before,
    );
  }

  test('a portfolio drop: the value against its stop line', () async {
    await stopWith(const [
      DrawdownStop(
        value: Money(840000, Currency.eur),
        threshold: Money(850000, Currency.eur),
      ),
    ]);
    final view = await container.read(tripStopProvider('trip').future);
    expect(view.date, day(7));
    expect(view.name, 'Octobre');
    expect(view.dropStop, isTrue);
    // 8 400 € against the 10 000 € put in.
    expect(view.portfolioLoss, dec('-0.16'));
    // 10 000 € − 10 × 100 $ × 0,85251.
    expect(view.cash, eur('9147.49'));
    expect(view.chart!.dates, [day(5), day(6), day(7)]);
    expect(view.chart!.values.last, dec('8400'));
    expect(view.chart!.threshold, [dec('8500'), dec('8500'), dec('8500')]);
    expect(view.chart!.limit, dec('0.15'));
    expect(view.chart!.market, isNull, reason: 'no world ETF in the catalogue');
    expect(stopEventId(view.date), 'stop-2026-10-07');
  });

  test('the world ETF over the same days, in its currency', () async {
    backend.assets.add({...backend.assets.first, 'id': 'world'});
    backend.closes['world'] = {
      '2026-10-05': '50',
      '2026-10-06': '45',
      '2026-10-07': '48',
    };
    await stopWith(const [
      DrawdownStop(
        value: Money(840000, Currency.eur),
        threshold: Money(850000, Currency.eur),
      ),
    ]);
    final view = await container.read(tripStopProvider('trip').future);
    expect(view.chart!.market, dec('-0.04'));
  });

  test('a world ETF listed after the chart starts says nothing', () async {
    backend.assets.add({
      ...backend.assets.first,
      'id': 'world',
      'listingDate': '2026-10-06',
    });
    backend.closes['world'] = {'2026-10-06': '45', '2026-10-07': '48'};
    await stopWith(const [
      DrawdownStop(
        value: Money(840000, Currency.eur),
        threshold: Money(850000, Currency.eur),
      ),
    ]);
    final view = await container.read(tripStopProvider('trip').future);
    expect(view.chart!.market, isNull);
  });

  test('a position drop: that position against cost × 0,8', () async {
    await stopWith([PositionLossStop('apple', dec('-0.21'))]);
    final view = await container.read(tripStopProvider('trip').future);
    expect(view.assetNames['apple'], 'apple');
    final chart = view.chart!;
    expect(chart.dates, [day(5), day(6), day(7)]);
    // 10 × 101 $ × 0,85 on 10-06.
    expect(chart.values[1], dec('858.5'));
    expect(chart.threshold.first, dec('852.51') * dec('0.8'));
    expect(chart.limit, dec('0.20'));
    expect(view.portfolioLoss, isNull);
  });

  test('an order fill names the asset; no chart, no dilemma', () async {
    await stopWith(const [OrderFilledStop('o1')]);
    final view = await container.read(tripStopProvider('trip').future);
    expect(view.assetNames['o1'], 'apple');
    expect(view.chart, isNull);
    expect(view.dropStop, isFalse);
  });

  test(
    'deciding: sells placed, journal written, the trip runs again',
    () async {
      await stopWith(const [
        DrawdownStop(
          value: Money(840000, Currency.eur),
          threshold: Money(850000, Currency.eur),
        ),
      ]);
      container.listen(stopActionsProvider('trip'), (_, _) {});
      await container
          .read(stopActionsProvider('trip').notifier)
          .decide(StopDecision.sellHalf, reason: '  Peur de la suite ');
      final wallet = await wallets.load('trip');
      expect(wallet.status, WalletStatus.active);
      expect(wallet.stopReasons, isEmpty);
      final sell = wallet.pendingOrders.single;
      expect(
        (sell.side, (sell.size as QuantitySize).quantity),
        (Side.sell, Quantity.whole(5)),
      );
      final journal = (await db.walletDao.journalOf('trip')).single;
      expect(
        (journal.decision, journal.reason, journal.eventId),
        ('sell_half', 'Peur de la suite', 'stop-2026-10-07'),
      );
    },
  );

  test('the automatic stops can be changed from the stop', () async {
    container.listen(stopActionsProvider('trip'), (_, _) {});
    await container
        .read(stopActionsProvider('trip').notifier)
        .updateStops(const StopConditions(orderFilled: true));
    final stops = (await wallets.load('trip')).params.stops;
    expect(stops.drawdown, isNull);
    expect(stops.orderFilled, isTrue);
  });
}
