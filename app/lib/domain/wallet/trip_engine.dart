import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../analytics/returns.dart';
import '../companion/events.dart';
import '../companion/rules.dart';
import '../learning/profile_rules.dart';
import '../livret/livret_interest.dart';
import '../market/market_calendar.dart';
import '../market/price_bar.dart';
import 'dca.dart';
import 'order.dart';
import 'order_matcher.dart';
import 'position.dart';
import 'valuation.dart';

/// The market as a trip sees it: a snapshot the data layer loads from its
/// cache. The engine never asks for a date after the day it is computing.
abstract interface class TripMarket {
  /// The last date with data: a trip cannot advance past it.
  DateTime get lastDate;

  /// [assetId]'s bar on [date]; null when its exchange did not trade.
  PriceBar? bar(String assetId, DateTime date);

  /// The price to value [assetId] with at the end of [date], stale flag
  /// included; null when no bar exists on or before [date].
  PriceAsOf? priceAsOf(String assetId, DateTime date);

  /// EUR per unit of [currency], the latest rate on or before [date].
  Decimal fxRate(Currency currency, DateTime date);

  Exchange exchangeOf(String assetId);
}

/// A trip wallet at the end of a simulated day.
final class TripState {
  const TripState({
    required this.date,
    required this.cash,
    required this.invested,
    required this.fills,
    required this.positions,
    required this.pendingOrders,
    required this.dcaPlans,
    required this.livret,
    required this.values,
    required this.breached,
    required this.companion,
    required this.companionLog,
  });

  /// A trip leaving on [date] with [cash].
  TripState.start(DateTime date, Money cash)
    : this(
        date: date,
        cash: cash,
        invested: cash,
        fills: const [],
        positions: const {},
        pendingOrders: const [],
        dcaPlans: const [],
        livret: LivretAccount.empty(date),
        values: [DailyValue(date: date, value: cash, flow: cash)],
        breached: const {},
        companion: CompanionTracker.empty(),
        companionLog: const [],
      );

  /// The simulated day, seen after its close.
  final DateTime date;
  final Money cash;

  /// Money put in: starting cash + contributions.
  final Money invested;
  final List<Fill> fills;

  /// Derived from [fills], kept up to date fill by fill.
  final Map<String, Position> positions;
  final List<Order> pendingOrders;
  final List<DcaPlan> dcaPlans;
  final LivretAccount livret;

  /// One row per trip day: the `wallet_values` series.
  final List<DailyValue> values;

  /// Threshold stop conditions that held at the last evaluation; they fire
  /// again only after being false once.
  final Set<String> breached;

  /// The companion's running facts, and the moments it already showed.
  final CompanionTracker companion;
  final List<CompanionLogEntry> companionLog;

  TripState copyWith({
    DateTime? date,
    Money? cash,
    Money? invested,
    List<Fill>? fills,
    Map<String, Position>? positions,
    List<Order>? pendingOrders,
    List<DcaPlan>? dcaPlans,
    LivretAccount? livret,
    List<DailyValue>? values,
    Set<String>? breached,
    CompanionTracker? companion,
    List<CompanionLogEntry>? companionLog,
  }) => TripState(
    date: date ?? this.date,
    cash: cash ?? this.cash,
    invested: invested ?? this.invested,
    fills: fills ?? this.fills,
    positions: positions ?? this.positions,
    pendingOrders: pendingOrders ?? this.pendingOrders,
    dcaPlans: dcaPlans ?? this.dcaPlans,
    livret: livret ?? this.livret,
    values: values ?? this.values,
    breached: breached ?? this.breached,
    companion: companion ?? this.companion,
    companionLog: companionLog ?? this.companionLog,
  );
}

/// When a trip stops by itself (BRIEF §4.5). Null thresholds and false flags
/// are off.
final class StopConditions {
  const StopConditions({
    this.drawdown,
    this.positionLoss,
    this.orderFilled = false,
    this.contribution = false,
  });

