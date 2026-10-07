import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/order_matcher.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/validation.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String amount) => Money.book(d(amount), Currency.eur);
Price usd(String v) => Price(d(v), Currency.usd);
Price eurP(String v) => Price(d(v), Currency.eur);
Quantity q(String v) => Quantity.truncate(d(v));
final day = DateTime.utc(2026, 10, 12);

/// Live wallet: 0.15 % FX fee, fractional shares.
final live = TradingRules(
  fxFeeRate: d('0.0015'),
  fixedFee: const Money.zero(Currency.eur),
  fractionalShares: true,
);

/// "Serré": 0.15 % FX fee, 1 € per order, whole shares only.
final tight = TradingRules(
  fxFeeRate: d('0.0015'),
  fixedFee: eur('1'),
  fractionalShares: false,
);

Order order({
  Side side = Side.buy,
  OrderType type = OrderType.market,
  OrderSize? size,
  Price? limit,
  Price? stop,
  String asset = 'aapl',
}) => Order(
  id: 'o1',
  assetId: asset,
  side: side,
  type: type,
  size: size ?? AmountSize(eur('100')),
  limitPrice: limit,
  stopPrice: stop,
  createdAt: day,
);

PriceBar bar({
  required String open,
  required String high,
  required String low,
  String? close,
  Currency currency = Currency.usd,
}) => PriceBar(
  date: day.add(const Duration(days: 1)),
  open: d(open),
  high: d(high),
  low: d(low),
  close: d(close ?? open),
  volume: 0,
  currency: currency,
);

Fill filled(MatchResult result) => switch (result) {
  Filled(:final fill) => fill,
  _ => fail('expected a fill, got $result'),
};

