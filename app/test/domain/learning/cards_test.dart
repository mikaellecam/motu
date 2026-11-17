import 'package:decimal/decimal.dart';
import 'package:finance_companion/domain/learning/cards.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/toys.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
const label = Localized('l', 'l');

Dataset dataset(List<String> values) => Dataset(
  id: 'ds.x',
  source: 'test',
  adjusted: false,
  currency: 'EUR',
  interval: '1month',
  frozenAt: DateTime.utc(2026),
  points: [
    for (final (i, v) in values.indexed) (DateTime.utc(2020, i + 1), d(v)),
  ],
);

void main() {
  group('formulaSeries', () {
    test('every formula draws its series, the main one first', () {
      final inputs = {
        ToyFormula.fees: {
          'amount': d('1000'),
          'years': d('2'),
          'return': d('0.1'),
          'fee_low': d('0'),
          'fee_high': d('0.01'),
        },
        ToyFormula.compound: {
          'amount': d('0'),
          'monthly': d('10'),
          'years': d('1'),
          'return': d('0'),
        },
        ToyFormula.cushion: {
          'spending': d('1000'),
          'months': d('3'),
          'saving': d('1000'),
        },
        ToyFormula.loan: {
          'amount': d('1200'),
          'months': d('12'),
          'rate': d('0'),
        },
      };
      for (final formula in ToyFormula.values) {
        final series = formulaSeries(formula, inputs[formula]!);
        expect(series.keys, formula.series, reason: formula.json);
      }
      expect(formulaSeries(ToyFormula.fees, inputs[ToyFormula.fees]!)['low'], [
        d('1000'),
        d('1100'),
        d('1210'),
      ]);
      expect(
        formulaSeries(ToyFormula.cushion, inputs[ToyFormula.cushion]!)['saved'],
        [d('0'), d('1000'), d('2000'), d('3000')],
      );
      expect(formulaSeries(ToyFormula.compound, inputs[ToyFormula.compound]!), {
        'value': [d('0'), d('120')],
        'money_in': [d('0'), d('120')],
      });
    });

    test('a missing input or a negative one is an error', () {
      expect(
        () => formulaSeries(ToyFormula.loan, {'amount': d('1')}),
        throwsArgumentError,
      );
      expect(
        () => formulaSeries(ToyFormula.cushion, {
          'spending': d('-1'),
          'months': d('3'),
          'saving': d('1'),
        }),
        throwsArgumentError,
      );
    });
  });

  group('cardLineValues', () {
    final datasets = {
      'ds.x': dataset(['50', '75', '25']),
      'ds.empty': dataset([]),
      'ds.zero': dataset(['0', '10']),
    };

    test('a dataset as is, or as what an amount became', () {
      expect(cardLineValues(const CardLine(label, dataset: 'ds.x'), datasets), [
        d('50'),
        d('75'),
        d('25'),
      ]);
      expect(
        cardLineValues(
          CardLine(label, dataset: 'ds.x', amount: d('1000')),
          datasets,
        ),
        [d('1000'), d('1500'), d('500')],
      );
    });

    test('a single point, an empty or unknown dataset, a zero start', () {
      expect(
        cardLineValues(CardLine(label, dataset: 'ds.one', amount: d('1')), {
          'ds.one': dataset(['7']),
        }),
        [d('1')],
      );
      expect(
        cardLineValues(const CardLine(label, dataset: 'ds.empty'), datasets),
        isEmpty,
      );
      expect(
        cardLineValues(const CardLine(label, dataset: 'ds.none'), datasets),
        isEmpty,
      );
      // No division by zero: the values as they are.
      expect(
        cardLineValues(
          CardLine(label, dataset: 'ds.zero', amount: d('100')),
          datasets,
        ),
        [d('0'), d('10')],
      );
    });

    test('a formula: its main series, or the one named', () {
      final inputs = {
        'amount': d('100'),
        'monthly': d('0'),
        'years': d('1'),
        'return': d('0.5'),
      };
      expect(
        cardLineValues(
          CardLine(label, formula: ToyFormula.compound, inputs: inputs),
          const {},
        ),
        [d('100'), d('150')],
      );
      expect(
        cardLineValues(
          CardLine(
            label,
            formula: ToyFormula.compound,
            inputs: inputs,
            series: 'money_in',
          ),
          const {},
        ),
        [d('100'), d('100')],
      );
      expect(
        cardLineValues(
          CardLine(
            label,
            formula: ToyFormula.compound,
            inputs: inputs,
            series: 'nope',
          ),
          const {},
        ),
        isEmpty,
      );
    });
  });
}
