import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/analytics/drawdown.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/analytics/risk.dart';
import 'package:finance_companion/domain/analytics/volatility.dart';
import 'package:finance_companion/domain/wallet/valuation.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int n) => DateTime.utc(2026, 1, 1).add(Duration(days: n));
List<Decimal> ds(List<num> xs) => [for (final x in xs) d('$x')];

DailyValue v(int n, int value, [int flow = 0]) => DailyValue(
  date: day(n),
  value: Money(value, Currency.eur),
  flow: Money(flow, Currency.eur),
);

Matcher closeTo9(double expected) => isA<Decimal>().having(
  (x) => (x.toDouble() - expected).abs(),
  'error',
  lessThan(1e-9),
);

void main() {
  group('simpleReturn', () {
    test('(end − start) / start', () {
      expect(simpleReturn(d('100'), d('120')), d('0.2'));
      expect(simpleReturn(d('125'), d('90')), d('-0.28'));
      expect(simpleReturn(d('3'), d('4')), d('0.333333333333'));
    });

    test('undefined from zero', () {
      expect(simpleReturn(Decimal.zero, d('10')), isNull);
    });
  });

  group('timeWeightedReturn', () {
    test('empty or single day: 0', () {
      expect(timeWeightedReturn(const []), Decimal.zero);
      expect(timeWeightedReturn([v(0, 10000, 10000)]), Decimal.zero);
    });

    test('without flows it is the simple return', () {
      expect(
        timeWeightedReturn([v(0, 10000, 10000), v(1, 10500), v(2, 11000)]),
        closeTo9(0.1),
      );
    });

    test('contributions are not performance', () {
      // 100 € grows to 110 €, then 100 € arrive and the day ends at 215 €:
      // r = 10 %, then (215 − 100) / 110 − 1.
      expect(
        timeWeightedReturn([
          v(0, 10000, 10000),
          v(1, 11000),
          v(2, 21500, 10000),
        ]),
        closeTo9(0.15),
      );
      // A contribution alone leaves the return at 0.
      expect(
        timeWeightedReturn([v(0, 10000, 10000), v(1, 30000, 20000)]),
        Decimal.zero,
      );
    });

    test('days after a zero value are skipped', () {
      // The wallet is empty on day 1; day 2 starts again from a deposit.
      expect(
        timeWeightedReturn([
          v(0, 10000, 10000),
          v(1, 0, -11000),
          v(2, 5000, 5000),
          v(3, 5500),
        ]),
        closeTo9(1.1 * 1.1 - 1),
      );
    });

    test('a loss', () {
      expect(timeWeightedReturn([v(0, 10000, 10000), v(1, 8500)]), d('-0.15'));
    });

    test('days must be in date order', () {
      expect(
        () => timeWeightedReturn([v(1, 100), v(0, 100)]),
        throwsArgumentError,
      );
    });
  });

  group('annualisedVolatility', () {
    test('null under 20 returns (21 closes)', () {
      expect(annualisedVolatility(const []), isNull);
      expect(annualisedVolatility(ds([100])), isNull);
      expect(
        annualisedVolatility(ds([for (var i = 0; i < 20; i++) 100 + i])),
        isNull,
      );
    });

    test('sample std of daily log returns × √252', () {
      expect(
        annualisedVolatility(
          ds([for (var i = 0; i < 21; i++) i.isEven ? 100 : 101]),
        ),
        closeTo9(0.16206005771107865),
      );
      expect(
        annualisedVolatility(
          ds([
            100,
            102,
            99,
            103,
            101,
            104,
            100,
            98,
            101,
            105,
            107,
            103,
            102,
            106,
            108,
            104,
            103,
            107,
            110,
            108,
            111,
          ]),
        ),
        closeTo9(0.4673264159591759),
      );
    });

    test('a flat price has zero volatility', () {
      expect(annualisedVolatility(ds(List.filled(30, 50))), Decimal.zero);
    });

    test('a non-positive close is invalid data', () {
      expect(
        () => annualisedVolatility(ds([...List.filled(25, 10), 0])),
        throwsArgumentError,
      );
    });
  });

  group('riskBand', () {
    final cases = <(String?, int?)>[
      (null, null),
      ('0', 1),
      ('0.0799', 1),
      ('0.08', 2),
      ('0.1499', 2),
      ('0.15', 3),
      ('0.25', 4),
      ('0.3999', 4),
      ('0.40', 5),
      ('1.2', 5),
    ];
    for (final (vol, band) in cases) {
      test('$vol → $band', () {
        expect(riskBand(vol == null ? null : d(vol)), band);
      });
    }

    test('thresholds are configurable', () {
      expect(riskBand(d('0.1'), thresholds: ds([0.05, 0.2, 0.3, 0.5])), 2);
    });
  });

  group('maxDrawdown', () {
    test('empty or single point: 0 with no dates', () {
      for (final series in [
        <(DateTime, Decimal)>[],
        [(day(0), d('100'))],
      ]) {
        final dd = maxDrawdown(series);
        expect(dd.depth, Decimal.zero);
        expect(dd.peakDate, isNull);
        expect(dd.troughDate, isNull);
      }
    });

    test('the brief example: 100 → 110 → 125 → 115 → 90 → 105 is −28 %', () {
      final values = ds([100, 110, 125, 115, 90, 105]);
      final dd = maxDrawdown([
        for (var i = 0; i < values.length; i++) (day(i), values[i]),
      ]);
      expect(dd.depth, d('-0.28'));
      expect(dd.peakDate, day(2));
      expect(dd.troughDate, day(4));
    });

    test('monotonic rise: no drawdown', () {
      final dd = maxDrawdown([
        for (var i = 0; i < 5; i++) (day(i), d('${100 + i}')),
      ]);
      expect(dd.depth, Decimal.zero);
      expect(dd.peakDate, isNull);
    });

    test('monotonic fall: first point to last', () {
      final dd = maxDrawdown([
        (day(0), d('100')),
        (day(1), d('80')),
        (day(2), d('50')),
      ]);
      expect(dd.depth, d('-0.5'));
      expect(dd.peakDate, day(0));
      expect(dd.troughDate, day(2));
    });

    test('the deepest fall wins, not the latest', () {
      final dd = maxDrawdown([
        (day(0), d('100')),
        (day(1), d('60')),
        (day(2), d('200')),
        (day(3), d('150')),
      ]);
      expect(dd.depth, d('-0.4'));
      expect(dd.troughDate, day(1));
    });

    test('zero values before the first positive peak are ignored', () {
      // An empty wallet for two days, then funded.
      final dd = maxDrawdown([
        (day(0), Decimal.zero),
        (day(1), Decimal.zero),
        (day(2), d('100')),
        (day(3), d('90')),
      ]);
      expect(dd.depth, d('-0.1'));
      expect(dd.peakDate, day(2));
    });
  });

  group('concentration and effective positions', () {
    final lines = <AllocationLine>[
      PositionLine('a', d('0.4')),
      PositionLine('b', d('0.1')),
      CashLine(d('0.3')),
      LivretLine(d('0.2')),
    ];

    test('concentration is the largest position weight', () {
      expect(concentration(lines), d('0.4'));
    });

    test('effective positions use weights among positions only', () {
      // 0.8 / 0.2 among positions: 1 / (0.64 + 0.04).
      expect(effectivePositions(lines), closeTo9(1 / 0.68));
      expect(
        effectivePositions([
          PositionLine('a', d('0.25')),
          PositionLine('b', d('0.25')),
        ]),
        d('2'),
      );
    });

    test('no positions: both undefined', () {
      final cashOnly = [CashLine(Decimal.one)];
      expect(concentration(cashOnly), isNull);
      expect(effectivePositions(cashOnly), isNull);
      expect(concentration(const []), isNull);
    });
  });
}
