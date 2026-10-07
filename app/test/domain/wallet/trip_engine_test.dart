import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
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

TripEngine engine({Money? contribution, TradingRules? rules}) => TripEngine(
  calendar: calendar,
  livretRates: rates,
  rules: rules ?? live,
  monthlyContribution: contribution ?? const Money.zero(Currency.eur),
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
}) => e.advance(
  state,
  target: target,
  stops: stops,
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
    expect(result.endOfData, isFalse);
    expect(result.stop, isEmpty);
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
      expect(result.events.map((e) => e.runtimeType), [
        ContributionCredited,
        OrderPlaced,
        OrderFilled,
        OrderFilled,
      ]);
      expect((result.events[1] as OrderPlaced).order.planId, 'p1');
      expect((result.events[2] as OrderFilled).order.planId, 'p1');
      expect((result.events[3] as OrderFilled).order.id, 'o1');
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

    test('stops at the end of the data', () {
      final result = advance(
        engine(),
        TripState.start(day(6, 1), eur('100')),
        day(6, 30),
        const {},
        lastDate: day(6, 3),
      );
      expect(result.state.date, day(6, 3));
      expect(result.endOfData, isTrue);
    });

    test('a target on or before the current day changes nothing', () {
      final start = TripState.start(day(6, 3), eur('100'));
      final result = advance(engine(), start, day(6, 3), const {});
      expect(result.state, same(start));
      expect(result.events, isEmpty);
    });
  });
}
