import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:finance_companion/domain/livret/livret_interest.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/order_matcher.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String amount) => Money.book(d(amount), Currency.eur);
DateTime day(int m, int dd) => DateTime.utc(2020, m, dd);

final realistic = WalletParams(
  rules: TradingRules(
    fxFeeRate: d('0.0015'),
    fixedFee: eur('0'),
    fractionalShares: true,
  ),
  monthlyContribution: eur('200'),
  stops: StopConditions(drawdown: d('0.15'), orderFilled: true),
  difficulty: 'realiste',
);

Order buyApple(String id, {DateTime? at}) => Order(
  id: id,
  assetId: 'aapl',
  side: Side.buy,
  type: OrderType.limit,
  size: QuantitySize(Quantity.whole(2)),
  limitPrice: Price(d('70'), Currency.usd),
  createdAt: at ?? day(2, 18),
);

Fill fillOf(
  Order order, {
  required String price,
  Side? side,
  DateTime? date,
  String qty = '2',
}) => Fill(
  assetId: order.assetId,
  side: side ?? order.side,
  date: date ?? day(2, 20),
  quantity: Quantity.truncate(d(qty)),
  price: Price(d(price), Currency.usd),
  fxRate: d('0.9'),
  fees: eur('0.12'),
);

void main() {
  late AppDatabase db;
  late WalletRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = WalletRepository(db);
    await repo.createWallet(
      id: 'covid',
      kind: WalletKind.trip,
      name: 'Covid',
      startDate: day(2, 18),
      startingCash: eur('10000'),
      params: realistic,
      createdAt: DateTime.utc(2026, 10, 7),
    );
  });
  tearDown(() => db.close());

  test('a new wallet: starting cash, first value, params kept', () async {
    final w = await repo.load('covid');
    expect(w.kind, WalletKind.trip);
    expect(w.simDate, day(2, 18));
    expect(w.status, WalletStatus.active);
    expect(w.cash, eur('10000'));
    expect(w.values.single.value, eur('10000'));
    expect(w.values.single.flow, eur('10000'));
    expect(w.params.difficulty, 'realiste');
    expect(w.params.monthlyContribution, eur('200'));
    expect(w.params.rules.fxFeeRate, d('0.0015'));
    expect(w.params.rules.fractionalShares, isTrue);
    expect(w.params.stops.drawdown, d('0.15'));
    expect(w.params.stops.positionLoss, isNull);
    expect(w.params.stops.orderFilled, isTrue);
    expect(w.positions, isEmpty);
  });

  test('a live wallet has no simulated date', () async {
    await repo.createWallet(
      id: 'live',
      kind: WalletKind.live,
      name: 'Live',
      startDate: day(1, 1),
      startingCash: eur('50000'),
      params: realistic,
      createdAt: day(1, 1),
    );
    expect((await repo.load('live')).simDate, isNull);
  });

  test('the live wallet is created once, with the §4.5 settings', () async {
    final launch = DateTime.utc(2026, 10, 9, 7, 30);
    final id = await repo.ensureLiveWallet(launch);
    expect(
      await repo.ensureLiveWallet(launch.add(const Duration(days: 3))),
      id,
    );

    final live = await repo.load(id);
    expect(live.kind, WalletKind.live);
    expect(live.startDate, DateTime.utc(2026, 10, 9));
    expect(live.cash, eur('50000'));
    expect(live.values.single.value, eur('50000'));
    expect(live.params.rules.fxFeeRate, d('0.0015'));
    expect(live.params.rules.fixedFee, eur('0'));
    expect(live.params.rules.fractionalShares, isTrue);
    expect(live.params.monthlyContribution, eur('0'));
    expect(live.params.stops.drawdown, isNull);
    expect(live.params.stops.orderFilled, isFalse);
  });

  test('an unknown wallet is a NotFoundFailure', () async {
    expect(() => repo.load('nope'), throwsA(isA<NotFoundFailure>()));
  });

  test('orders wait, fill, and the ledger follows', () async {
    final order = buyApple('o1');
    await repo.placeOrder('covid', order);
    var w = await repo.load('covid');
    final pending = w.pendingOrders.single;
    expect(pending.id, 'o1');
    expect(pending.type, OrderType.limit);
    expect((pending.size as QuantitySize).quantity, Quantity.whole(2));
    expect(pending.limitPrice, Price(d('70'), Currency.usd));

    // 2 × 66 $ × 0.9 = 118,80 € + 0,12 € of fees.
    final fill = fillOf(order, price: '66');
    await repo.recordFill('covid', order, fill);
    w = await repo.load('covid');
    expect(w.pendingOrders, isEmpty);
    expect(w.cash, eur('9881.08'));
    expect(w.fills.single.price, Price(d('66'), Currency.usd));
    expect(w.fills.single.fees, eur('0.12'));
    expect(w.fills.single.orderId, 'o1');

    // Positions are derived from the fills on every load.
    final position = w.positions['aapl']!;
    expect(position.quantity, Quantity.whole(2));
    expect(position.costBasis, d('118.92'));
  });

  test('a sell credits notional minus fees and realises P&L', () async {
    final buy = buyApple('o1');
    await repo.placeOrder('covid', buy);
    await repo.recordFill('covid', buy, fillOf(buy, price: '66'));
    final sell = Order(
      id: 'o2',
      assetId: 'aapl',
      side: Side.sell,
      type: OrderType.market,
      size: QuantitySize(Quantity.whole(1)),
      createdAt: day(3, 1),
    );
    await repo.placeOrder('covid', sell);
    await repo.recordFill(
      'covid',
      sell,
      fillOf(sell, price: '80', qty: '1', date: day(3, 2)),
    );

    final w = await repo.load('covid');
    // 9 881,08 + (72,00 − 0,12).
    expect(w.cash, eur('9952.96'));
    expect(w.positions['aapl']!.quantity, Quantity.whole(1));
    expect(w.fills.map((f) => f.side), [Side.buy, Side.sell]);
  });

  test('amount orders keep their amount', () async {
    final order = Order(
      id: 'o1',
      assetId: 'cw8',
      side: Side.buy,
      type: OrderType.market,
      size: AmountSize(eur('250')),
      createdAt: day(2, 18),
      planId: 'p1',
    );
    await repo.placeOrder('covid', order);
    final pending = (await repo.load('covid')).pendingOrders.single;
    expect((pending.size as AmountSize).amount, eur('250'));
    expect(pending.planId, 'p1');
  });

  test('a cancelled order leaves the pending list', () async {
    await repo.placeOrder('covid', buyApple('o1'));
    await repo.cancelOrder('o1', CancelReason.insufficientCash);
    expect((await repo.load('covid')).pendingOrders, isEmpty);
  });

  test('the daily value series is appended, one row per day', () async {
    await repo.appendValue(
      'covid',
      DailyValue(date: day(2, 19), value: eur('9800'), flow: eur('0')),
    );
    await repo.appendValue(
      'covid',
      DailyValue(date: day(2, 20), value: eur('9700'), flow: eur('0')),
    );
    // A day recomputed replaces its row.
    await repo.appendValue(
      'covid',
      DailyValue(date: day(2, 20), value: eur('9750'), flow: eur('0')),
    );
    final values = (await repo.load('covid')).values;
    expect(values.map((v) => v.date), [day(2, 18), day(2, 19), day(2, 20)]);
    expect(values.last.value, eur('9750'));
  });

  test('contributions and Livret transfers move cash', () async {
    await repo.addContribution('covid', day(3, 2), eur('200'));
    await repo.moveToLivret('covid', day(3, 3), eur('1000'));
    await repo.moveToLivret('covid', day(3, 20), eur('-300'));
    final w = await repo.load('covid');
    expect(w.cash, eur('9500'));
    expect(w.livretMovements.map((m) => (m.date, m.amount)), [
      (day(3, 3), eur('1000')),
      (day(3, 20), eur('-300')),
    ]);
    // They rebuild the Livret account.
    final livret = livretAt(
      w.livretMovements,
      rates: [LivretRate(DateTime.utc(2000), d('0.03'))],
      asOf: day(3, 21),
    );
    expect(livret.balance, eur('700'));
  });

  test('DCA plans are saved and read back', () async {
    final plan = DcaPlan(
      id: 'p1',
      assetId: 'cw8',
      amount: eur('200'),
      frequency: DcaFrequency.monthly,
      start: day(3, 2),
    );
    await repo.savePlan('covid', plan);
    final read = (await repo.load('covid')).plans.single;
    expect(read.amount, eur('200'));
    expect(read.frequency, DcaFrequency.monthly);
    expect(read.start, day(3, 2));
    expect(read.active, isTrue);
  });

  test('storage errors become a StorageFailure', () async {
    // The wallet does not exist: the foreign key refuses the order.
    expect(
      () => repo.placeOrder('ghost', buyApple('o9')),
      throwsA(isA<StorageFailure>()),
    );
  });

  group('trips', () {
    final rates = [LivretRate(DateTime.utc(2019, 8, 1), d('0.0075'))];

    test('a new trip as the engine takes it', () async {
      final state = await repo.tripState('covid', livretRates: rates);
      expect(state.date, day(2, 18));
      expect(state.cash, eur('10000'));
      expect(state.invested, eur('10000'));
      expect(state.values.single.flow, eur('10000'));
      expect(state.breached, isEmpty);
      expect(state.companionLog, isEmpty);
    });

    test('an advance is booked whole, and reads back', () async {
      final before = await repo.tripState('covid', livretRates: rates);
      final userOrder = buyApple('o1');
      await repo.placeOrder('covid', userOrder);
      final dcaOrder = Order(
        id: 'dca-p1-2020-03-02',
        assetId: 'aapl',
        side: Side.buy,
        type: OrderType.market,
        size: AmountSize(eur('100')),
        createdAt: day(3, 2),
        planId: 'p1',
      );
      final cancelled = Order(
        id: 'o2',
        assetId: 'aapl',
        side: Side.buy,
        type: OrderType.limit,
        size: QuantitySize(Quantity.whole(1)),
        limitPrice: Price(d('1'), Currency.usd),
        createdAt: day(2, 18),
      );
      await repo.placeOrder('covid', cancelled);
      final userFill = fillOf(userOrder, price: '66', date: day(2, 20));
      final dcaFill = fillOf(
        dcaOrder,
        price: '60',
        date: day(3, 2),
        qty: '1.5',
      );
      final values = [
        ...before.values,
        DailyValue(date: day(2, 19), value: eur('9990'), flow: eur('0')),
        DailyValue(date: day(3, 2), value: eur('10150'), flow: eur('200')),
      ];
      final after = before.copyWith(
        date: day(3, 2),
        values: values,
        breached: {'drawdown'},
        companion: CompanionTracker.restore(
          peaks: {'aapl': Price(d('66'), Currency.usd)},
          index: d('0.98'),
          indexPeak: d('1'),
          previousValue: d('10150'),
          cashHighSince: null,
          recentPnl: const {},
          usdRates: const [],
          followUps: const {},
        ),
      );
      await repo.saveAdvance(
        'covid',
        TripAdvance(
          state: after,
          events: [
            OrderFilled(day(2, 20), userOrder, userFill),
            ContributionCredited(day(3, 2), eur('200')),
            OrderPlaced(day(3, 2), dcaOrder),
            OrderFilled(day(3, 2), dcaOrder, dcaFill),
            OrderCancelled(day(3, 2), cancelled, CancelReason.insufficientCash),
            MomentFired(
              Moment(CompanionRule.firstLoss, '', day(3, 2), const {
                'assetId': 'aapl',
              }),
            ),
          ],
          stop: const [ContributionStop(Money(20000, Currency.eur))],
          endOfData: false,
        ),
        before: before,
      );

      final wallet = await repo.load('covid');
      expect(wallet.simDate, day(3, 2));
      expect(wallet.status, WalletStatus.stopped);
      expect(wallet.pendingOrders, isEmpty);
      expect(wallet.fills, hasLength(2));
      expect(
        [for (final v in wallet.values) v.date],
        [day(2, 18), day(2, 19), day(3, 2)],
      );
      final reloaded = await repo.tripState('covid', livretRates: rates);
      expect(reloaded.invested, eur('10200'));
      expect(reloaded.breached, {'drawdown'});
      expect(reloaded.companion.peaks['aapl'], Price(d('66'), Currency.usd));
      expect(reloaded.companionLog.single.rule, CompanionRule.firstLoss);
      final moment = (await repo.moments('covid')).single;
      expect(
        (moment.rule, moment.firedAt),
        (CompanionRule.firstLoss, day(3, 2)),
      );
      // 10 000 + 200 − (118,80 + 0,12) − (81,00 + 0,12)
      expect(reloaded.cash, eur('9999.96'));
    });

    test('a stop keeps its reasons until the user decides', () async {
      final before = await repo.tripState('covid', livretRates: rates);
      const drop = DrawdownStop(
        value: Money(840000, Currency.eur),
        threshold: Money(850000, Currency.eur),
      );
      await repo.saveAdvance(
        'covid',
        TripAdvance(
          state: before.copyWith(date: day(3, 9)),
          events: const [],
          stop: const [drop],
          endOfData: false,
        ),
        before: before,
      );
      var wallet = await repo.load('covid');
      expect(wallet.status, WalletStatus.stopped);
      final reason = wallet.stopReasons.single as DrawdownStop;
      expect((reason.value, reason.threshold), (drop.value, drop.threshold));

      final sell = Order(
        id: 'stop-aapl-2020-03-09',
        assetId: 'aapl',
        side: Side.sell,
        type: OrderType.market,
        size: QuantitySize(Quantity.whole(1)),
        createdAt: day(3, 9),
      );
      await repo.decide(
        'covid',
        simDate: day(3, 9),
        eventId: 'stop-2020-03-09',
        decision: 'sell_half',
        sells: [sell],
        reason: 'Trop de stress',
      );
      wallet = await repo.load('covid');
      expect(wallet.status, WalletStatus.active);
      expect(wallet.stopReasons, isEmpty);
      expect(wallet.pendingOrders.single.id, 'stop-aapl-2020-03-09');
      final journal = await repo.journal('covid');
      expect(
        (
          journal.single.date,
          journal.single.decision,
          journal.single.reason,
          journal.single.eventId,
        ),
        (day(3, 9), 'sell_half', 'Trop de stress', 'stop-2020-03-09'),
      );
    });

    test('the journal reads back in date order', () async {
      for (final (date, decision) in [
        (day(4, 2), 'hold'),
        (day(3, 9), 'continue'),
      ]) {
        await repo.decide(
          'covid',
          simDate: date,
          eventId: 'stop',
          decision: decision,
          sells: const [],
        );
      }
      final journal = await repo.journal('covid');
      expect([for (final e in journal) e.decision], ['continue', 'hold']);
      expect(journal.first.reason, isNull);
    });

    test('the end of the data finishes the trip', () async {
      final before = await repo.tripState('covid', livretRates: rates);
      await repo.saveAdvance(
        'covid',
        TripAdvance(
          state: before.copyWith(date: day(2, 19)),
          events: const [],
          stop: const [],
          endOfData: true,
        ),
        before: before,
      );
      final wallet = await repo.load('covid');
      expect(
        (wallet.status, wallet.simDate),
        (WalletStatus.finished, day(2, 19)),
      );
    });

    test('a trip can be finished any time', () async {
      await repo.finish('covid');
      final wallet = await repo.load('covid');
      expect(
        (wallet.status, wallet.simDate),
        (WalletStatus.finished, day(2, 18)),
      );
    });

    test('an unknown wallet has no journal and no moment', () async {
      expect(await repo.journal('nope'), isEmpty);
      expect(await repo.moments('nope'), isEmpty);
    });

    test('the automatic stops can be changed', () async {
      await repo.updateStops(
        'covid',
        StopConditions(positionLoss: d('0.20'), contribution: true),
      );
      final stops = (await repo.load('covid')).params.stops;
      expect(stops.drawdown, isNull);
      expect(stops.positionLoss, d('0.20'));
      expect(stops.contribution, isTrue);
      expect(stops.orderFilled, isFalse);
      expect((await repo.load('covid')).params.monthlyContribution, eur('200'));
    });

    test('no stop leaves the status as it was', () async {
      final before = await repo.tripState('covid', livretRates: rates);
      await repo.saveAdvance(
        'covid',
        TripAdvance(
          state: before.copyWith(date: day(2, 19)),
          events: const [],
          stop: const [],
          endOfData: false,
        ),
        before: before,
      );
      final wallet = await repo.load('covid');
      expect(wallet.status, WalletStatus.active);
      expect(wallet.simDate, day(2, 19));
    });
  });

  test(
    'mission facts: the live wallet\'s holdings and any active plan',
    () async {
      await repo.ensureLiveWallet(DateTime.utc(2026, 10, 11));
      final facts = <({Set<String> liveAssets, bool activePlan})>[];
      final sub = repo.watchMissionFacts().listen(facts.add);
      addTearDown(sub.cancel);
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 20));
      await settle();
      expect(facts.last.liveAssets, isEmpty);
      expect(facts.last.activePlan, isFalse);

      // A buy in the live wallet; one in a trip does not count.
      final order = buyApple('o1');
      await repo.placeOrder('live', order);
      await repo.recordFill('live', order, fillOf(order, price: '66'));
      await repo.placeOrder('covid', buyApple('o2'));
      await repo.recordFill(
        'covid',
        buyApple('o2'),
        fillOf(buyApple('o2'), price: '66'),
      );
      await settle();
      expect(facts.last.liveAssets, {'aapl'});
      expect(facts.last.activePlan, isFalse);

      // Sold out: no longer held.
      final sell = Order(
        id: 's1',
        assetId: 'aapl',
        side: Side.sell,
        type: OrderType.market,
        size: QuantitySize(Quantity.whole(2)),
        createdAt: day(3, 1),
      );
      await repo.placeOrder('live', sell);
      await repo.recordFill(
        'live',
        sell,
        fillOf(sell, price: '70', side: Side.sell),
      );
      await settle();
      expect(facts.last.liveAssets, isEmpty);

      // A plan in any wallet.
      await repo.savePlan(
        'covid',
        DcaPlan(
          id: 'p1',
          assetId: 'aapl',
          amount: eur('100'),
          frequency: DcaFrequency.monthly,
          start: day(3, 2),
        ),
      );
      await settle();
      expect(facts.last.activePlan, isTrue);
    },
  );

  test('a live order filled at once: placed and filled together', () async {
    final order = Order(
      id: 'now',
      assetId: 'aapl',
      side: Side.buy,
      type: OrderType.market,
      size: QuantitySize(Quantity.whole(2)),
      createdAt: day(2, 20),
    );
    await repo.executeOrder('covid', order, fillOf(order, price: '66'));
    final w = await repo.load('covid');
    expect(w.pendingOrders, isEmpty);
    expect(w.fills.single.orderId, 'now');
    expect(w.positions['aapl']!.quantity, Quantity.whole(2));
  });

  test('a trip order waits; its reason goes to the journal', () async {
    Order buy(String id) => Order(
      id: id,
      assetId: 'aapl',
      side: Side.buy,
      type: OrderType.market,
      size: QuantitySize(Quantity.whole(1)),
      createdAt: day(3, 9),
    );
    await repo.placeTripOrder(
      'covid',
      buy('t1'),
      simDate: day(3, 9),
      reason: 'Les prix ont baissé',
    );
    await repo.placeTripOrder('covid', buy('t2'), simDate: day(3, 9));
    expect(
      [for (final o in (await repo.load('covid')).pendingOrders) o.id],
      ['t1', 't2'],
    );
    final journal = await repo.journal('covid');
    expect(
      [for (final e in journal) (e.date, e.decision, e.eventId, e.reason)],
      [(day(3, 9), 'buy', 't1', 'Les prix ont baissé')],
      reason: 'no reason, no entry',
    );
  });

  group('the live wallet as the engine takes it', () {
    final rates = [LivretRate(DateTime.utc(2019, 8, 1), d('0.0075'))];

    test('its day is the last valued one', () async {
      await repo.ensureLiveWallet(DateTime.utc(2026, 10, 5, 9));
      final state = await repo.liveState(livretRates: rates);
      expect(state.date, DateTime.utc(2026, 10, 5));
      expect((state.cash, state.invested), (eur('50000'), eur('50000')));
    });

    test('an advance books its days but never makes it a trip', () async {
      await repo.ensureLiveWallet(DateTime.utc(2026, 10, 5, 9));
      final before = await repo.liveState(livretRates: rates);
      await repo.saveAdvance(
        'live',
        TripAdvance(
          state: before.copyWith(
            date: DateTime.utc(2026, 10, 7),
            values: [
              ...before.values,
              DailyValue(
                date: DateTime.utc(2026, 10, 6),
                value: eur('50010'),
                flow: eur('0'),
              ),
              DailyValue(
                date: DateTime.utc(2026, 10, 7),
                value: eur('50020'),
                flow: eur('0'),
              ),
            ],
          ),
          events: const [],
          stop: const [],
          endOfData: true,
        ),
        before: before,
      );
      final live = await repo.load('live');
      expect((live.simDate, live.status), (null, WalletStatus.active));
      expect(live.values.last.date, DateTime.utc(2026, 10, 7));
      expect(
        (await repo.liveState(livretRates: rates)).date,
        DateTime.utc(2026, 10, 7),
      );
    });
  });

  test('an order\'s detail: pending, filled, cancelled by the user', () async {
    final pending = buyApple('p');
    await repo.placeOrder('covid', pending);
    var detail = (await repo.orderDetail('p'))!;
    expect(
      (detail.walletId, detail.status, detail.fill),
      ('covid', OrderStatus.pending, null),
    );
    expect(detail.order.limitPrice, Price(d('70'), Currency.usd));

    await repo.recordFill('covid', pending, fillOf(pending, price: '66'));
    detail = (await repo.orderDetail('p'))!;
    expect(detail.status, OrderStatus.filled);
    expect(detail.fill!.price, Price(d('66'), Currency.usd));

    await repo.placeOrder('covid', buyApple('c'));
    expect(await repo.cancelByUser('c'), isTrue);
    detail = (await repo.orderDetail('c'))!;
    expect(
      (detail.status, detail.cancelReason),
      (OrderStatus.cancelled, CancelReason.byUser),
    );
    expect((await repo.load('covid')).pendingOrders, isEmpty);
    expect(await repo.cancelByUser('p'), isFalse, reason: 'already filled');
    expect(await repo.orderDetail('nope'), isNull);
  });

  group('the live wallet from Settings', () {
    final now = DateTime.utc(2026, 10, 12, 9);

    test(
      'a new FX fee applies to what comes next, not to past fills',
      () async {
        await repo.ensureLiveWallet(now);
        await repo.setLiveFxFee(Decimal.parse('0.005'));
        final w = await repo.load(WalletRepository.liveWalletId);
        expect(w.params.rules.fxFeeRate, Decimal.parse('0.005'));
        expect(w.params.rules.fractionalShares, isTrue);
      },
    );

    test('a reset starts again today with the new capital, the fee kept, '
        'nothing left of before', () async {
      await repo.ensureLiveWallet(DateTime.utc(2026, 9, 1));
      await repo.setLiveFxFee(Decimal.parse('0.01'));
      await repo.moveToLivret(
        WalletRepository.liveWalletId,
        DateTime.utc(2026, 9, 2),
        const Money(100000, Currency.eur),
      );
      await repo.resetLiveWallet(
        now,
        startingCash: const Money(1000000, Currency.eur),
      );
      final w = await repo.load(WalletRepository.liveWalletId);
      expect(w.startDate, DateTime.utc(2026, 10, 12));
      expect(w.cash, const Money(1000000, Currency.eur));
      expect(w.livretMovements, isEmpty);
      expect(w.values.single.value, const Money(1000000, Currency.eur));
      expect(w.params.rules.fxFeeRate, Decimal.parse('0.01'));
    });

    test('a reset without a live wallet creates one', () async {
      await repo.resetLiveWallet(
        now,
        startingCash: WalletRepository.defaultLiveCash,
      );
      expect(
        (await repo.load(WalletRepository.liveWalletId)).cash,
        WalletRepository.defaultLiveCash,
      );
    });
  });
}
