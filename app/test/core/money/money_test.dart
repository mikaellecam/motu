import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(int cents) => Money(cents, Currency.eur);
Money usd(int cents) => Money(cents, Currency.usd);

final throwsMismatch = throwsA(
  isA<CurrencyMismatchError>()
      .having((e) => e.left, 'left', Currency.eur)
      .having((e) => e.right, 'right', Currency.usd)
      .having((e) => e.toString(), 'message', contains('EUR')),
);

void main() {
  group('Currency', () {
    test('ISO codes and minor digits', () {
      expect(Currency.eur.code, 'EUR');
      expect(Currency.usd.code, 'USD');
      expect(Currency.eur.minorDigits, 2);
      expect(Currency.usd.minorDigits, 2);
    });
  });

  group('Money', () {
    test('adds and subtracts in minor units', () {
      expect(eur(1050) + eur(250), eur(1300));
      expect(eur(1050) - eur(2000), eur(-950));
      expect(-eur(300), eur(-300));
      expect(eur(0) + eur(0), const Money.zero(Currency.eur));
    });

    test('0.10 + 0.20 is exactly 0.30', () {
      expect(eur(10) + eur(20), eur(30));
    });

    test('exposes its amount as an exact Decimal', () {
      expect(eur(5153460).amount, d('51534.60'));
      expect(eur(-5).amount, d('-0.05'));
      expect(eur(0).amount, Decimal.zero);
    });

    test('sign helpers', () {
      expect(eur(0).isZero, isTrue);
      expect(eur(1).isZero, isFalse);
      expect(eur(1).isPositive, isTrue);
      expect(eur(0).isPositive, isFalse);
      expect(eur(-1).isNegative, isTrue);
      expect(eur(0).isNegative, isFalse);
    });

    test('compares within a currency', () {
      expect(eur(100) < eur(101), isTrue);
      expect(eur(100) <= eur(100), isTrue);
      expect(eur(101) > eur(100), isTrue);
      expect(eur(100) >= eur(101), isFalse);
      expect(eur(100).compareTo(eur(100)), 0);
      expect([eur(3), eur(-1), eur(2)]..sort(), [eur(-1), eur(2), eur(3)]);
    });

    test('equality includes the currency', () {
      expect(eur(100), isNot(usd(100)));
      expect(eur(100).hashCode, eur(100).hashCode);
      expect(eur(100), isNot(100));
    });

    test('mixing currencies throws a typed error', () {
      expect(() => eur(1) + usd(1), throwsMismatch);
      expect(() => eur(1) - usd(1), throwsMismatch);
      expect(() => eur(1) < usd(1), throwsMismatch);
      expect(() => eur(1) <= usd(1), throwsMismatch);
      expect(() => eur(1) > usd(1), throwsMismatch);
      expect(() => eur(1) >= usd(1), throwsMismatch);
      expect(() => eur(1).compareTo(usd(1)), throwsMismatch);
    });

    group('book rounds half-even to the cent, once', () {
      final cases = <(String, int)>[
        ('12.34', 1234),
        ('0.005', 0),
        ('0.015', 2),
        ('0.025', 2),
        ('0.0251', 3),
        ('-0.005', 0),
        ('-0.015', -2),
        ('1234.5649999', 123456),
        ('0', 0),
      ];
      for (final (amount, cents) in cases) {
        test('$amount → $cents', () {
          expect(Money.book(d(amount), Currency.eur), eur(cents));
        });
      }
    });

    test('toString is a debug form', () {
      expect(eur(-1234).toString(), 'EUR -12.34');
    });
  });

  group('Quantity', () {
    test('whole units and millionths', () {
      expect(Quantity.whole(3).micros, 3000000);
      expect(const Quantity.micros(1).toDecimal(), d('0.000001'));
      expect(Quantity.whole(0), const Quantity.zero());
    });

    test('truncate keeps 6 decimals, toward zero', () {
      expect(Quantity.truncate(d('1.2345678')).micros, 1234567);
      expect(Quantity.truncate(d('0.0000009')), const Quantity.zero());
      expect(Quantity.truncate(d('2')).micros, 2000000);
      expect(Quantity.truncate(d('-1.2345678')).micros, -1234567);
    });

    test('arithmetic and comparison', () {
      final a = Quantity.truncate(d('1.5'));
      final b = Quantity.truncate(d('0.25'));
      expect((a + b).toDecimal(), d('1.75'));
      expect((a - b).toDecimal(), d('1.25'));
      expect(a > b, isTrue);
      expect(a >= a, isTrue);
      expect(b < a, isTrue);
      expect(b <= a, isTrue);
      expect(a.compareTo(b), greaterThan(0));
      expect(a, Quantity.truncate(d('1.500000')));
      expect(a.hashCode, Quantity.truncate(d('1.5')).hashCode);
      expect(a, isNot(1.5));
    });

    test('whole-share and sign helpers', () {
      expect(Quantity.whole(2).isWhole, isTrue);
      expect(Quantity.truncate(d('2.5')).isWhole, isFalse);
      expect(const Quantity.zero().isZero, isTrue);
      expect(const Quantity.micros(1).isZero, isFalse);
      expect(const Quantity.micros(1).isPositive, isTrue);
      expect(const Quantity.zero().isPositive, isFalse);
    });

    test('toString is a debug form', () {
      expect(Quantity.truncate(d('0.5')).toString(), 'Quantity(0.5)');
    });
  });

  group('Price', () {
    final p = Price(d('177.57'), Currency.usd);

    test('equality includes the currency', () {
      expect(p, Price(d('177.570'), Currency.usd));
      expect(p, isNot(Price(d('177.57'), Currency.eur)));
      expect(p.hashCode, Price(d('177.57'), Currency.usd).hashCode);
      expect(p, isNot(d('177.57')));
    });

    test('compares within a currency', () {
      final lower = Price(d('150'), Currency.usd);
      expect(lower < p, isTrue);
      expect(lower <= p, isTrue);
      expect(p > lower, isTrue);
      expect(p >= p, isTrue);
      expect(p.compareTo(lower), greaterThan(0));
    });

    test('mixing currencies throws a typed error', () {
      final inEur = Price(d('1'), Currency.eur);
      final inUsd = Price(d('1'), Currency.usd);
      expect(() => inEur < inUsd, throwsMismatch);
      expect(() => inEur <= inUsd, throwsMismatch);
      expect(() => inEur > inUsd, throwsMismatch);
      expect(() => inEur >= inUsd, throwsMismatch);
      expect(() => inEur.compareTo(inUsd), throwsMismatch);
    });

    test('notional of a quantity, unrounded, in the price currency', () {
      expect(p.times(Quantity.truncate(d('0.5'))), d('88.785'));
      expect(p.times(const Quantity.zero()), Decimal.zero);
    });

    test('toString is a debug form', () {
      expect(p.toString(), 'USD 177.57');
    });
  });

  group('roundHalfEven', () {
    final cases = <(String, int, String)>[
      ('2.345', 2, '2.34'),
      ('2.355', 2, '2.36'),
      ('-2.345', 2, '-2.34'),
      ('-2.355', 2, '-2.36'),
      ('2.3451', 2, '2.35'),
      ('2.3449', 2, '2.34'),
      ('0.5', 0, '0'),
      ('1.5', 0, '2'),
      ('2.5', 0, '2'),
      ('-0.5', 0, '0'),
      ('-1.5', 0, '-2'),
      ('7', 2, '7'),
    ];
    for (final (value, scale, expected) in cases) {
      test('$value at $scale → $expected', () {
        expect(roundHalfEven(d(value), scale), d(expected));
      });
    }
  });
}
