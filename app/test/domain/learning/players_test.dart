import 'package:decimal/decimal.dart';
import 'package:finance_companion/domain/learning/reveal.dart';
import 'package:finance_companion/domain/learning/toys.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);

List<(DateTime, Decimal)> series(List<(DateTime, String)> points) => [
  for (final (date, value) in points) (date, d(value)),
];

void main() {
  group('investedCurve', () {
    test('what the amount became, point by point', () {
      final curve = investedCurve(
        series([
          (day(2022, 1, 7), '172.17'),
          (day(2022, 1, 14), '154.96'),
          (day(2022, 12, 30), '129.93'),
        ]),
        d('1000'),
      );
      expect(
        [for (final (_, v) in curve) v.round(scale: 2)],
        [d('1000'), d('900.04'), d('754.66')],
      );
      expect(curve.first.$1, day(2022, 1, 7));
    });

    test('a single point is the amount', () {
      expect(investedCurve(series([(day(2022, 1, 7), '5')]), d('100')), [
        (day(2022, 1, 7), d('100')),
      ]);
    });

    test('no point: no curve', () {
      expect(investedCurve(const [], d('100')), isEmpty);
    });

    test('a first price of zero cannot be invested in', () {
      expect(
        () => investedCurve(series([(day(2022, 1, 7), '0')]), d('100')),
        throwsArgumentError,
      );
    });
  });

  group('curveChange', () {
    test('last over first', () {
      expect(
        curveChange(
          series([(day(2022, 1, 7), '1000'), (day(2022, 2, 7), '1250')]),
        ),
        d('0.25'),
      );
    });

    test('fewer than two points: none', () {
      expect(curveChange(const []), isNull);
      expect(curveChange(series([(day(2022, 1, 7), '1000')])), isNull);
    });
  });

  group('liveStart', () {
    test('years and months back from the latest day', () {
      expect(liveStart(day(2026, 10, 9), '1y'), day(2025, 10, 9));
      expect(liveStart(day(2026, 10, 9), '6m'), day(2026, 4, 9));
      expect(liveStart(day(2026, 10, 9), '3y'), day(2023, 10, 9));
    });

    test('a month end stays in its month', () {
      expect(liveStart(day(2026, 3, 31), '1m'), day(2026, 2, 28));
      expect(liveStart(day(2024, 2, 29), '1y'), day(2023, 2, 28));
    });

    test('an unreadable period: none', () {
      for (final period in ['', '1w', 'y', '0y', 'one year']) {
        expect(liveStart(day(2026, 10, 9), period), isNull, reason: period);
      }
    });
  });

  group('averageYearlyReturn', () {
    test('the yearly rate that joins the first and last points', () {
      // × 2 in 10 years: 7,18 % a year.
      final rate = averageYearlyReturn(
        series([
          (day(2010, 1, 1), '50'),
          (day(2015, 6, 1), '70'),
          (day(2020, 1, 1), '100'),
        ]),
      )!;
      expect(rate.round(scale: 4), d('0.0718'));
    });

    test('a fall gives a negative rate', () {
      final rate = averageYearlyReturn(
        series([(day(2020, 1, 1), '100'), (day(2022, 1, 1), '81')]),
      )!;
      expect(rate.round(scale: 3), d('-0.1'));
    });

    test('fewer than two points, one day, or a zero price: none', () {
      expect(averageYearlyReturn(const []), isNull);
      expect(averageYearlyReturn(series([(day(2020, 1, 1), '100')])), isNull);
      expect(
        averageYearlyReturn(
          series([(day(2020, 1, 1), '100'), (day(2020, 1, 1), '110')]),
        ),
        isNull,
      );
      expect(
        averageYearlyReturn(
          series([(day(2020, 1, 1), '0'), (day(2021, 1, 1), '110')]),
        ),
        isNull,
      );
    });
  });

  group('feesToy', () {
    test('two fee levels on the same money and return', () {
      final result = feesToy(
        amount: d('10000'),
        years: 2,
        yearlyReturn: d('0.05'),
        lowFee: d('0.002'),
        highFee: d('0.015'),
      );
      // 10 000 × (1,05 × 0,998)² and × (1,05 × 0,985)².
      expect(
        [for (final v in result.low) v.round(scale: 2)],
        [d('10000'), d('10479'), d('10980.94')],
      );
      expect(result.high.last.round(scale: 2), d('10696.73'));
      expect(result.gap.round(scale: 2), d('284.21'));
    });

    test('zero years: the amount, no gap', () {
      final result = feesToy(
        amount: d('10000'),
        years: 0,
        yearlyReturn: d('0.05'),
        lowFee: d('0.002'),
        highFee: d('0.015'),
      );
      expect(result.low, [d('10000')]);
      expect(result.gap, Decimal.zero);
    });

    test('a negative return and no fee', () {
      final result = feesToy(
        amount: d('100'),
        years: 1,
        yearlyReturn: d('-0.1'),
        lowFee: Decimal.zero,
        highFee: d('0.01'),
      );
      expect(
        (result.low.last, result.high.last.round(scale: 2)),
        (d('90'), d('89.1')),
      );
    });

    test('negative inputs are refused', () {
      expect(
        () => feesToy(
          amount: d('-1'),
          years: 1,
          yearlyReturn: d('0.05'),
          lowFee: Decimal.zero,
          highFee: Decimal.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => feesToy(
          amount: d('1'),
          years: -1,
          yearlyReturn: d('0.05'),
          lowFee: Decimal.zero,
          highFee: Decimal.zero,
        ),
        throwsArgumentError,
      );
    });
  });

  group('compoundToy', () {
    test('a start, a monthly amount, and growth on what is there', () {
      final result = compoundToy(
        amount: d('1000'),
        monthly: d('100'),
        years: 2,
        yearlyReturn: d('0.05'),
      );
      expect(result.moneyIn, [d('1000'), d('2200'), d('3400')]);
      // 1 000 × 1,05 + 1 200 = 2 250; 2 250 × 1,05 + 1 200 = 3 562,50.
      expect(result.value, [d('1000'), d('2250'), d('3562.5')]);
      expect(result.growth, d('162.5'));
    });

    test('nothing in: nothing grows', () {
      final result = compoundToy(
        amount: Decimal.zero,
        monthly: Decimal.zero,
        years: 3,
        yearlyReturn: d('0.07'),
      );
      expect(result.value.last, Decimal.zero);
      expect(result.growth, Decimal.zero);
    });

    test('negative inputs are refused', () {
      expect(
        () => compoundToy(
          amount: d('1'),
          monthly: d('-1'),
          years: 1,
          yearlyReturn: d('0.05'),
        ),
        throwsArgumentError,
      );
    });
  });

  test('a toy completes once every control was moved', () {
    const controls = ['amount', 'years', 'return'];
    expect(everyControlTouched(controls, {'amount', 'years'}), isFalse);
    expect(
      everyControlTouched(controls, {'amount', 'years', 'return'}),
      isTrue,
    );
    expect(everyControlTouched(const [], const {}), isTrue);
  });
}
