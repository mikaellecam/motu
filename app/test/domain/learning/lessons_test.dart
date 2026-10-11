import 'package:decimal/decimal.dart';
import 'package:finance_companion/domain/learning/checkpoint.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/decision.dart';
import 'package:finance_companion/domain/learning/puzzle.dart';
import 'package:finance_companion/domain/learning/sort.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);
const _l = Localized('x', 'x');

List<(DateTime, Decimal)> series(List<(DateTime, String)> points) => [
  for (final (date, value) in points) (date, d(value)),
];

/// [n] daily closes from 2020-01-01 moving by [moves] in turn.
List<(DateTime, Decimal)> daily(
  int n,
  List<String> moves, {
  String start = '100',
}) {
  var price = d(start);
  return [
    for (var i = 0; i < n; i++)
      (
        DateTime.utc(2020, 1, 1 + i),
        i == 0
            ? price
            : price = (price * (Decimal.one + d(moves[i % moves.length]))),
      ),
  ];
}

void main() {
  group('decision', () {
    final world = series([
      (day(2020, 2, 14), '100'),
      (day(2020, 2, 21), '96'),
      (day(2020, 3, 20), '70'),
      (day(2021, 2, 26), '119'),
    ]);

    test('the moment splits the curve: before it, then after it', () {
      final (before, after) = splitAt(world, day(2020, 3, 20));
      expect(before.map((p) => p.$2), [d('100'), d('96'), d('70')]);
      expect(after.map((p) => p.$2), [d('70'), d('119')]);
    });

    test('a moment between two points splits at the last one before it', () {
      final (before, after) = splitAt(world, day(2020, 3, 1));
      expect(before.last.$1, day(2020, 2, 21));
      expect(after.first.$1, day(2020, 2, 21));
    });

    test('a moment outside the curve: all before, or all after', () {
      expect(splitAt(world, day(2022, 1, 1)).$2, hasLength(1));
      expect(splitAt(world, day(2019, 1, 1)).$1, isEmpty);
      final (none, nothing) = splitAt(const [], day(2020, 3, 20));
      expect((none.isEmpty, nothing.isEmpty), (true, true));
    });

    test(
      'each choice: the kept share follows the market, the rest is cash',
      () {
        final change = changeAfter(world, day(2020, 3, 20))!;
        expect(change, d('0.7'));
        expect(
          choiceOutcome(d('1000'), kept: Decimal.one, change: change),
          d('1700'),
        );
        expect(
          choiceOutcome(d('1000'), kept: d('0.5'), change: change),
          d('1350'),
        );
        expect(
          choiceOutcome(d('1000'), kept: Decimal.zero, change: change),
          d('1000'),
        );
      },
    );

    test('no change without points after the moment', () {
      expect(changeAfter(world, day(2022, 1, 1)), isNull);
      expect(changeAfter(world, day(2019, 1, 1)), isNull);
    });
  });

  group('sort', () {
    test('the true order: by value, then as written', () {
      expect(
        trueOrder(
          ['a', 'b', 'c', 'd'],
          {'a': d('0.30'), 'b': Decimal.zero, 'c': d('0.18'), 'd': d('0.18')},
        ),
        ['b', 'c', 'd', 'a'],
      );
    });

    test('well placed: same rank as the truth', () {
      expect(wellPlaced(['b', 'a', 'c'], ['a', 'b', 'c']), 1);
      expect(wellPlaced(['a', 'b', 'c'], ['a', 'b', 'c']), 3);
      expect(wellPlaced(const [], const []), 0);
    });

    test('an item takes its fixed value, or its dataset\'s volatility', () {
      expect(
        itemValue(SortItem('livret', _l, value: Decimal.zero)),
        Decimal.zero,
      );
      final calm = daily(40, ['0.001', '-0.001']);
      expect(
        itemValue(const SortItem('etf', _l, dataset: 'ds'), calm),
        isNotNull,
      );
      expect(
        itemValue(const SortItem('etf', _l, dataset: 'ds'), daily(5, ['0.01'])),
        isNull,
        reason: 'too short a history',
      );
    });
  });

  group('build_puzzle', () {
    // Two assets moving in opposite directions every day, and a third one
    // that swings hard.
    final up = daily(60, ['0.01', '-0.01']);
    final down = daily(60, ['-0.01', '0.01']);
    final wild = daily(60, ['0.05', '-0.05']);
    final prices = {'up': up, 'down': down, 'wild': wild};

    test('opposite moves cancel out in a mix', () {
      final alone = portfolioVolatility(prices, {'up': Decimal.one})!;
      final mixed = portfolioVolatility(prices, {
        'up': d('0.5'),
        'down': d('0.5'),
      })!;
      expect(alone, greaterThan(d('0.1')));
      expect(mixed, lessThan(d('0.01')));
    });

    test('only the days every weighted asset has count', () {
      final short = {'up': up, 'down': down.sublist(0, 30)};
      final vol = portfolioVolatility(short, {
        'up': d('0.5'),
        'down': d('0.5'),
      });
      expect(vol, isNotNull);
      expect(
        portfolioVolatility(
          {'up': up, 'down': down.sublist(0, 10)},
          {'up': d('0.5'), 'down': d('0.5')},
        ),
        isNull,
        reason: 'fewer than 20 common returns',
      );
    });

    test('what is not given a weight sits in cash', () {
      final full = portfolioVolatility(prices, {'wild': Decimal.one})!;
      final half = portfolioVolatility(prices, {'wild': d('0.5')})!;
      // Half the money moving: about half the volatility, and no crash on
      // a long history.
      expect(half, greaterThan(full * d('0.45')));
      expect(half, lessThan(full * d('0.55')));
    });

    test('weights over 100 % count as shares of the whole', () {
      expect(
        portfolioVolatility(prices, {'up': d('0.8'), 'down': d('0.8')}),
        portfolioVolatility(prices, {'up': d('0.5'), 'down': d('0.5')}),
      );
    });

    test('no weight: no portfolio', () {
      expect(portfolioVolatility(prices, const {}), isNull);
      expect(portfolioVolatility(prices, {'up': Decimal.zero}), isNull);
    });

    const assets = [
      PuzzleAsset('up', _l, 'us'),
      PuzzleAsset('down', _l, 'europe'),
      PuzzleAsset('wild', _l, 'emerging'),
    ];
    final rules = PuzzleRules(
      maxVolatility: d('0.10'),
      minAssets: 3,
      minRegions: 3,
    );

    test('every rule checked', () {
      final check = checkPuzzle(
        rules,
        assets,
        weights: {'up': d('0.5'), 'down': d('0.4'), 'wild': d('0.1')},
        volatility: d('0.08'),
      );
      expect(
        (check.total, check.volatility, check.assets, check.regions),
        (true, true, true, true),
      );
      expect(check.solved, isTrue);
    });

    test('a broken rule each', () {
      final check = checkPuzzle(
        rules,
        assets,
        weights: {'up': d('0.5'), 'down': d('0.4')},
        volatility: d('0.12'),
      );
      expect(
        (check.total, check.volatility, check.assets, check.regions),
        (false, false, false, false),
      );
      expect(check.solved, isFalse);
    });

    test('an unknown volatility is not a calm one', () {
      expect(
        checkPuzzle(
          rules,
          assets,
          weights: {'up': d('0.4'), 'down': d('0.3'), 'wild': d('0.3')},
          volatility: null,
        ).volatility,
        isFalse,
      );
    });

    test('a rule left out of the puzzle always holds', () {
      final check = checkPuzzle(
        PuzzleRules(maxVolatility: d('0.10')),
        assets,
        weights: {'up': Decimal.one},
        volatility: d('0.05'),
      );
      expect(check.solved, isTrue);
    });
  });

  group('checkpoint', () {
    const questions = [
      QuizQuestion(question: _l, choices: [], answer: 'a'),
      QuizQuestion(question: _l, choices: [], answer: 'b'),
      QuizQuestion(question: _l, choices: [], answer: 'c'),
    ];

    test('the score counts the right answers', () {
      expect(quizScore(questions, ['a', 'x', 'c']), 2);
      expect(quizScore(questions, ['a', 'b', 'c']), 3);
    });

    test('unanswered questions score nothing', () {
      expect(quizScore(questions, ['a']), 1);
      expect(quizScore(questions, const []), 0);
    });
  });
}
