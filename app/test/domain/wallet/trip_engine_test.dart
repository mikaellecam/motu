import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:finance_companion/domain/learning/profile_rules.dart';
import 'package:finance_companion/domain/livret/livret_interest.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/order_matcher.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String amount) => Money.book(d(amount), Currency.eur);
DateTime day(int m, int dd) => DateTime.utc(2026, m, dd);

// Good Friday closes both; Easter Monday and 1 May close Euronext only;
// Friday 3 July closes the US markets only.
final calendar = MarketCalendar({
  Exchange.euronext: {day(4, 3), day(4, 6), day(5, 1)},
  Exchange.nyse: {day(4, 3), day(7, 3)},
  Exchange.nasdaq: {day(4, 3), day(7, 3)},
  // OTC follows the NYSE holiday calendar.
  Exchange.otc: {day(4, 3), day(7, 3)},
});

const exchanges = {'cw8': Exchange.euronext, 'aapl': Exchange.nyse};

/// A market made of daily bars, which fails the test if the engine reads a
/// date after [readLimit].
class FakeMarket implements TripMarket {
  FakeMarket(this.prices, {required this.lastDate, required this.readLimit});

  /// assetId → date → open and close of that day.
  final Map<String, Map<DateTime, String>> prices;
  @override
  final DateTime lastDate;
  final DateTime readLimit;

  void _check(DateTime date) {
    if (date.isAfter(readLimit)) fail('read $date after $readLimit');
  }

  Currency _currency(String asset) =>
      asset == 'aapl' ? Currency.usd : Currency.eur;

  @override
  PriceBar? bar(String assetId, DateTime date) {
    _check(date);
    final price = prices[assetId]?[date];
    if (price == null) return null;
    return PriceBar(
      date: date,
      open: d(price),
      high: d(price),
      low: d(price),
      close: d(price),
      volume: 0,
      currency: _currency(assetId),
    );
  }

  @override
  PriceAsOf? priceAsOf(String assetId, DateTime date) {
    _check(date);
    final known = (prices[assetId] ?? {}).keys.where((k) => !k.isAfter(date));
    if (known.isEmpty) return null;
    final latest = known.reduce((a, b) => a.isAfter(b) ? a : b);
    return PriceAsOf(
      Price(d(prices[assetId]![latest]!), _currency(assetId)),
      latest,
      stale: latest.isBefore(calendar.onOrBefore(exchangeOf(assetId), date)),
    );
  }

  @override
  Decimal fxRate(Currency currency, DateTime date) {
    _check(date);
    return currency == Currency.usd ? d('0.9') : Decimal.one;
  }

  @override
  Exchange exchangeOf(String assetId) => exchanges[assetId]!;
}

/// Bars on every trading day of [asset]'s exchange in [from]..[to].
Map<DateTime, String> series(
  String asset,
  DateTime from,
  DateTime to, {
  String price = '100',
  Map<DateTime, String> overrides = const {},
}) {
  final exchange = exchanges[asset]!;
  return {
    for (
      var date = from;
      !date.isAfter(to);
      date = date.add(const Duration(days: 1))
    )
      if (calendar.isTradingDay(exchange, date)) date: overrides[date] ?? price,
  };
}

final live = TradingRules(
  fxFeeRate: d('0.0015'),
  fixedFee: const Money.zero(Currency.eur),
  fractionalShares: true,
);

final rates = [LivretRate(DateTime.utc(2000), d('0.03'))];

/// The fixture trades CW8 on Euronext and AAPL on NYSE.
TripEngine engine({
  Money? contribution,
  TradingRules? rules,
  Set<Exchange> exchanges = const {Exchange.euronext, Exchange.nyse},
}) => TripEngine(
  calendar: calendar,
  exchanges: exchanges,
  livretRates: rates,
  rules: rules ?? live,
  monthlyContribution: contribution ?? const Money.zero(Currency.eur),
  thresholds: MomentThresholds(concentration: d('0.40')),
);

/// 10 shares of CW8 bought at 100 € on [date], no cash left.
TripState invested1000(DateTime date) {
  final fill = Fill(
    assetId: 'cw8',
    side: Side.buy,
    date: date,
    quantity: Quantity.whole(10),
    price: Price(d('100'), Currency.eur),
    fxRate: Decimal.one,
    fees: const Money.zero(Currency.eur),
  );
  final start = TripState.start(date, eur('1000'));
  return start.copyWith(
    cash: eur('0'),
    fills: [fill],
    positions: {'cw8': applyFill(null, fill)},
  );
}