  /// Stop when the value falls below the money put in × (1 − drawdown).
  final Decimal? drawdown;

  /// Stop when a position's unrealised loss exceeds this share of its cost.
  final Decimal? positionLoss;

  /// Stop when an order the user placed fills (DCA purchases don't count).
  final bool orderFilled;

  /// Stop when a monthly contribution arrives.
  final bool contribution;
}

sealed class TripEvent {
  const TripEvent(this.date);
  final DateTime date;
}

final class ContributionCredited extends TripEvent {
  const ContributionCredited(super.date, this.amount);
  final Money amount;
}

/// A DCA plan placed an order.
final class OrderPlaced extends TripEvent {
  const OrderPlaced(super.date, this.order);
  final Order order;
}

final class OrderFilled extends TripEvent {
  const OrderFilled(super.date, this.order, this.fill);
  final Order order;
  final Fill fill;
}

/// A companion rule fired: a card to show, never a reason to stop.
final class MomentFired extends TripEvent {
  MomentFired(this.moment) : super(moment.date);
  final Moment moment;
}

final class OrderCancelled extends TripEvent {
  const OrderCancelled(super.date, this.order, this.reason);
  final Order order;
  final CancelReason reason;
}

sealed class StopReason {
  const StopReason();
}

final class DrawdownStop extends StopReason {
  const DrawdownStop({required this.value, required this.threshold});
  final Money value;

  /// The line the value crossed: money put in × (1 − drawdown).
  final Money threshold;
}

final class PositionLossStop extends StopReason {
  const PositionLossStop(this.assetId, this.loss);
  final String assetId;

  /// Unrealised P&L over cost basis, negative.
  final Decimal loss;
}

final class OrderFilledStop extends StopReason {
  const OrderFilledStop(this.orderId);
  final String orderId;
}

final class ContributionStop extends StopReason {
  const ContributionStop(this.amount);
  final Money amount;
}

final class TripAdvance {
  const TripAdvance({
    required this.state,
    required this.events,
    required this.stop,
    required this.endOfData,
  });

  final TripState state;

  /// What happened, in order.
  final List<TripEvent> events;

  /// Why the trip stopped on `state.date`; empty when it did not.
  final List<StopReason> stop;

  /// The target lies beyond the data: the trip went as far as it could.
  final bool endOfData;
}

/// Moves a trip forward through history (BRIEF §4.5).
final class TripEngine {
  const TripEngine({
    required this.calendar,
    required this.exchanges,
    required this.livretRates,
    required this.rules,
    required this.monthlyContribution,
    required this.thresholds,
  });

  final MarketCalendar calendar;

  /// The exchanges the catalogue's assets trade on.
  final Set<Exchange> exchanges;
  final List<LivretRate> livretRates;
  final TradingRules rules;

  /// Credited on the first trip day of each month; zero for none.
  final Money monthlyContribution;

  /// Companion thresholds of the user's profile.
  final MomentThresholds thresholds;

  /// A trip day is a day when any of the catalogue's [exchanges] trades
  /// (decided 2026-10-07): an asset whose exchange is closed keeps its last
  /// close and its orders wait.
  bool isTripDay(DateTime date) =>
      exchanges.any((exchange) => calendar.isTradingDay(exchange, date));

  DateTime _nextTripDay(DateTime date) {
    var next = DateTime.utc(date.year, date.month, date.day + 1);
    while (!isTripDay(next)) {
      next = DateTime.utc(next.year, next.month, next.day + 1);
    }
    return next;
  }

