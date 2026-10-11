import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/order_ticket.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(d(s), Currency.eur);
Price usd(String s) => Price(d(s), Currency.usd);

final rules = TradingRules(
  fxFeeRate: d('0.0015'),
  fixedFee: eur('1'),
  fractionalShares: true,
);
final whole = TradingRules(
  fxFeeRate: d('0.0015'),
  fixedFee: eur('1'),
  fractionalShares: false,
);

Order order(
  Side side,
  OrderSize size, {
  OrderType type = OrderType.market,
  Price? limit,
}) => Order(
  id: 'o',
  assetId: 'apple',
  side: side,
  type: type,
  size: size,
  limitPrice: limit,
  createdAt: DateTime.utc(2026, 10, 11),
);

void main() {
  group('estimate', () {
    test('a buy in euros: the shares it gets, fees on top', () {
      // 900 € at 200 $ × 0,9: 5 shares; 1,35 € FX fee + 1 € fixed.
      final e = estimateOrder(
        order(Side.buy, AmountSize(eur('900'))),
        referencePrice: usd('200'),
        fxRate: d('0.9'),
        rules: rules,
      )!;
      expect(
        (e.quantity, e.notional, e.fees, e.total),
        (Quantity.whole(5), eur('900'), eur('2.35'), eur('902.35')),
      );
    });

    test('a sell in shares: fees out of the proceeds', () {
      final e = estimateOrder(
        order(Side.sell, QuantitySize(Quantity.whole(2))),
        referencePrice: usd('200'),
        fxRate: d('0.9'),
        rules: rules,
      )!;
      // 360 € − (0,54 € + 1 €).
      expect(
        (e.notional, e.fees, e.total),
        (eur('360'), eur('1.54'), eur('358.46')),
      );
    });

    test('a whole-share wallet floors a euro amount to whole shares', () {
      final e = estimateOrder(
        order(Side.buy, AmountSize(eur('500'))),
        referencePrice: usd('200'),
        fxRate: d('0.9'),
        rules: whole,
      )!;
      // 500 / 180 = 2,77…: 2 shares, 360 €.
      expect((e.quantity, e.notional), (Quantity.whole(2), eur('360')));
    });

    test('a limit order is priced at its limit', () {
      final e = estimateOrder(
        order(
          Side.buy,
          QuantitySize(Quantity.whole(1)),
          type: OrderType.limit,
          limit: usd('150'),
        ),
        referencePrice: usd('200'),
        fxRate: d('0.9'),
        rules: rules,
      )!;
      expect(e.notional, eur('135'));
    });

    test('nothing to estimate: no price, no size, below one share', () {
      expect(
        estimateOrder(
          order(Side.buy, AmountSize(eur('100'))),
          referencePrice: null,
          fxRate: Decimal.one,
          rules: rules,
        ),
        isNull,
      );
      expect(
        estimateOrder(
          order(Side.buy, AmountSize(eur('0'))),
          referencePrice: usd('200'),
          fxRate: d('0.9'),
          rules: rules,
        ),
        isNull,
      );
      expect(
        estimateOrder(
          order(Side.buy, AmountSize(eur('100'))),
          referencePrice: usd('200'),
          fxRate: d('0.9'),
          rules: whole,
        ),
        isNull,
      );
    });
  });

  group('max', () {
    test('all the cash, fees included', () {
      // n + 0,15 % × n + 1 € = 1 002,50 €: n = 1 000 €.
      expect(
        maxBuyAmount(eur('1002.50'), assetCurrency: Currency.usd, rules: rules),
        eur('1000'),
      );
      // No FX fee in euros.
      expect(
        maxBuyAmount(eur('101'), assetCurrency: Currency.eur, rules: rules),
        eur('100'),
      );
    });

    test('rounded down to the cent, never below zero', () {
      expect(
        maxBuyAmount(eur('100'), assetCurrency: Currency.usd, rules: rules),
        eur('98.85'),
      );
      expect(
        maxBuyAmount(eur('0.50'), assetCurrency: Currency.usd, rules: rules),
        eur('0'),
      );
    });
  });

  test('half a position: down to whole shares when the wallet wants them', () {
    expect(
      halfOf(Quantity.whole(5), fractional: true),
      Quantity.truncate(d('2.5')),
    );
    expect(halfOf(Quantity.whole(5), fractional: false), Quantity.whole(2));
    expect(halfOf(Quantity.whole(1), fractional: false), Quantity.zero());
  });

  group('weight', () {
    test('a buy: the asset weighs more, the fees leave the wallet', () {
      // 400 € of Apple in 10 000 €, buying 500 € with 2 € of fees.
      final w = weightChange(
        positionValue: d('400'),
        walletTotal: d('10000'),
        side: Side.buy,
        notional: eur('500'),
        fees: eur('2'),
      )!;
      expect(w.before, d('0.04'));
      expect(w.after.round(scale: 4), d('0.0900'));
    });

    test('a sell: it weighs less', () {
      final w = weightChange(
        positionValue: d('400'),
        walletTotal: d('10000'),
        side: Side.sell,
        notional: eur('400'),
        fees: eur('1'),
      )!;
      expect(w.after, Decimal.zero);
    });

    test('an empty wallet has no weight', () {
      expect(
        weightChange(
          positionValue: Decimal.zero,
          walletTotal: Decimal.zero,
          side: Side.buy,
          notional: eur('1'),
          fees: eur('0'),
        ),
        isNull,
      );
    });
  });
}
