import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/valuation.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int m, int dd) => DateTime.utc(2026, m, dd);

PriceBar bar(DateTime date, String close, [Currency c = Currency.eur]) =>
    PriceBar(
      date: date,
      open: d(close),
      high: d(close),
      low: d(close),
      close: d(close),
      volume: 0,
      currency: c,
    );

Position position(String asset, String qty, String cost) => Position(
  assetId: asset,
  quantity: Quantity.truncate(d(qty)),
  costBasis: d(cost),
  realisedPnl: Decimal.zero,
);

PriceAsOf fresh(String price, [Currency c = Currency.eur]) =>
    PriceAsOf(Price(d(price), c), day(10, 9), stale: false);

void main() {
  group('closeAsOf', () {
    final bars = [
      bar(day(10, 7), '10'),
      bar(day(10, 8), '11'),
      bar(day(10, 9), '12'),
    ];

    test('the bar of the expected day, not stale', () {
      final p = closeAsOf(bars, asOf: day(10, 9), expectedDate: day(10, 9))!;
      expect(p.price, Price(d('12'), Currency.eur));
      expect(p.date, day(10, 9));
      expect(p.stale, isFalse);
    });

    test(
      'a missing bar falls back to the latest earlier one, flagged stale',
      () {
        final gap = [bars[0], bars[1]];
        final p = closeAsOf(gap, asOf: day(10, 9), expectedDate: day(10, 9))!;
        expect(p.price.value, d('11'));
        expect(p.date, day(10, 8));
        expect(p.stale, isTrue);
      },
    );

    test('a weekend asOf uses Friday without being stale', () {
      // Saturday 10 Oct: the caller expects Friday 9 Oct's close.
      final p = closeAsOf(bars, asOf: day(10, 10), expectedDate: day(10, 9))!;
      expect(p.date, day(10, 9));
      expect(p.stale, isFalse);
    });

    test('never looks ahead of asOf', () {
      final p = closeAsOf(bars, asOf: day(10, 8), expectedDate: day(10, 8))!;
      expect(p.price.value, d('11'));
    });

    test('no bar on or before asOf: null', () {
      expect(
        closeAsOf(bars, asOf: day(10, 6), expectedDate: day(10, 6)),
        isNull,
      );
      expect(
        closeAsOf(const [], asOf: day(10, 9), expectedDate: day(10, 9)),
        isNull,
      );
    });

    test('a single bar', () {
      final p = closeAsOf(
        [bars[0]],
        asOf: day(10, 7),
        expectedDate: day(10, 7),
      )!;
      expect(p.price.value, d('10'));
      expect(p.stale, isFalse);
    });

    test('bars may arrive unsorted', () {
      final p = closeAsOf(
        bars.reversed.toList(),
        asOf: day(10, 8),
        expectedDate: day(10, 8),
      )!;
      expect(p.price.value, d('11'));
    });
  });

  group('Holding', () {
    test('market value converts to EUR at the given rate', () {
      final h = Holding(
        position: position('aapl', '2', '180'),
        price: fresh('100', Currency.usd),
        fxRate: d('0.9'),
      );
      expect(h.marketValue, d('180'));
      expect(h.unrealisedPnl, Decimal.zero);
    });

    test('unrealised P&L in amount and ratio', () {
      final h = Holding(
        position: position('cw8', '4', '400'),
        price: fresh('110'),
        fxRate: Decimal.one,
      );
      expect(h.marketValue, d('440'));
      expect(h.unrealisedPnl, d('40'));
      expect(h.unrealisedPnlRatio, d('0.1'));
    });

    test('the ratio is undefined when nothing was paid', () {
      final h = Holding(
        position: position('gift', '1', '0'),
        price: fresh('10'),
        fxRate: Decimal.one,
      );
      expect(h.unrealisedPnl, d('10'));
      expect(h.unrealisedPnlRatio, isNull);
    });

    test('carries the stale flag of its price', () {
      final h = Holding(
        position: position('cw8', '1', '10'),
        price: PriceAsOf(Price(d('10'), Currency.eur), day(10, 8), stale: true),
        fxRate: Decimal.one,
      );
      expect(h.stale, isTrue);
    });

    test('a EUR price converts at exactly 1', () {
      expect(
        () => Holding(
          position: position('cw8', '1', '10'),
          price: fresh('10'),
          fxRate: d('0.9'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('valueWallet', () {
    const cash = Money(10000, Currency.eur);

    test('cash only', () {
      final v = valueWallet(
        cash: cash,
        positions: const {},
        prices: const {},
        fxRates: const {},
      );
      expect(v.total, d('100'));
      expect(v.holdings, isEmpty);
      expect(v.allocation.single, isA<CashLine>());
      expect(v.allocation.single.weight, Decimal.one);
      expect(v.hasStalePrice, isFalse);
    });

    test('total = cash + market values + Livret', () {
      final v = valueWallet(
        cash: cash,
        positions: {
          'cw8': position('cw8', '2', '180'),
          'aapl': position('aapl', '1', '90'),
        },
        prices: {'cw8': fresh('100'), 'aapl': fresh('120', Currency.usd)},
        fxRates: {Currency.usd: d('0.9')},
        livret: d('50.25'),
      );
      // 100 cash + 200 CW8 + 108 AAPL + 50.25 Livret.
      expect(v.total, d('458.25'));
      expect(v.holdings.map((h) => h.marketValue), [d('200'), d('108')]);
    });

    test('closed positions are not holdings', () {
      final v = valueWallet(
        cash: cash,
        positions: {'cw8': position('cw8', '0', '0')},
        prices: const {},
        fxRates: const {},
      );
      expect(v.holdings, isEmpty);
    });

    test('allocation lines sum to 1 within 1e-9, cash and Livret included', () {
      final v = valueWallet(
        cash: const Money(10000, Currency.eur),
        positions: {
          'a': position('a', '1', '100'),
          'b': position('b', '1', '100'),
        },
        prices: {'a': fresh('100'), 'b': fresh('100')},
        fxRates: const {},
        livret: d('100'),
      );
      final weights = v.allocation.map((l) => l.weight).toList();
      final sum = weights.fold(Decimal.zero, (a, b) => a + b);
      expect((sum - Decimal.one).abs() <= d('1e-9'), isTrue);
      expect(v.allocation.whereType<PositionLine>().map((l) => l.assetId), [
        'a',
        'b',
      ]);
      expect(v.allocation.whereType<CashLine>(), hasLength(1));
      expect(v.allocation.whereType<LivretLine>(), hasLength(1));
      expect(weights.first, d('0.25'));
    });

    test(
      'non-terminating weights still sum to 1 within 1e-9 over 40 lines',
      () {
        final positions = {
          for (var i = 0; i < 39; i++) 'a$i': position('a$i', '1', '1'),
        };
        final v = valueWallet(
          cash: const Money(700, Currency.eur),
          positions: positions,
          prices: {for (final id in positions.keys) id: fresh('3.33')},
          fxRates: const {},
        );
        final sum = v.allocation.fold(Decimal.zero, (a, l) => a + l.weight);
        expect(v.allocation, hasLength(40));
        expect((sum - Decimal.one).abs() <= d('1e-9'), isTrue);
      },
    );

    test('an empty wallet has no allocation (no division by zero)', () {
      final v = valueWallet(
        cash: const Money.zero(Currency.eur),
        positions: const {},
        prices: const {},
        fxRates: const {},
      );
      expect(v.total, Decimal.zero);
      expect(v.allocation, isEmpty);
    });

    test('a zero Livret is not a line', () {
      final v = valueWallet(
        cash: cash,
        positions: const {},
        prices: const {},
        fxRates: const {},
        livret: Decimal.zero,
      );
      expect(v.allocation.whereType<LivretLine>(), isEmpty);
    });

    test('one stale price flags the valuation', () {
      final v = valueWallet(
        cash: cash,
        positions: {'cw8': position('cw8', '1', '10')},
        prices: {
          'cw8': PriceAsOf(
            Price(d('10'), Currency.eur),
            day(10, 8),
            stale: true,
          ),
        },
        fxRates: const {},
      );
      expect(v.hasStalePrice, isTrue);
    });

    test(
      'an open position without a price, or a missing rate, is an error',
      () {
        expect(
          () => valueWallet(
            cash: cash,
            positions: {'cw8': position('cw8', '1', '10')},
            prices: const {},
            fxRates: const {},
          ),
          throwsArgumentError,
        );
        expect(
          () => valueWallet(
            cash: cash,
            positions: {'aapl': position('aapl', '1', '10')},
            prices: {'aapl': fresh('10', Currency.usd)},
            fxRates: const {},
          ),
          throwsArgumentError,
        );
      },
    );

    test('cash must be in EUR', () {
      expect(
        () => valueWallet(
          cash: const Money(100, Currency.usd),
          positions: const {},
          prices: const {},
          fxRates: const {},
        ),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });
  });

  group('ratio', () {
    test('exact when the quotient terminates', () {
      expect(ratio(d('1'), d('4')), d('0.25'));
    });

    test('12 decimals otherwise', () {
      expect(ratio(d('1'), d('3')), d('0.333333333333'));
    });
  });
}