  /// Advances [state] one trip day at a time up to [target], or to the last
  /// date of the data. Each day, in order:
  ///
  /// 1. the monthly contribution, on the first trip day of a month;
  /// 2. DCA plans due that day place € market orders, filled at the open;
  /// 3. pending orders run through the matcher on the day's bar;
  /// 4. the Livret closes the fortnights that ended;
  /// 5. end-of-day valuation, appended to the value series;
  /// 6. companion rules (moments become events), then stop conditions: when
  ///    one fires, the trip stops after that day.
  ///
  /// Reads nothing dated after the day being computed.
  TripAdvance advance(
    TripState state, {
    required DateTime target,
    required StopConditions stops,
    required TripMarket market,
  }) {
    final end = target.isAfter(market.lastDate) ? market.lastDate : target;
    final dueDates = {
      for (final plan in state.dcaPlans.where((p) => p.active))
        plan.id: dcaSchedule(
          start: plan.start,
          end: end,
          frequency: plan.frequency,
          calendar: calendar,
          exchange: market.exchangeOf(plan.assetId),
        ).toSet(),
    };
    final events = <TripEvent>[];
    var current = state;
    for (
      var day = _nextTripDay(current.date);
      !day.isAfter(end);
      day = _nextTripDay(day)
    ) {
      final (next, dayEvents, reasons) = _runDay(
        current,
        day,
        dueDates,
        stops,
        market,
      );
      current = next;
      events.addAll(dayEvents);
      if (reasons.isNotEmpty) {
        return TripAdvance(
          state: current,
          events: events,
          stop: reasons,
          endOfData: false,
        );
      }
    }
    return TripAdvance(
      state: current,
      events: events,
      stop: const [],
      endOfData: target.isAfter(market.lastDate),
    );
  }

