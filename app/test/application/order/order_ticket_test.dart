import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/order/order_ticket.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
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
import '../../fakes/glossary_pack.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(d(s), Currency.eur);

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late WallClock wall;
  late ProviderContainer c;
  late WalletRepository wallets;

  /// [at]: Thursday 2026-10-08 12:00 UTC is 08:00 in New York, closed.
  Future<void> open({
    DateTime? at,
    bool withGateTerm = true,
    Stream<bool>? online,
  }) async {
    db = AppDatabase(NativeDatabase.memory());
    wall = WallClock(at ?? DateTime.utc(2026, 10, 8, 12));
    backend = FakeBackend()
      ..assets.add({
        ...FakeBackend().assets.first,
        'id': 'world',
        'type': 'etf',
      })
      ..closes['world'] = {
        '2026-10-05': '100',
        '2026-10-06': '101',
        '2026-10-07': '102',
      };
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
            online: online,
          ),
        ),
        fxServiceProvider.overrideWithValue(
          FxService(
            db,
            FrankfurterApi(adapter: FakeFrankfurter()),
            wallClock: wall,
          ),
        ),
        contentPackProvider(actionsEtfIsland).overrideWith(
          (ref) async =>
              decodePack(glossaryPackJson(withOrderTerms: withGateTerm)),
        ),
      ],
    );
    wallets = c.read(walletRepositoryProvider);
    await wallets.ensureLiveWallet(DateTime.utc(2026, 10, 5, 9));
  }

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<TicketState> ticket(Side side, {String walletId = 'live'}) async {
    c.listen(orderTicketProvider('apple', walletId, side), (_, _) {});
    return c.read(orderTicketProvider('apple', walletId, side).future);
  }

  OrderTicket actions(Side side, {String walletId = 'live'}) =>
      c.read(orderTicketProvider('apple', walletId, side).notifier);

  TicketState now(Side side, {String walletId = 'live'}) =>
      c.read(orderTicketProvider('apple', walletId, side)).value!;

  List<String> codes(TicketState s) => [for (final e in s.errors) e.code];

  test(
    'the context: room, price, threshold, the market closed till 13:30 UTC',
    () async {
      await open();
      final s = await ticket(Side.buy);
      final ctx = s.context;
      expect((ctx.isTrip, ctx.finished), (false, false));
      expect(ctx.availableCash, eur('50000'));
      expect(ctx.availableQuantity, const Quantity.zero());
      expect(ctx.threshold, d('0.40'));
      expect(ctx.price.value, d('102'));
      expect(
        (ctx.marketOpen, ctx.nextOpen),
        (false, DateTime.utc(2026, 10, 8, 13, 30)),
      );
      // Nothing typed: the error is there but not shown.
      expect(codes(s), ['amount_not_positive']);
      expect(s.showErrors, isFalse);
    },
  );

  test('typing prices the order and weighs it', () async {
    await open();
    await ticket(Side.buy);
    actions(Side.buy).setAmount('8 717,94');
    final s = now(Side.buy);
    expect(codes(s), isEmpty);
    // 8 717,94 € at 102 $ × 0,8547: 100 shares.
    expect(s.estimate!.quantity, Quantity.whole(100));
    expect(s.estimate!.fees, eur('13.08'));
    expect(s.weight!.before, Decimal.zero);
    expect(s.weight!.after.round(scale: 2), d('0.17'));
    expect(s.overThreshold, isFalse);

    actions(Side.buy).setAmount('30000');
    expect(now(Side.buy).overThreshold, isTrue, reason: 'never blocks');
    expect(now(Side.buy).canSubmit, isTrue);
  });

  test('every rule broken shows its code, once there is input', () async {
    await open();
    await ticket(Side.buy);
    actions(Side.buy).setAmount('0');
    expect(codes(now(Side.buy)), ['amount_not_positive']);
    expect(now(Side.buy).showErrors, isTrue);
    actions(Side.buy).setAmount('60000');
    final cash = now(Side.buy).errors.single;
    expect(
      (cash.code, cash.params['cash']),
      ('insufficient_cash', eur('50000')),
    );

    await ticket(Side.sell);
    actions(Side.sell)
      ..setMode(SizeMode.quantity)
      ..setQuantity('1');
    expect(codes(now(Side.sell)), ['insufficient_quantity']);

    await actions(Side.buy).setType(OrderType.limit);
    actions(Side.buy).setAmount('100');
    expect(codes(now(Side.buy)), ['limit_price_not_positive']);
  });

  test('quick amounts: Max fits the fees in; sells take half or all', () async {
    await open();
    await ticket(Side.buy);
    actions(Side.buy).quick(const QuickMax());
    final s = now(Side.buy);
    expect(codes(s), isEmpty);
    expect(s.estimate!.total <= eur('50000'), isTrue);

    final order = Order(
      id: 'b',
      assetId: 'apple',
      side: Side.buy,
      type: OrderType.market,
      size: QuantitySize(Quantity.whole(5)),
      createdAt: DateTime.utc(2026, 10, 5),
    );
    await wallets.placeOrder('live', order);
    await wallets.recordFill(
      'live',
      order,
      Fill(
        assetId: 'apple',
        side: Side.buy,
        date: DateTime.utc(2026, 10, 5),
        quantity: Quantity.whole(5),
        price: Price(d('100'), Currency.usd),
        fxRate: d('0.85'),
        fees: const Money.zero(Currency.eur),
      ),
    );
    c.invalidate(orderTicketProvider('apple', 'live', Side.sell));
    await ticket(Side.sell);
    actions(Side.sell).quick(const QuickHalf());
    expect(now(Side.sell).estimate!.quantity, Quantity.truncate(d('2.5')));
    actions(Side.sell).quick(const QuickAll());
    expect(now(Side.sell).estimate!.quantity, Quantity.whole(5));
  });

  test('market closed: the order waits for the opening', () async {
    await open();
    await ticket(Side.buy);
    actions(Side.buy).setAmount('500');
    final outcome = await actions(Side.buy).submit();
    expect((outcome! as OrderSent).opensAt, DateTime.utc(2026, 10, 8, 13, 30));
    expect((await wallets.load('live')).pendingOrders, hasLength(1));
  });

  test('market open: a market order fills at the quote now', () async {
    // Wednesday 2026-10-07 15:00 UTC is 11:00 in New York.
    await open(at: DateTime.utc(2026, 10, 7, 15));
    backend.quotes['apple'] = {
      'assetId': 'apple',
      'price': '101.5',
      'currency': 'USD',
      'asOf': '2026-10-07T14:55:00Z',
      'marketOpen': true,
    };
    final s = await ticket(Side.buy);
    expect(s.context.marketOpen, isTrue);
    actions(Side.buy)
      ..setMode(SizeMode.quantity)
      ..setQuantity('2');
    final outcome = await actions(Side.buy).submit();
    final fill = (outcome! as OrderExecuted).fill;
    expect((fill.quantity, fill.price.value), (Quantity.whole(2), d('101.5')));
    final wallet = await wallets.load('live');
    expect(wallet.pendingOrders, isEmpty);
    expect(wallet.positions['apple']!.quantity, Quantity.whole(2));
  });

  test('offline, market open: the order waits for the next opening', () async {
    // BRIEF §14.1 (decided 2026-10-12): no fill at a price that may be old.
    final online = StreamController<bool>();
    addTearDown(online.close);
    await open(at: DateTime.utc(2026, 10, 7, 15), online: online.stream);
    backend.quotes['apple'] = {
      'assetId': 'apple',
      'price': '101.5',
      'currency': 'USD',
      'asOf': '2026-10-07T14:55:00Z',
      'marketOpen': true,
    };
    await ticket(Side.buy);
    backend.offline = true;
    online.add(false);
    await pumpEventQueue();
    c.invalidate(orderTicketProvider('apple', 'live', Side.buy));

    final s = await ticket(Side.buy);
    expect(
      (s.context.marketOpen, s.context.offline, s.context.nextOpen),
      (true, true, DateTime.utc(2026, 10, 8, 13, 30)),
    );
    actions(Side.buy)
      ..setMode(SizeMode.quantity)
      ..setQuantity('2');
    final outcome = await actions(Side.buy).submit();
    expect((outcome! as OrderSent).opensAt, DateTime.utc(2026, 10, 8, 13, 30));
    final wallet = await wallets.load('live');
    expect(wallet.pendingOrders, hasLength(1));
    expect(wallet.positions['apple'], isNull);
  });

  test(
    'a trip order waits for the trip; its reason goes to the journal',
    () async {
      await open();
      await wallets.createWallet(
        id: 'trip',
        kind: WalletKind.trip,
        name: 'Octobre',
        startDate: DateTime.utc(2026, 10, 7),
        startingCash: eur('10000'),
        params: WalletParams(
          rules: TradingRules(
            fxFeeRate: Decimal.zero,
            fixedFee: const Money.zero(Currency.eur),
            fractionalShares: false,
          ),
          monthlyContribution: const Money.zero(Currency.eur),
          stops: const StopConditions(),
        ),
        createdAt: DateTime.utc(2026, 10, 8),
      );
      final s = await ticket(Side.buy, walletId: 'trip');
      expect(s.context.isTrip, isTrue);
      actions(Side.buy, walletId: 'trip')
        ..setAmount('500')
        ..setReason('  Le prix me paraît bas  ');
      expect(
        await actions(Side.buy, walletId: 'trip').submit(),
        isA<OrderSent>(),
      );
      final journal = await wallets.journal('trip');
      expect(
        (journal.single.decision, journal.single.reason),
        ('buy', 'Le prix me paraît bas'),
      );
    },
  );

  test('a finished trip takes no order', () async {
    await open();
    await wallets.createWallet(
      id: 'done',
      kind: WalletKind.trip,
      name: 'Fini',
      startDate: DateTime.utc(2026, 10, 7),
      startingCash: eur('10000'),
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: Decimal.zero,
          fixedFee: const Money.zero(Currency.eur),
          fractionalShares: true,
        ),
        monthlyContribution: const Money.zero(Currency.eur),
        stops: const StopConditions(),
      ),
      createdAt: DateTime.utc(2026, 10, 8),
    );
    await wallets.finish('done');
    await ticket(Side.buy, walletId: 'done');
    actions(Side.buy, walletId: 'done').setAmount('100');
    expect(now(Side.buy, walletId: 'done').canSubmit, isFalse);
    expect(await actions(Side.buy, walletId: 'done').submit(), isNull);
  });

  test('soft gate: the first limit opens its term, once', () async {
    await open();
    await ticket(Side.buy);
    expect(await actions(Side.buy).setType(OrderType.limit), 'ordre-limite');
    expect(await actions(Side.buy).setType(OrderType.market), isNull);
    await c
        .read(glossaryRepositoryProvider)
        .discover('ordre-limite', wall.now());
    expect(await actions(Side.buy).setType(OrderType.limit), isNull);
    expect(await actions(Side.buy).setType(OrderType.stop), 'ordre-stop');
  });

  test('soft gate: no sheet for a term the pack does not have', () async {
    await open(withGateTerm: false);
    await ticket(Side.buy);
    expect(await actions(Side.buy).setType(OrderType.limit), isNull);
  });
}
