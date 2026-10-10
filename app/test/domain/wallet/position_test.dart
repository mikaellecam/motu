import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int m, int dd) => DateTime.utc(2026, m, dd);

Fill fill(
  Side side,
  String qty,
  String price, {
  String asset = 'cw8',
  Currency currency = Currency.eur,
  String fx = '1',
  int feeCents = 0,
  DateTime? date,
}) => Fill(
  assetId: asset,
  side: side,
  date: date ?? day(1, 5),
  quantity: Quantity.truncate(d(qty)),
  price: Price(d(price), currency),
  fxRate: d(fx),
  fees: Money(feeCents, Currency.eur),
);

void main() {
  group('Fill', () {
    test('notional is booked in EUR, half-even', () {
      expect(
        fill(Side.buy, '3', '10.50').notional,
        const Money(3150, Currency.eur),
      );
      expect(
        fill(Side.buy, '2', '100', currency: Currency.usd, fx: '0.9').notional,
        const Money(18000, Currency.eur),
      );
      // 1.005 € → 1.00 € (tie to even), 1.015 € → 1.02 €.
      expect(
        fill(Side.buy, '1', '1.005').notional,
        const Money(100, Currency.eur),
      );
      expect(
        fill(Side.buy, '1', '1.015').notional,
        const Money(102, Currency.eur),
      );
    });

    test(
      'a buy costs notional plus fees; a sell yields notional minus fees',
      () {
        expect(
          fill(Side.buy, '1', '100', feeCents: 150).cashFlow,
          const Money(-10150, Currency.eur),
        );
        expect(
          fill(Side.sell, '1', '100', feeCents: 150).cashFlow,
          const Money(9850, Currency.eur),
        );
      },
    );
  });

  group('positionsFrom (average cost)', () {
    test('no fills, no positions', () {
      expect(positionsFrom(const []), isEmpty);
    });

    test('one buy: cost basis includes fees', () {
      final p = positionsFrom([
        fill(Side.buy, '2', '50', feeCents: 100),
      ])['cw8']!;
      expect(p.quantity, Quantity.whole(2));
      expect(p.costBasis, d('101'));
      expect(p.averageCost, d('50.5'));
      expect(p.realisedPnl, Decimal.zero);
      expect(p.isOpen, isTrue);
    });

    test('buys at different prices average their costs', () {
      final p = positionsFrom([
        fill(Side.buy, '1', '100'),
        fill(Side.buy, '3', '120'),
      ])['cw8']!;
      expect(p.quantity, Quantity.whole(4));
      expect(p.costBasis, d('460'));
      expect(p.averageCost, d('115'));
    });

    test('a USD asset is costed in EUR at the fill rate', () {
      final p = positionsFrom([
        fill(
          Side.buy,
          '2',
          '100',
          asset: 'aapl',
          currency: Currency.usd,
          fx: '0.9',
          feeCents: 27,
        ),
      ])['aapl']!;
      expect(p.costBasis, d('180.27'));
    });

    test('a sell keeps the average cost and realises P&L', () {
      final p = positionsFrom([
        fill(Side.buy, '4', '100'),
        fill(Side.sell, '1', '130', feeCents: 200),
      ])['cw8']!;
      expect(p.quantity, Quantity.whole(3));
      expect(p.averageCost, d('100'));
      expect(p.costBasis, d('300'));
      // Proceeds 130 − 2 fees = 128, minus 1 × 100 average cost.
      expect(p.realisedPnl, d('28'));
    });

    test('a losing sell realises a negative P&L', () {
      final p = positionsFrom([
        fill(Side.buy, '2', '100'),
        fill(Side.sell, '2', '80'),
      ])['cw8']!;
      expect(p.realisedPnl, d('-40'));
    });

    test('selling everything closes the position', () {
      final p = positionsFrom([
        fill(Side.buy, '3', '10', feeCents: 30),
        fill(Side.sell, '3', '12'),
      ])['cw8']!;
      expect(p.quantity, const Quantity.zero());
      expect(p.costBasis, Decimal.zero);
      expect(p.averageCost, isNull);
      expect(p.isOpen, isFalse);
      expect(p.realisedPnl, d('5.7'));
    });

    test('buying again after closing starts a fresh average', () {
      final p = positionsFrom([
        fill(Side.buy, '1', '10'),
        fill(Side.sell, '1', '20'),
        fill(Side.buy, '2', '30'),
      ])['cw8']!;
      expect(p.averageCost, d('30'));
      expect(p.realisedPnl, d('10'));
    });

    test('fractional sells keep the average exact', () {
      final p = positionsFrom([
        fill(Side.buy, '3', '10'),
        fill(Side.sell, '1', '10'),
        fill(Side.sell, '0.333333', '10'),
      ])['cw8']!;
      expect(p.quantity.toDecimal(), d('1.666667'));
      expect(p.averageCost, d('10'));
      // 0.333333 × 10 = 3.33333 € of cost, but the cash booked is 3.33 €.
      expect(p.realisedPnl, d('-0.00333'));
    });

    test('assets are tracked separately', () {
      final positions = positionsFrom([
        fill(Side.buy, '1', '10', asset: 'cw8'),
        fill(Side.buy, '2', '20', asset: 'mc'),
        fill(Side.sell, '1', '12', asset: 'cw8'),
      ]);
      expect(positions.keys, unorderedEquals(['cw8', 'mc']));
      expect(positions['mc']!.quantity, Quantity.whole(2));
      expect(positions['cw8']!.isOpen, isFalse);
    });

    test('selling more than held is corrupt data', () {
      expect(
        () => positionsFrom([
          fill(Side.buy, '1', '10'),
          fill(Side.sell, '2', '10'),
        ]),
        throwsStateError,
      );
      expect(
        () => positionsFrom([fill(Side.sell, '1', '10')]),
        throwsStateError,
      );
    });

    test('a fill without a positive quantity is corrupt data', () {
      expect(
        () => positionsFrom([fill(Side.buy, '0', '10')]),
        throwsStateError,
      );
    });

    test('fills must come in date order', () {
      expect(
        () => positionsFrom([
          fill(Side.buy, '1', '10', date: day(2, 1)),
          fill(Side.buy, '1', '10', date: day(1, 1)),
        ]),
        throwsStateError,
      );
    });
  });

  group('currency effect', () {
    Fill usd(Side side, String qty, String price, String fx) => fill(
      side,
      qty,
      price,
      asset: 'aapl',
      currency: Currency.usd,
      fx: fx,
      feeCents: 150,
    );

    test('one buy: its own rate, fees left out', () {
      expect(
        averagePurchaseRate([usd(Side.buy, '10', '100', '0.9')], 'aapl'),
        d('0.9'),
      );
    });

    test('two buys: weighted by the dollars spent', () {
      // 1 000 $ at 0,90 and 3 000 $ at 0,80: 3 300 € for 4 000 $.
      final rate = averagePurchaseRate([
        usd(Side.buy, '10', '100', '0.9'),
        usd(Side.buy, '20', '150', '0.8'),
      ], 'aapl');
      expect(rate, d('0.825'));
    });

    test('a sell keeps the average; selling everything leaves none', () {
      final fills = [
        usd(Side.buy, '10', '100', '0.9'),
        usd(Side.buy, '20', '150', '0.8'),
        usd(Side.sell, '15', '160', '0.95'),
      ];
      expect(averagePurchaseRate(fills, 'aapl'), d('0.825'));
      expect(
        averagePurchaseRate([
          ...fills,
          usd(Side.sell, '15', '160', '0.95'),
        ], 'aapl'),
        isNull,
      );
      expect(
        averagePurchaseRate(fills, 'other'),
        isNull,
        reason: 'never bought',
      );
      expect(averagePurchaseRate(const [], 'aapl'), isNull);
    });

    test('the part of the value the currency made', () {
      // 10 shares at 120 $: 1 200 $ worth 1 020 € at 0,85, 1 080 € at 0,90.
      expect(
        currencyEffect(
          quantity: Quantity.whole(10),
          price: Price(d('120'), Currency.usd),
          fxNow: d('0.85'),
          averageRate: d('0.9'),
        ),
        d('-60'),
      );
      expect(
        currencyEffect(
          quantity: Quantity.whole(10),
          price: Price(d('50'), Currency.eur),
          fxNow: Decimal.one,
          averageRate: Decimal.one,
        ),
        Decimal.zero,
      );
    });
  });
}