  (TripState, List<TripEvent>, List<StopReason>) _runDay(
    TripState s,
    DateTime day,
    Map<String, Set<DateTime>> dueDates,
    StopConditions stops,
    TripMarket market,
  ) {
    final events = <TripEvent>[];
    var cash = s.cash;
    var invested = s.invested;
    var flow = const Money.zero(Currency.eur);
    final fills = [...s.fills];
    final positions = {...s.positions};

    // 1. Contribution, on the first trip day of a month.
    if (monthlyContribution.isPositive &&
        (day.month != s.date.month || day.year != s.date.year)) {
      cash += monthlyContribution;
      invested += monthlyContribution;
      flow += monthlyContribution;
      events.add(ContributionCredited(day, monthlyContribution));
    }

    // 2. DCA plans due today, then 3. orders waiting since before today.
    final planOrders = [
      for (final plan in s.dcaPlans)
        if (plan.active && (dueDates[plan.id]?.contains(day) ?? false))
          Order(
            id: 'dca-${plan.id}-${day.toIso8601String().substring(0, 10)}',
            assetId: plan.assetId,
            side: Side.buy,
            type: OrderType.market,
            size: AmountSize(plan.amount),
            createdAt: day,
            planId: plan.id,
          ),
    ];
    events.addAll([for (final order in planOrders) OrderPlaced(day, order)]);
    final queue = [...planOrders, ...s.pendingOrders];
    final pending = <Order>[];
    for (var i = 0; i < queue.length; i++) {
      final order = queue[i];
      final bar = market.bar(order.assetId, day);
      if (bar == null) {
        pending.add(order);
        continue;
      }
      // Other buys still waiting keep what they reserve.
      final waiting = [...pending, ...queue.skip(i + 1)];
      final result = matchOnBar(
        order,
        bar,
        rules: rules,
        fxRate: market.fxRate(bar.currency, day),
        spendableCash: cash - _reserved(waiting, s.date, market),
        heldQuantity:
            positions[order.assetId]?.quantity ?? const Quantity.zero(),
      );
      switch (result) {
        case Filled(:final fill):
          cash += fill.cashFlow;
          positions[fill.assetId] = applyFill(positions[fill.assetId], fill);
          fills.add(fill);
          events.add(OrderFilled(day, order, fill));
        case Cancelled(:final reason):
          events.add(OrderCancelled(day, order, reason));
        case Unfilled():
          pending.add(order);
      }
    }

    // 4. Livret.
    final livret = s.livret.advanceTo(day, livretRates);

    // 5. Valuation.
    final prices = {
      for (final position in positions.values.where((p) => p.isOpen))
        position.assetId: market.priceAsOf(position.assetId, day)!,
    };
    final valuation = valueWallet(
      cash: cash,
      positions: positions,
      prices: prices,
      fxRates: {
        for (final price in prices.values)
          if (price.price.currency != Currency.eur)
            price.price.currency: market.fxRate(price.price.currency, day),
      },
      livret: livret.balance.amount + livret.accrued,
    );
    final value = Money.book(valuation.total, Currency.eur);

    // 6. Companion moments, then stop conditions.
    final total = valuation.total;
    Decimal share(Decimal part) =>
        total > Decimal.zero ? ratio(part, total) : Decimal.zero;
    final (companion, moments) = s.companion.observe(
      DaySnapshot(
        date: day,
        value: total,
        flow: flow.amount,
        cashWeight: share(cash.amount),
        holdings: [
          for (final h in valuation.holdings)
            HoldingFacts(
              assetId: h.position.assetId,
              price: h.price.price,
              weight: share(h.marketValue),
              pnlRatio: h.unrealisedPnlRatio,
            ),
        ],
        sells: [
          for (final event in events.whereType<OrderFilled>())
            if (event.fill.side == Side.sell)
              SellFact(event.fill.assetId, event.fill.price),
        ],
        usdRate: market.fxRate(Currency.usd, day),
        priceOf: (assetId) => market.priceAsOf(assetId, day)?.price,
      ),
      log: s.companionLog,
      thresholds: thresholds,
    );
    events.addAll(moments.map(MomentFired.new));

    // Thresholds fire when they start to hold.
    final breached = <String>{};
    final reasons = <StopReason>[];
    void crossing(String key, bool holds, StopReason Function() reason) {
      if (!holds) return;
      breached.add(key);
      if (!s.breached.contains(key)) reasons.add(reason());
    }

    if (stops.drawdown case final drawdown?) {
      final line = Money.book(
        invested.amount * (Decimal.one - drawdown),
        Currency.eur,
      );
      crossing(
        'drawdown',
        value < line,
        () => DrawdownStop(value: value, threshold: line),
      );
    }
    if (stops.positionLoss case final limit?) {
      for (final holding in valuation.holdings) {
        final loss = holding.unrealisedPnlRatio;
        crossing(
          'position:${holding.position.assetId}',
          loss != null && loss < -limit,
          () => PositionLossStop(holding.position.assetId, loss!),
        );
      }
    }
    if (stops.orderFilled) {
      reasons.addAll([
        for (final event in events.whereType<OrderFilled>())
          if (event.order.planId == null) OrderFilledStop(event.order.id),
      ]);
    }
    if (stops.contribution && flow.isPositive) {
      reasons.add(ContributionStop(flow));
    }

    final next = TripState(
      date: day,
      cash: cash,
      invested: invested,
      fills: fills,
      positions: positions,
      pendingOrders: pending,
      dcaPlans: s.dcaPlans,
      livret: livret,
      values: [
        ...s.values,
        DailyValue(date: day, value: value, flow: flow),
      ],
      breached: breached,
      companion: companion,
      companionLog: [...s.companionLog, ...moments.map((m) => m.logEntry)],
    );
    return (next, events, reasons);
  }

  /// Cash that [orders] hold back, estimated at prices known on [asOf].
  Money _reserved(List<Order> orders, DateTime asOf, TripMarket market) {
    var total = const Money.zero(Currency.eur);
    for (final order in orders.where((o) => o.side == Side.buy)) {
      final reference = market.priceAsOf(order.assetId, asOf)?.price;
      if (reference == null) continue;
      total += cashToReserve(
        order,
        rules: rules,
        referencePrice: reference,
        fxRate: market.fxRate(reference.currency, asOf),
      );
    }
    return total;
  }
}