void main() {
  group('fees', () {
    test('a EUR asset pays the fixed fee only', () {
      expect(orderFees(eur('1000'), Currency.eur, tight), eur('1'));
      expect(orderFees(eur('1000'), Currency.eur, live), eur('0'));
    });

    test('a USD asset pays notional × FX rate, booked, plus the fixed fee', () {
      expect(orderFees(eur('180'), Currency.usd, live), eur('0.27'));
      expect(orderFees(eur('360'), Currency.usd, tight), eur('1.54'));
      // 0.15 % of 3.33 € = 0.004995 € → 0.00 €.
      expect(orderFees(eur('3.33'), Currency.usd, live), eur('0'));
    });
  });

  group('matchOnBar: price rules (BRIEF §4.6)', () {
    MatchResult match(Order o, PriceBar b) => matchOnBar(
      o,
      b,
      rules: live,
      fxRate: Decimal.one,
      spendableCash: eur('100000'),
      heldQuantity: q('1000'),
    );
    final oneShare = QuantitySize(q('1'));

    test('market fills at the open', () {
      final f = filled(
        match(order(size: oneShare), bar(open: '100', high: '110', low: '90')),
      );
      expect(f.price, usd('100'));
      expect(f.date, day.add(const Duration(days: 1)));
    });

    test('limit buy: waits until low ≤ limit, fills at min(open, limit)', () {
      final o = order(type: OrderType.limit, size: oneShare, limit: usd('95'));
      expect(
        match(o, bar(open: '100', high: '105', low: '96')),
        isA<Unfilled>(),
      );
      expect(
        filled(match(o, bar(open: '100', high: '105', low: '94'))).price,
        usd('95'),
      );
      // Gap down below the limit: the open is better than the limit.
      expect(
        filled(match(o, bar(open: '90', high: '92', low: '88'))).price,
        usd('90'),
      );
    });

    test('limit sell: waits until high ≥ limit, fills at max(open, limit)', () {
      final o = order(
        side: Side.sell,
        type: OrderType.limit,
        size: oneShare,
        limit: usd('110'),
      );
      expect(
        match(o, bar(open: '100', high: '109', low: '95')),
        isA<Unfilled>(),
      );
      expect(
        filled(match(o, bar(open: '100', high: '112', low: '95'))).price,
        usd('110'),
      );
      expect(
        filled(match(o, bar(open: '115', high: '118', low: '113'))).price,
        usd('115'),
      );
    });

    test('stop sell: triggers when low ≤ stop, fills at min(open, stop)', () {
      final o = order(
        side: Side.sell,
        type: OrderType.stop,
        size: oneShare,
        stop: usd('90'),
      );
      expect(
        match(o, bar(open: '100', high: '105', low: '91')),
        isA<Unfilled>(),
      );
      expect(
        filled(match(o, bar(open: '100', high: '105', low: '85'))).price,
        usd('90'),
      );
      // Gap through the stop: filled at the open, below the stop. Slippage is
      // real and taught.
      expect(
        filled(match(o, bar(open: '80', high: '82', low: '78'))).price,
        usd('80'),
      );
    });

    test('stop buy: triggers when high ≥ stop, fills at max(open, stop)', () {
      final o = order(type: OrderType.stop, size: oneShare, stop: usd('110'));
      expect(
        match(o, bar(open: '100', high: '109', low: '95')),
        isA<Unfilled>(),
      );
      expect(
        filled(match(o, bar(open: '100', high: '112', low: '95'))).price,
        usd('110'),
      );
      expect(
        filled(match(o, bar(open: '120', high: '121', low: '118'))).price,
        usd('120'),
      );
    });

    test('a trigger price in another currency than the bar is a bug', () {
      final o = order(type: OrderType.limit, size: oneShare, limit: eurP('95'));
      expect(
        () => match(o, bar(open: '100', high: '105', low: '94')),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });
  });

  group('matchOnBar: quantity, fees, cash', () {
    MatchResult match(
      Order o,
      PriceBar b, {
      TradingRules? rules,
      String cash = '100000',
      String held = '1000',
    }) => matchOnBar(
      o,
      b,
      rules: rules ?? live,
      fxRate: d('0.9'),
      spendableCash: eur(cash),
      heldQuantity: q(held),
    );
    final at200 = bar(open: '200', high: '200', low: '200');

    test(
      'an amount order buys amount / (price × rate), truncated to 6 decimals',
      () {
        final f = filled(match(order(size: AmountSize(eur('100'))), at200));
        expect(f.quantity, q('0.555555'));
        expect(f.fxRate, d('0.9'));
        // 200 × 0.555555 × 0.9 = 99.9999 → 100.00 €, fees 0.15 % on top.
        expect(f.notional, eur('100'));
        expect(f.fees, eur('0.15'));
        expect(f.cashFlow, eur('-100.15'));
      },
    );

    test('a quantity order buys that quantity', () {
      final f = filled(match(order(size: QuantitySize(q('2'))), at200));
      expect(f.quantity, q('2'));
      expect(f.notional, eur('360'));
      expect(f.fees, eur('0.54'));
    });

    test('whole-share wallets floor an amount to whole shares', () {
      final f = filled(
        match(order(size: AmountSize(eur('500'))), at200, rules: tight),
      );
      expect(f.quantity, q('2'));
      expect(f.notional, eur('360'));
      expect(f.fees, eur('1.54'));
    });

    test('an amount that buys no whole share is cancelled', () {
      expect(
        match(order(size: AmountSize(eur('150'))), at200, rules: tight),
        isA<Cancelled>().having(
          (c) => c.reason,
          'reason',
          CancelReason.amountBelowOneShare,
        ),
      );
    });

    test(
      'a buy that cash cannot pay at execution is cancelled, not partly filled',
      () {
        expect(
          match(order(size: QuantitySize(q('2'))), at200, cash: '360.53'),
          isA<Cancelled>().having(
            (c) => c.reason,
            'reason',
            CancelReason.insufficientCash,
          ),
        );
        expect(
          match(order(size: QuantitySize(q('2'))), at200, cash: '360.54'),
          isA<Filled>(),
        );
      },
    );

    test('a sell above the shares held at execution is cancelled', () {
      expect(
        match(
          order(side: Side.sell, size: QuantitySize(q('3'))),
          at200,
          held: '2',
        ),
        isA<Cancelled>().having(
          (c) => c.reason,
          'reason',
          CancelReason.insufficientQuantity,
        ),
      );
      // An amount sell needing more shares than held, after the price fell.
      expect(
        match(
          order(side: Side.sell, size: AmountSize(eur('400'))),
          at200,
          held: '2',
        ),
        isA<Cancelled>().having(
          (c) => c.reason,
          'reason',
          CancelReason.insufficientQuantity,
        ),
      );
    });

    test('a sell receives notional minus fees', () {
      final f = filled(
        match(
          order(side: Side.sell, size: QuantitySize(q('1'))),
          at200,
          rules: tight,
        ),
      );
      expect(f.cashFlow, eur('178.73'));
    });

    test('a sell whose fees eat the proceeds is cancelled', () {
      final cheap = bar(open: '1', high: '1', low: '1', currency: Currency.eur);
      expect(
        matchOnBar(
          order(side: Side.sell, size: QuantitySize(q('1')), asset: 'penny'),
          cheap,
          rules: tight,
          fxRate: Decimal.one,
          spendableCash: eur('0'),
          heldQuantity: q('1'),
        ),
        isA<Cancelled>().having(
          (c) => c.reason,
          'reason',
          CancelReason.proceedsBelowFees,
        ),
      );
    });
  });

  group('fillAtQuote (live, market open)', () {
    final at = DateTime.utc(2026, 10, 12, 14, 0);

    test('a market order fills at the quote, timestamped', () {
      final result = fillAtQuote(
        order(size: QuantitySize(q('1'))),
        usd('200'),
        at: at,
        rules: live,
        fxRate: d('0.9'),
        spendableCash: eur('1000'),
        heldQuantity: const Quantity.zero(),
      );
      final f = filled(result);
      expect(f.price, usd('200'));
      expect(f.date, at);
      expect(f.cashFlow, eur('-180.27'));
    });

    test('only market orders fill at a quote', () {
      expect(
        () => fillAtQuote(
          order(type: OrderType.limit, limit: usd('1')),
          usd('200'),
          at: at,
          rules: live,
          fxRate: d('0.9'),
          spendableCash: eur('1000'),
          heldQuantity: const Quantity.zero(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('validateOrder', () {
    List<String> codes(
      Order o, {
      TradingRules? rules,
      Price? reference,
      String fx = '0.9',
      String cash = '1000',
      String held = '0',
    }) => [
      for (final f in validateOrder(
        o,
        rules: rules ?? live,
        referencePrice: reference,
        fxRate: d(fx),
        availableCash: eur(cash),
        availableQuantity: q(held),
      ))
        f.code,
    ];
    final ref = usd('200');

    test('a valid order has no failure', () {
      expect(codes(order(), reference: ref), isEmpty);
    });

    test('non-positive sizes', () {
      expect(codes(order(size: AmountSize(eur('0'))), reference: ref), [
        'amount_not_positive',
      ]);
      expect(codes(order(size: AmountSize(eur('-5'))), reference: ref), [
        'amount_not_positive',
      ]);
      expect(codes(order(size: QuantitySize(q('0'))), reference: ref), [
        'quantity_not_positive',
      ]);
    });

    test('whole-share wallets reject fractional quantities', () {
      expect(
        codes(
          order(size: QuantitySize(q('1.5'))),
          rules: tight,
          reference: ref,
        ),
        ['quantity_not_whole'],
      );
      expect(
        codes(order(size: QuantitySize(q('1.5'))), reference: ref),
        isEmpty,
      );
    });

    test('whole-share wallets reject an amount that buys no share', () {
      final failures = validateOrder(
        order(size: AmountSize(eur('150'))),
        rules: tight,
        referencePrice: ref,
        fxRate: d('0.9'),
        availableCash: eur('1000'),
        availableQuantity: q('0'),
      );
      expect(failures.single.code, 'amount_below_one_share');
      expect(failures.single.params, {'price': ref});
    });

    test('limit and stop orders need a positive price', () {
      expect(
        codes(
          order(type: OrderType.limit, size: QuantitySize(q('1'))),
          reference: ref,
        ),
        ['limit_price_not_positive'],
      );
      expect(
        codes(
          order(
            type: OrderType.limit,
            size: QuantitySize(q('1')),
            limit: usd('0'),
          ),
          reference: ref,
        ),
        ['limit_price_not_positive'],
      );
      expect(
        codes(
          order(
            type: OrderType.stop,
            size: QuantitySize(q('1')),
            stop: usd('-1'),
          ),
          reference: ref,
        ),
        ['stop_price_not_positive'],
      );
    });

    test('an asset without a price at asOf is unavailable', () {
      expect(codes(order()), ['asset_unavailable']);
    });

    test('a buy must fit in the available cash, fees included', () {
      // 1 000 € at 0.15 % FX fee costs 1 001,50 €.
      final failures = validateOrder(
        order(size: AmountSize(eur('1000'))),
        rules: live,
        referencePrice: ref,
        fxRate: d('0.9'),
        availableCash: eur('1001.49'),
        availableQuantity: q('0'),
      );
      expect(failures.single.code, 'insufficient_cash');
      expect(failures.single.params, {'cash': eur('1001.49')});
      expect(
        codes(
          order(size: AmountSize(eur('1000'))),
          reference: ref,
          cash: '1001.50',
        ),
        isEmpty,
      );
    });

    test('a limit buy by quantity is costed at its limit', () {
      final o = order(
        type: OrderType.limit,
        size: QuantitySize(q('5')),
        limit: usd('150'),
      );
      // 5 × 150 × 0.9 = 675 € + 1.01 € FX fee.
      expect(codes(o, reference: ref, cash: '676.01'), isEmpty);
      expect(codes(o, reference: ref, cash: '676'), ['insufficient_cash']);
    });

    test('a sell must not exceed the shares available', () {
      final failures = validateOrder(
        order(side: Side.sell, size: QuantitySize(q('3'))),
        rules: live,
        referencePrice: ref,
        fxRate: d('0.9'),
        availableCash: eur('0'),
        availableQuantity: q('2'),
      );
      expect(failures.single.code, 'insufficient_quantity');
      expect(failures.single.params, {'held': q('2')});
      // 500 € at 180 € a share needs 2.78 shares.
      expect(
        codes(
          order(side: Side.sell, size: AmountSize(eur('500'))),
          reference: ref,
          held: '2',
        ),
        ['insufficient_quantity'],
      );
      expect(
        codes(
          order(side: Side.sell, size: AmountSize(eur('300'))),
          reference: ref,
          held: '2',
        ),
        isEmpty,
      );
    });

    test('a sell smaller than its fees is rejected', () {
      final failures = validateOrder(
        order(side: Side.sell, size: AmountSize(eur('1')), asset: 'penny'),
        rules: tight,
        referencePrice: eurP('0.5'),
        fxRate: Decimal.one,
        availableCash: eur('0'),
        availableQuantity: q('10'),
      );
      expect(failures.single.code, 'amount_below_fees');
      expect(failures.single.params, {'fees': eur('1')});
    });

    test('independent problems are all reported', () {
      expect(
        codes(
          order(type: OrderType.limit, size: QuantitySize(q('0'))),
          reference: ref,
        ),
        ['quantity_not_positive', 'limit_price_not_positive'],
      );
    });

    test('every failure is a ValidationFailure with a code', () {
      final failures = validateOrder(
        order(size: AmountSize(eur('0'))),
        rules: live,
        referencePrice: null,
        fxRate: d('0.9'),
        availableCash: eur('0'),
        availableQuantity: q('0'),
      );
      expect(failures, everyElement(isA<ValidationFailure>()));
      expect(failures.map((f) => f.code), everyElement(isNotEmpty));
    });
  });

  group('reservations (pending orders)', () {
    test('an amount buy reserves amount + fees on the amount', () {
      expect(
        cashToReserve(
          order(size: AmountSize(eur('100'))),
          rules: live,
          referencePrice: usd('200'),
          fxRate: d('0.9'),
        ),
        eur('100.15'),
      );
    });

    test(
      'a quantity buy reserves at its limit, its stop, or the last price',
      () {
        final qty = QuantitySize(q('2'));
        expect(
          cashToReserve(
            order(type: OrderType.limit, size: qty, limit: usd('150')),
            rules: live,
            referencePrice: usd('200'),
            fxRate: d('0.9'),
          ),
          eur('270.40'), // 0.405 € fee → 0.40 € (half-even)
        );
        expect(
          cashToReserve(
            order(type: OrderType.stop, size: qty, stop: usd('210')),
            rules: live,
            referencePrice: usd('200'),
            fxRate: d('0.9'),
          ),
          eur('378.57'),
        );
        expect(
          cashToReserve(
            order(size: qty),
            rules: live,
            referencePrice: usd('200'),
            fxRate: d('0.9'),
          ),
          eur('360.54'),
        );
      },
    );

    test('sells reserve shares, not cash', () {
      final sell = order(side: Side.sell, size: AmountSize(eur('90')));
      expect(
        cashToReserve(
          sell,
          rules: live,
          referencePrice: usd('200'),
          fxRate: d('0.9'),
        ),
        eur('0'),
      );
      expect(
        quantityToReserve(
          sell,
          rules: live,
          referencePrice: usd('200'),
          fxRate: d('0.9'),
        ),
        q('0.5'),
      );
      expect(
        quantityToReserve(
          order(side: Side.sell, size: QuantitySize(q('3'))),
          rules: live,
          referencePrice: usd('200'),
          fxRate: d('0.9'),
        ),
        q('3'),
      );
      expect(
        quantityToReserve(
          order(),
          rules: live,
          referencePrice: usd('200'),
          fxRate: d('0.9'),
        ),
        q('0'),
      );
    });
  });
}
