import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> text(String s) => {'fr': s, 'en': s};

/// The world ETF around March 2020, weekly; two daily series.
final datasets = [
  {
    'id': 'ds.world-2020',
    'source': 'twelvedata',
    'asset': 'world',
    'adjusted': true,
    'currency': 'USD',
    'interval': '1week',
    'frozen_at': '2026-10-06',
    'points': [
      ['2020-02-14', 80],
      ['2020-03-20', 56],
      ['2021-02-26', 95],
    ],
  },
  for (final id in ['ds.a-daily', 'ds.b-daily'])
    {
      'id': id,
      'source': 'twelvedata',
      'adjusted': true,
      'currency': 'USD',
      'interval': '1day',
      'frozen_at': '2026-10-06',
      'points': [
        ['2024-01-02', 100],
        ['2024-01-03', 101],
      ],
    },
];

Map<String, Object?> node(String type, Map<String, Object?> payload) => {
  'id': 'ae.node',
  'type': type,
  'title': text('Un nœud'),
  'status': 'draft',
  'datasets': ['ds.world-2020', 'ds.a-daily', 'ds.b-daily'],
  'explanation': text('Ce qui s\'est passé.'),
  ...payload,
};

Map<String, Object?> decision() => node('decision', {
  'context': text(
    'Le 20 mars 2020, les marchés ont perdu un tiers en un mois.',
  ),
  'moment': '2020-03-20',
  'series': {'dataset': 'ds.world-2020', 'label': text('ETF Monde')},
  'invested': 10000,
  'choices': [
    for (final (id, kept) in [('hold', 1), ('half', 0.5), ('sell', 0)])
      {
        'id': id,
        'label': text(id),
        'upside': text('+'),
        'downside': text('−'),
        'kept': kept,
      },
  ],
});

Map<String, Object?> sort() => node('sort', {
  'prompt': text('Du moins risqué au plus risqué.'),
  'scale': {'low': text('Moins risqué'), 'high': text('Plus risqué')},
  'items': [
    {'id': 'livret', 'label': text('Livret A'), 'value': 0},
    {'id': 'a', 'label': text('A'), 'dataset': 'ds.a-daily'},
    {'id': 'b', 'label': text('B'), 'dataset': 'ds.b-daily'},
  ],
});

Map<String, Object?> puzzle() => node('build_puzzle', {
  'prompt': text('Un portefeuille calme.'),
  'assets': [
    {'dataset': 'ds.a-daily', 'label': text('A'), 'region': 'us'},
    {'dataset': 'ds.b-daily', 'label': text('B'), 'region': 'europe'},
  ],
  'rules': {'max_volatility': 0.12, 'min_assets': 2, 'min_regions': 2},
  'step': 0.1,
});

Map<String, Object?> checkpoint() => node('checkpoint', {
  'questions': [
    for (final answer in ['a', 'b'])
      {
        'question': text('Laquelle ?'),
        'choices': [
          {'id': 'a', 'label': text('A')},
          {'id': 'b', 'label': text('B')},
        ],
        'answer': answer,
        if (answer == 'a') 'explanation': text('Parce que.'),
      },
  ],
});

ContentPack packWith(Map<String, Object?> n) => decodePack(
  jsonEncode({
    'island': {
      'id': 'actions-etf',
      'version': 1,
      'title': text('Actions & ETF'),
      'nodes': ['ae.node'],
    },
    'nodes': [n],
    'datasets': datasets,
    'glossary': const [],
  }),
);

T decoded<T>(
  Map<String, Object?> n,
  T Function(NodeContent, ContentPack) decode,
) {
  final pack = packWith(n);
  return decode(pack.nodes.single, pack);
}

void refused(
  String what,
  Map<String, Object?> Function() base,
  void Function(Map<String, Object?> n) edit,
  Object Function(NodeContent, ContentPack) decode,
) => test('refused: $what', () {
  final n = base();
  edit(n);
  expect(() => decoded(n, decode), throwsFormatException);
});

List<Object?> list(Map<String, Object?> n, String key) => n[key]! as List;

