import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
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
}
