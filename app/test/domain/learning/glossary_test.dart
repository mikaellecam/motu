import 'package:decimal/decimal.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:finance_companion/domain/learning/checkpoint.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/glossary.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:finance_companion/domain/learning/reveal.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int m, int dd) => DateTime.utc(2025, m, dd);
const _l = Localized('x', 'x');

NodeContent node(String id, List<String> glossary) => NodeContent(
  id: id,
  type: NodeType.toy,
  title: _l,
  status: ContentStatus.draft,
  glossary: glossary,
);

void main() {
  group('status', () {
    test('discovered, met, or to discover', () {
      expect(
        [
          for (final id in ['a', 'b', 'c', 'd'])
            termStatus(id, discovered: {'a', 'b'}, met: {'b', 'c'}),
        ],
        [
          TermStatus.discovered,
          TermStatus.discovered,
          TermStatus.met,
          TermStatus.toDiscover,
        ],
      );
    });

    test('terms met: in completed lessons and in companion moments', () {
      expect(
        termsMet(
          completed: [
            node('ae.a', ['etf', 'indice']),
            node('ae.b', []),
          ],
          moments: [CompanionRule.firstLoss],
        ),
        {'etf', 'indice', 'volatilite', 'horizon-de-placement'},
      );
      expect(termsMet(completed: const [], moments: const []), isEmpty);
    });

    test('the filters: everything, the discovered, the rest', () {
      for (final (status, all, discovered, toDiscover) in [
        (TermStatus.discovered, true, true, false),
        (TermStatus.met, true, false, true),
        (TermStatus.toDiscover, true, false, true),
      ]) {
        expect(
          (
            GlossaryFilter.all.keeps(status),
            GlossaryFilter.discovered.keeps(status),
            GlossaryFilter.toDiscover.keeps(status),
          ),
          (all, discovered, toDiscover),
          reason: '$status',
        );
      }
    });
  });

  test('a term quiz is passed with every answer right', () {
    const quiz = [
      QuizQuestion(question: _l, choices: [RevealChoice('a', _l)], answer: 'a'),
      QuizQuestion(question: _l, choices: [RevealChoice('b', _l)], answer: 'b'),
    ];
    expect(quizPassed(quiz, ['a', 'b']), isTrue);
    expect(quizPassed(quiz, ['a', 'x']), isFalse);
    expect(quizPassed(quiz, ['a']), isFalse, reason: 'not finished');
    expect(quizPassed(const [], const []), isFalse, reason: 'no quiz');
  });

  group('live examples over a year', () {
    // Up 20 %, down to 90, back to 110.
    final closes = [
      (day(1, 2), d('100')),
      (day(3, 3), d('120')),
      (day(6, 2), d('90')),
      (day(12, 31), d('110')),
    ];

    test('performance: first to last close', () {
      expect(liveFigure(LiveExample.performance, closes), d('0.1'));
    });

    test('worst drop: from a peak to the trough after it', () {
      expect(liveFigure(LiveExample.drawdown, closes), d('-0.25'));
    });

    test('volatility: too few closes, none', () {
      expect(liveFigure(LiveExample.volatility, closes), isNull);
      final daily = [
        for (var i = 0; i < 30; i++)
          (DateTime.utc(2025, 1, 1 + i), d(i.isEven ? '100' : '101')),
      ];
      expect(liveFigure(LiveExample.volatility, daily), greaterThan(d('0.1')));
    });

    test('currency: how the euro value of one unit moved; none in euros', () {
      final rates = [(day(1, 2), d('0.90')), (day(12, 31), d('0.99'))];
      expect(liveFigure(LiveExample.currency, closes, rates: rates), d('0.1'));
      expect(liveFigure(LiveExample.currency, closes), isNull);
    });

    test('no close: no figure', () {
      for (final kind in LiveExample.values) {
        expect(liveFigure(kind, const []), isNull, reason: '$kind');
      }
    });
  });
}