TripAdvance advance(
  TripEngine e,
  TripState state,
  DateTime target,
  Map<String, Map<DateTime, String>> prices, {
  StopConditions stops = const StopConditions(),
  DateTime? lastDate,
  bool Function(Order order, DateTime day)? eligible,
}) => e.advance(
  state,
  target: target,
  stops: stops,
  eligible: eligible,
  market: FakeMarket(
    prices,
    lastDate: lastDate ?? day(12, 31),
    readLimit: target,
  ),
);

Order buy(
  String id,
  String asset,
  OrderSize size,
  DateTime at, {
  Price? limit,
}) => Order(
  id: id,
  assetId: asset,
  side: Side.buy,
  type: limit == null ? OrderType.market : OrderType.limit,
  size: size,
  limitPrice: limit,
  createdAt: at,
);

void main() {
  test('trip days are days when any exchange trades', () {
    final result = advance(
      engine(),
      TripState.start(day(4, 2), eur('1000')),
      day(4, 7),
      const {},
    );
    // Good Friday (both closed) and the weekend are skipped; Easter Monday
    // counts because New York trades.
    expect(result.state.values.map((v) => v.date), [
      day(4, 2),
      day(4, 6),
      day(4, 7),
    ]);
    expect(result.state.date, day(4, 7));
    expect(result.atToday, isFalse);
    expect(result.stop, isEmpty);
  });

  test('with US listings only, a US holiday is not a trip day', () {
    final usOnly = engine(exchanges: const {Exchange.nyse, Exchange.otc});
    final result = advance(
      usOnly,
      TripState.start(day(7, 2), eur('1000')),
      day(7, 6),
      const {},
    );
    // Friday 3 July: Euronext trades, but no catalogue exchange does.
    expect(result.state.values.map((v) => v.date), [day(7, 2), day(7, 6)]);
  });

  test('a US asset waits on a US holiday and keeps its last close', () {
    final prices = {
      'aapl': series(
        'aapl',
        day(6, 29),
        day(7, 10),
        overrides: {day(7, 2): '110'},
      ),
    };
    final state = TripState.start(day(7, 2), eur('1000')).copyWith(
      pendingOrders: [
        buy('o1', 'aapl', QuantitySize(Quantity.whole(1)), day(7, 2)),
      ],
    );
    final friday = advance(engine(), state, day(7, 3), prices);
    expect(friday.state.date, day(7, 3));
    expect(friday.state.pendingOrders, hasLength(1));
    expect(friday.events, isEmpty);

    final monday = advance(engine(), friday.state, day(7, 6), prices);
    final filled = monday.events.whereType<OrderFilled>().single;
    expect(filled.fill.date, day(7, 6));
    expect(filled.fill.price, Price(d('100'), Currency.usd));
  });

  group('one day, in order', () {
    final prices = {'cw8': series('cw8', day(5, 25), day(6, 5))};
    final plan = DcaPlan(
      id: 'p1',
      assetId: 'cw8',
      amount: eur('200'),
      frequency: DcaFrequency.monthly,
      start: day(6, 1),
    );
    final userOrder = buy(
      'o1',
      'cw8',
      QuantitySize(Quantity.whole(1)),
      day(5, 29),
    );

    test('contribution → DCA → matcher → Livret → valuation', () {
      final state = TripState.start(
        day(5, 29),
        eur('100'),
      ).copyWith(dcaPlans: [plan], pendingOrders: [userOrder]);
      final result = advance(
        engine(contribution: eur('200')),
        state,
        day(6, 1),
        prices,
      );

      // The contribution arrives first, the plan buys at the open with it, then
      // the user's order placed on Friday fills with the cash it reserved.
      final steps = result.events.where((e) => e is! MomentFired);
      expect(steps.map((e) => e.runtimeType), [
        ContributionCredited,
        OrderPlaced,
        OrderFilled,
        OrderFilled,
      ]);
      expect((steps.elementAt(1) as OrderPlaced).order.planId, 'p1');
      expect((steps.elementAt(2) as OrderFilled).order.planId, 'p1');
      expect((steps.elementAt(3) as OrderFilled).order.id, 'o1');
      // Companion rules run after valuation: all in one ETF is concentrated.
      expect(result.events.whereType<MomentFired>().map((e) => e.moment.rule), [
        CompanionRule.concentration,
      ]);
      // Valuation sees the shares bought that morning.
      final today = result.state.values.last;
      expect(today.value, eur('300'));
      expect(today.flow, eur('200'));
      expect(result.state.invested, eur('300'));
      expect(result.state.cash, eur('0'));
      expect(result.state.positions['cw8']!.quantity, Quantity.whole(3));
      expect(result.state.pendingOrders, isEmpty);
    });

    test('a DCA purchase cannot spend cash a pending order reserved', () {
      final state = TripState.start(
        day(5, 29),
        eur('0'),
      ).copyWith(dcaPlans: [plan], pendingOrders: [userOrder]);
      final result = advance(
        engine(contribution: eur('200')),
        state,
        day(6, 1),
        prices,
      );
      // 200 € arrive, 100 € are held for o1: the 200 € purchase is cancelled
      // and o1 fills.
      expect(
        result.events.whereType<OrderCancelled>().single.reason,
        CancelReason.insufficientCash,
      );
      expect(result.events.whereType<OrderFilled>().single.order.id, 'o1');
    });
  });

  test(
    'a day run again keeps one value: its close, the flows added (M12-13)',
    () {
      // The live wallet started on Friday 29 May with 1 000 € and an order
      // placed before that day's open: the state is taken from the day
      // before, so Friday runs once more.
      final start = TripState.start(day(5, 29), eur('1000'));
      final order = buy(
        'o1',
        'cw8',
        QuantitySize(Quantity.whole(2)),
        day(5, 29),
      );
      final result = advance(
        engine(),
        start.copyWith(date: day(5, 28), pendingOrders: [order]),
        day(6, 1),
        {
          'cw8': series(
            'cw8',
            day(5, 25),
            day(6, 5),
            overrides: {day(5, 29): '110'},
          ),
        },
      );

      expect(
        result.events.whereType<OrderFilled>().single.fill.date,
        day(5, 29),
      );
      expect(
        [for (final v in result.state.values) v.date],
        [day(5, 29), day(6, 1)],
      );
      final friday = result.state.values.first;
      // 2 shares at 110 and 780 € of cash, the starting cash still put in.
      expect(friday.value, eur('1000'));
      expect(friday.flow, eur('1000'));
      expect(result.state.invested, eur('1000'));
    },
  );

  test('contributions arrive on the first trip day of each month only', () {
    final result = advance(
      engine(contribution: eur('200')),
      TripState.start(day(4, 28), eur('0')),
      day(6, 3),
      const {},
    );
    // 1 May is closed on Euronext but New York trades: it is a trip day.
    expect(result.events.whereType<ContributionCredited>().map((e) => e.date), [
      day(5, 1),
      day(6, 1),
    ]);
    expect(result.state.cash, eur('400'));
  });

  group('the next contribution', () {
    DateTime? next(DateTime from, {Money? amount, TripEngine? on}) =>
        nextContributionDay(
          from,
          contribution: amount ?? eur('200'),
          isTripDay: (on ?? engine()).isTripDay,
        );

    test('the first trip day of the next month', () {
      expect(next(day(3, 10)), day(4, 1));
      expect(next(day(3, 31)), day(4, 1), reason: 'the last day of a month');
    });

    test('today is the first trip day of a month: the next month', () {
      // Today's contribution was credited when the trip reached it.
      expect(next(day(6, 1)), day(7, 1));
    });

    test('a month that starts on a weekend: the Monday', () {
      // Saturday 1 August.
      expect(next(day(7, 15)), day(8, 3));
    });

    test('a holiday counts only when no exchange trades', () {
      // 1 May closes Euronext; New York trades.
      expect(next(day(4, 20)), day(5, 1));
      final euronextOnly = engine(exchanges: const {Exchange.euronext});
      expect(next(day(4, 20), on: euronextOnly), day(5, 4));
    });

    test('past the calendar data: weekends only', () {
      expect(next(day(12, 15)), DateTime.utc(2027, 1, 1));
    });

    test('no contribution: none comes', () {
      expect(next(day(3, 10), amount: eur('0')), isNull);
      expect(next(day(3, 10), amount: eur('-50')), isNull);
    });

    test('the engine credits it on that day', () {
      final from = TripState.start(day(7, 15), eur('0'));
      final result = advance(
        engine(contribution: eur('200')),
        from,
        day(8, 5),
        const {},
      );
      expect(
        result.events.whereType<ContributionCredited>().single.date,
        next(from.date),
      );
    });
  });

  test('the Livret accrues and counts in the value', () {
    final livret = LivretAccount.empty(day(1, 9))
        .apply(LivretMovement(day(1, 9), eur('2400')));
    final state = TripState.start(
      day(1, 9),
      eur('2400'),
    ).copyWith(cash: eur('0'), livret: livret);
    final result = advance(engine(), state, day(2, 2), const {});
    // Jan 16–31 closed on Feb 1: 2 400 × 3 % / 24.
    expect(result.state.values.last.value, eur('2403'));
  });

  test('a whole-share DCA that buys no share is cancelled', () {
    final tight = TradingRules(
      fxFeeRate: d('0.0015'),
      fixedFee: eur('1'),
      fractionalShares: false,
    );
    final state = TripState.start(day(5, 29), eur('1000')).copyWith(
      dcaPlans: [
        DcaPlan(
          id: 'p1',
          assetId: 'cw8',
          amount: eur('50'),
          frequency: DcaFrequency.monthly,
          start: day(6, 1),
        ),
      ],
    );
    final result = advance(engine(rules: tight), state, day(6, 1), {
      'cw8': series('cw8', day(6, 1), day(6, 1)),
    });
    expect(
      result.events.whereType<OrderCancelled>().single.reason,
      CancelReason.amountBelowOneShare,
    );
  });

  test('companion moments are events, logged, and never stop the trip', () {
    final result = advance(engine(), invested1000(day(5, 29)), day(6, 10), {
      'cw8': series('cw8', day(6, 1), day(6, 10), overrides: {day(6, 3): '84'}),
    });
    expect(result.stop, isEmpty);
    expect(result.state.date, day(6, 10));
    final rules = result.events.whereType<MomentFired>().map(
      (e) => (e.moment.rule, e.date),
    );
    expect(
      rules,
      containsAll([
        (CompanionRule.firstLoss, day(6, 3)),
        (CompanionRule.positionDrop, day(6, 3)),
        (CompanionRule.portfolioDrawdown, day(6, 3)),
      ]),
    );
    // Logged, so they respect their cooldowns on the next advance.
    expect(
      result.state.companionLog.map((e) => e.rule),
      containsAll([CompanionRule.firstLoss, CompanionRule.positionDrop]),
    );
    final again = advance(engine(), result.state, day(6, 12), {
      'cw8': series(
        'cw8',
        day(6, 1),
        day(6, 12),
        overrides: {day(6, 11): '80'},
      ),
    });
    expect(
      again.events.whereType<MomentFired>().where(
        (e) =>
            e.moment.rule == CompanionRule.firstLoss ||
            e.moment.rule == CompanionRule.positionDrop,
      ),
      isEmpty,
    );
  });

  test('a panic sell in a trip, revisited three months later', () {
    final prices = {
      'cw8': series(
        'cw8',
        day(6, 1),
        day(9, 10),
        overrides: {day(6, 2): '84', day(6, 3): '85'},
      ),
    };
    final fell = advance(engine(), invested1000(day(5, 29)), day(6, 2), prices);
    final sell = Order(
      id: 's1',
      assetId: 'cw8',
      side: Side.sell,
      type: OrderType.market,
      size: QuantitySize(Quantity.whole(10)),
      createdAt: day(6, 2),
    );
    final sold = advance(
      engine(),
      fell.state.copyWith(pendingOrders: [sell]),
      day(6, 3),
      prices,
    );
    expect(
      sold.events.whereType<MomentFired>().map((e) => e.moment.rule),
      contains(CompanionRule.panicSell),
    );
    final later = advance(engine(), sold.state, day(9, 10), prices);
    final followUp = later.events.whereType<MomentFired>().singleWhere(
      (e) => e.moment.rule == CompanionRule.panicSellFollowUp,
    );
    expect(followUp.date, day(9, 3));
    expect(followUp.moment.params['priceNow'], Price(d('100'), Currency.eur));
  });

  group('stop conditions', () {
    final crash = {
      'cw8': series(
        'cw8',
        day(6, 1),
        day(6, 30),
        overrides: {
          day(6, 2): '84',
          day(6, 3): '80',
          day(6, 4): '90',
          day(6, 5): '84',
        },
      ),
    };

    test('portfolio below the money put in, minus the threshold', () {
      final stops = StopConditions(drawdown: d('0.15'));
      final first = advance(
        engine(),
        invested1000(day(5, 29)),
        day(6, 30),
        crash,
        stops: stops,
      );
      expect(first.state.date, day(6, 2));
      final reason = first.stop.single as DrawdownStop;
      expect(reason.value, eur('840'));
      expect(reason.threshold, eur('850'));

      // Still below on 3 June: no new crossing. Back above on the 4th, below
      // again on the 5th: stops again.
      final second = advance(
        engine(),
        first.state,
        day(6, 30),
        crash,
        stops: stops,
      );
      expect(second.state.date, day(6, 5));
      expect(second.stop.single, isA<DrawdownStop>());
    });

    test(
      'contributions raise the bar: the threshold follows the money put in',
      () {
        final stops = StopConditions(drawdown: d('0.15'));
        final prices = {
          'cw8': series(
            'cw8',
            day(5, 25),
            day(6, 30),
            overrides: {day(6, 1): '90'},
          ),
        };
        // 1 000 € invested + 200 € arriving on 1 June: 900 + 200 cash = 1 100 €
        // is above 1 200 × 0.85 = 1 020 €.
        final result = advance(
          engine(contribution: eur('200')),
          invested1000(day(5, 29)),
          day(6, 1),
          prices,
          stops: stops,
        );
        expect(result.stop, isEmpty);
      },
    );

    test('a position losing more than the threshold', () {
      final stops = StopConditions(positionLoss: d('0.2'));
      final result = advance(engine(), invested1000(day(5, 29)), day(6, 30), {
        'cw8': series(
          'cw8',
          day(6, 1),
          day(6, 30),
          overrides: {day(6, 2): '79'},
        ),
      }, stops: stops);
      expect(result.state.date, day(6, 2));
      final reason = result.stop.single as PositionLossStop;
      expect(reason.assetId, 'cw8');
      expect(reason.loss, d('-0.21'));
    });

    test('an order the user placed fills', () {
      final state = TripState.start(day(5, 29), eur('1000')).copyWith(
        pendingOrders: [
          buy(
            'o1',
            'cw8',
            QuantitySize(Quantity.whole(1)),
            day(5, 29),
            limit: Price(d('95'), Currency.eur),
          ),
        ],
      );
      final result = advance(engine(), state, day(6, 30), {
        'cw8': series(
          'cw8',
          day(6, 1),
          day(6, 30),
          overrides: {day(6, 3): '94'},
        ),
      }, stops: const StopConditions(orderFilled: true));
      expect(result.state.date, day(6, 3));
      expect((result.stop.single as OrderFilledStop).orderId, 'o1');
    });

    test('an order waits for the first day it is eligible on', () {
      // The live wallet: a limit order placed during the session of 06-02
      // takes part from the next session on, not on the bar it saw start.
      final state = TripState.start(day(6, 1), eur('1000')).copyWith(
        pendingOrders: [
          buy(
            'o1',
            'cw8',
            QuantitySize(Quantity.whole(1)),
            day(6, 2),
            limit: Price(d('95'), Currency.eur),
          ),
        ],
      );
      final result = advance(
        engine(),
        state,
        day(6, 30),
        {
          'cw8': series(
            'cw8',
            day(6, 1),
            day(6, 30),
            overrides: {day(6, 2): '94', day(6, 4): '94'},
          ),
        },
        stops: const StopConditions(orderFilled: true),
        eligible: (order, day) => day.isAfter(order.createdAt),
      );
      expect(result.state.date, day(6, 4));
      expect(result.events.whereType<OrderFilled>().single.date, day(6, 4));
    });

    test('a DCA purchase does not count as the user\'s order', () {
      final state = TripState.start(day(5, 29), eur('1000')).copyWith(
        dcaPlans: [
          DcaPlan(
            id: 'p1',
            assetId: 'cw8',
            amount: eur('100'),
            frequency: DcaFrequency.weekly,
            start: day(6, 1),
          ),
        ],
      );
      final result = advance(engine(), state, day(6, 12), {
        'cw8': series('cw8', day(6, 1), day(6, 12)),
      }, stops: const StopConditions(orderFilled: true));
      expect(result.stop, isEmpty);
      expect(result.events.whereType<OrderFilled>(), hasLength(2));
    });

    test('a contribution arrives', () {
      final result = advance(
        engine(contribution: eur('200')),
        TripState.start(day(5, 20), eur('0')),
        day(6, 30),
        const {},
        stops: const StopConditions(contribution: true),
      );
      expect(result.state.date, day(6, 1));
      expect(result.stop.single, isA<ContributionStop>());
    });
  });

  group('limits', () {
    test('never reads data after the target day', () {
      // FakeMarket fails the test on any read after the target.
      final prices = {'cw8': series('cw8', day(6, 1), day(6, 30))};
      final result = advance(
        engine(),
        invested1000(day(5, 29)),
        day(6, 10),
        prices,
      );
      expect(result.state.date, day(6, 10));
    });

    test('an order on an asset without an earlier price reserves nothing', () {
      // AAPL's history starts on 1 June: on that morning nothing tells what its
      // order will cost, so the CW8 order may use all the cash.
      final state = TripState.start(day(5, 29), eur('100')).copyWith(
        pendingOrders: [
          buy('o1', 'cw8', QuantitySize(Quantity.whole(1)), day(5, 29)),
          buy('o2', 'aapl', AmountSize(eur('10')), day(5, 29)),
        ],
      );
      final result = advance(engine(), state, day(6, 1), {
        'cw8': series('cw8', day(5, 25), day(6, 1)),
        'aapl': series('aapl', day(6, 1), day(6, 1)),
      });
      final filled = result.events.whereType<OrderFilled>().map(
        (e) => e.order.id,
      );
      expect(filled, ['o1']);
      expect(result.events.whereType<OrderCancelled>().single.order.id, 'o2');
    });

    test('stops at the end of the data: the trip is at today', () {
      final result = advance(
        engine(),
        TripState.start(day(6, 1), eur('100')),
        day(6, 30),
        const {},
        lastDate: day(6, 3),
      );
      expect(result.state.date, day(6, 3));
      expect(result.atToday, isTrue);
    });

    test('landing on the last day of the data is at today too', () {
      Map<String, bool> endsAt(DateTime target) => {
        for (final t in [day(6, 2), target])
          '$t': advance(
            engine(),
            TripState.start(day(6, 1), eur('100')),
            t,
            const {},
            lastDate: day(6, 3),
          ).atToday,
      };
      expect(endsAt(day(6, 3)).values, [false, true]);
    });

    test('a stop on the last day of the data: stopped, and at today', () {
      // The June contribution lands on the 1st, the last day of the data.
      final result = advance(
        engine(contribution: eur('50')),
        TripState.start(day(5, 20), eur('100')),
        day(6, 30),
        const {},
        stops: const StopConditions(contribution: true),
        lastDate: day(6, 1),
      );
      expect(result.state.date, day(6, 1));
      expect(result.stop, isNotEmpty);
      expect(result.atToday, isTrue);
    });

    test('a stop before the last day of the data is not at today', () {
      final result = advance(
        engine(contribution: eur('50')),
        TripState.start(day(5, 20), eur('100')),
        day(6, 30),
        const {},
        stops: const StopConditions(contribution: true),
        lastDate: day(6, 3),
      );
      expect(result.state.date, day(6, 1));
      expect(result.atToday, isFalse);
    });

    test('already on or past the last day of the data: at today', () {
      for (final date in [day(6, 3), day(6, 4)]) {
        final result = advance(
          engine(),
          TripState.start(date, eur('100')),
          day(6, 30),
          const {},
          lastDate: day(6, 3),
        );
        expect(result.state.date, date);
        expect(result.events, isEmpty);
        expect(result.atToday, isTrue);
      }
    });

    test('a target on or before the current day changes nothing', () {
      final start = TripState.start(day(6, 3), eur('100'));
      final result = advance(engine(), start, day(6, 3), const {});
      expect(result.state, same(start));
      expect(result.events, isEmpty);
    });
  });
}