void main() {
  group('decision', () {
    test('the moment, the curve, the choices and what each keeps', () {
      final d = decoded(decision(), decodeDecision);
      expect(d.moment, DateTime.utc(2020, 3, 20));
      expect(d.dataset, 'ds.world-2020');
      expect(d.invested, Decimal.fromInt(10000));
      expect(
        [for (final c in d.choices) (c.id, c.kept)],
        [
          ('hold', Decimal.one),
          ('half', Decimal.parse('0.5')),
          ('sell', Decimal.zero),
        ],
      );
    });

    refused(
      'a moment before the curve',
      decision,
      (n) => n['moment'] = '2019-01-01',
      decodeDecision,
    );
    refused(
      'a moment with nothing after it',
      decision,
      (n) => n['moment'] = '2021-02-26',
      decodeDecision,
    );
    refused(
      'a single choice',
      decision,
      (n) => list(n, 'choices').removeRange(1, 3),
      decodeDecision,
    );
    refused(
      'a share kept above all',
      decision,
      (n) => (list(n, 'choices')[0]! as Map)['kept'] = 1.5,
      decodeDecision,
    );
    refused('no amount', decision, (n) => n.remove('invested'), decodeDecision);
  });

  group('sort', () {
    test('the scale and its items, fixed or from a daily dataset', () {
      final s = decoded(sort(), decodeSort);
      expect(s.low.fr, 'Moins risqué');
      expect(
        [for (final i in s.items) (i.id, i.dataset, i.value)],
        [
          ('livret', null, Decimal.zero),
          ('a', 'ds.a-daily', null),
          ('b', 'ds.b-daily', null),
        ],
      );
    });

    refused(
      'an item with both a dataset and a value',
      sort,
      (n) => (list(n, 'items')[1]! as Map)['value'] = 1,
      decodeSort,
    );
    refused(
      'an item with neither',
      sort,
      (n) => (list(n, 'items')[1]! as Map).remove('dataset'),
      decodeSort,
    );
    refused(
      'a weekly dataset',
      sort,
      (n) => (list(n, 'items')[1]! as Map)['dataset'] = 'ds.world-2020',
      decodeSort,
    );
    refused(
      'twice the same item',
      sort,
      (n) => (list(n, 'items')[2]! as Map)['id'] = 'a',
      decodeSort,
    );
    refused(
      'a single item',
      sort,
      (n) => list(n, 'items').removeRange(1, 3),
      decodeSort,
    );
  });

  group('build_puzzle', () {
    test('the assets, the rules and the step', () {
      final p = decoded(puzzle(), decodePuzzle);
      expect(
        [for (final a in p.assets) (a.dataset, a.region)],
        [('ds.a-daily', 'us'), ('ds.b-daily', 'europe')],
      );
      expect(
        (p.rules.maxVolatility, p.rules.minAssets, p.rules.minRegions),
        (Decimal.parse('0.12'), 2, 2),
      );
      expect(p.step, Decimal.parse('0.1'));
    });

    test('rules other than the volatility are optional', () {
      final n = puzzle()..['rules'] = {'max_volatility': 0.12};
      final p = decoded(n, decodePuzzle);
      expect((p.rules.minAssets, p.rules.minRegions), (null, null));
    });

    refused(
      'a weekly dataset',
      puzzle,
      (n) => (list(n, 'assets')[0]! as Map)['dataset'] = 'ds.world-2020',
      decodePuzzle,
    );
    refused(
      'no volatility cap',
      puzzle,
      (n) => n['rules'] = {'min_assets': 2},
      decodePuzzle,
    );
    refused(
      'a step that does not divide 100 %',
      puzzle,
      (n) => n['step'] = 0.3,
      decodePuzzle,
    );
    refused(
      'more assets asked than offered',
      puzzle,
      (n) => n['rules'] = {'max_volatility': 0.12, 'min_assets': 3},
      decodePuzzle,
    );
  });

  group('checkpoint', () {
    test('questions, their choices, answers and explanations', () {
      final c = decoded(checkpoint(), decodeCheckpoint);
      expect([for (final q in c.questions) q.answer], ['a', 'b']);
      expect(c.questions.first.explanation!.fr, 'Parce que.');
      expect(c.questions.last.explanation, isNull);
    });

    refused(
      'an answer that is no choice',
      checkpoint,
      (n) => (list(n, 'questions')[0]! as Map)['answer'] = 'z',
      decodeCheckpoint,
    );
    refused(
      'no question',
      checkpoint,
      (n) => n['questions'] = const [],
      decodeCheckpoint,
    );
  });
}
