import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/toys.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> text(String s) => {'fr': s, 'en': s};

Map<String, Object> dataset(String id, {String? asset}) => {
  'id': id,
  'source': 'twelvedata',
  'asset': ?asset,
  'adjusted': true,
  'currency': 'USD',
  'interval': '1week',
  'frozen_at': '2026-10-06',
  'points': [
    ['2022-01-07', 172.17],
    ['2022-12-30', 129.93],
  ],
};

Map<String, Object?> reveal() => {
  'id': 'ae.apple',
  'type': 'predict_reveal',
  'title': text('Apple ou ETF Monde ?'),
  'status': 'draft',
  'datasets': ['ds.aapl', 'ds.acwi'],
  'question': text('Lequel a le plus chuté ?'),
  'choices': [
    {'id': 'apple', 'label': text('Apple')},
    {'id': 'world', 'label': text('ETF Monde')},
  ],
  'answer': 'apple',
  'series': [
    {'dataset': 'ds.aapl', 'label': text('Apple')},
    {'dataset': 'ds.acwi', 'label': text('ETF Monde')},
  ],
  'invested': 1000,
  'explanation': text('Une seule entreprise.'),
  'live_variant': {'widget': 'compare_returns', 'period': '1y'},
};

Map<String, Object?> control(String id, num min, num max, num step, num init) =>
    {
      'id': id,
      'label': text(id),
      'min': min,
      'max': max,
      'step': step,
      'default': init,
    };

Map<String, Object?> toy() => {
  'id': 'ae.fees',
  'type': 'toy',
  'title': text('Le jouet des frais'),
  'status': 'draft',
  'datasets': ['ds.acwi'],
  'formula': 'fees',
  'intro': text('Deux ETF, deux niveaux de frais.'),
  'explanation': text('Les frais se composent aussi.'),
  'return_from': {'dataset': 'ds.acwi', 'label': text("l'ETF Monde")},
  'controls': [
    control('amount', 1000, 100000, 1000, 10000),
    control('years', 1, 40, 1, 30),
    control('return', -0.05, 0.12, 0.005, 0.05),
    control('fee_low', 0, 0.03, 0.001, 0.002),
    control('fee_high', 0, 0.03, 0.001, 0.015),
  ],
};

/// A pack holding [nodes]; [edit] changes the one under test.
ContentPack packWith(Map<String, Object?> node) => decodePack(
  jsonEncode({
    'island': {
      'id': 'actions-etf',
      'version': 1,
      'title': text('Actions & ETF'),
      'nodes': [node['id']],
    },
    'nodes': [node],
    'datasets': [dataset('ds.aapl', asset: 'apple'), dataset('ds.acwi')],
    'glossary': const [],
  }),
);

void main() {
  group('predict_reveal', () {
    test('the question, its choices, the curves and the live variant', () {
      final pack = packWith(reveal());
      final node = decodePredictReveal(pack.nodes.single, pack);
      expect(node.question.fr, 'Lequel a le plus chuté ?');
      expect([for (final c in node.choices) c.id], ['apple', 'world']);
      expect(node.answer, 'apple');
      expect([for (final s in node.series) s.dataset], ['ds.aapl', 'ds.acwi']);
      expect(node.invested, Decimal.fromInt(1000));
      expect(node.liveVariant!.period, '1y');
      expect(pack.datasets['ds.aapl']!.asset, 'apple');
      expect(pack.datasets['ds.acwi']!.asset, isNull);
    });

    test('no amount draws base 100; no live variant, none', () {
      final pack = packWith(
        reveal()
          ..remove('invested')
          ..remove('live_variant'),
      );
      final node = decodePredictReveal(pack.nodes.single, pack);
      expect(node.invested, isNull);
      expect(node.liveVariant, isNull);
    });

    test('an unknown live widget is no live variant', () {
      final pack = packWith(
        reveal()..['live_variant'] = {'widget': 'radar', 'period': '1y'},
      );
      expect(decodePredictReveal(pack.nodes.single, pack).liveVariant, isNull);
    });

    for (final (what, edit) in <(String, void Function(Map<String, Object?>))>[
      ('an answer that is no choice', (n) => n['answer'] = 'gold'),
      ('no choice', (n) => n['choices'] = const []),
      (
        'a curve of a dataset the node does not draw',
        (n) => n['series'] = [
          {'dataset': 'ds.gold', 'label': text('Or')},
        ],
      ),
      ('no curve', (n) => n['series'] = const []),
      ('an amount of zero', (n) => n['invested'] = 0),
      ('no explanation', (n) => n.remove('explanation')),
    ]) {
      test('refused: $what', () {
        final node = reveal();
        edit(node);
        final pack = packWith(node);
        expect(
          () => decodePredictReveal(pack.nodes.single, pack),
          throwsFormatException,
          reason: what,
        );
      });
    }
  });

  group('toy', () {
    test('the formula, its sliders and where the return starts', () {
      final pack = packWith(toy());
      final node = decodeToy(pack.nodes.single, pack);
      expect(node.formula, ToyFormula.fees);
      expect([for (final c in node.controls) c.id], ToyFormula.fees.inputs);
      final ret = node.controls[2];
      expect(
        (ret.min, ret.max, ret.step, ret.initial),
        (
          Decimal.parse('-0.05'),
          Decimal.parse('0.12'),
          Decimal.parse('0.005'),
          Decimal.parse('0.05'),
        ),
      );
      expect(node.returnFrom!.dataset, 'ds.acwi');
      expect(node.returnFrom!.label.fr, "l'ETF Monde");
    });

    for (final (what, edit) in <(String, void Function(Map<String, Object?>))>[
      ('an unknown formula', (n) => n['formula'] = 'tax'),
      ('a missing control', (n) => (n['controls']! as List).removeAt(0)),
      (
        'a control the formula does not read',
        (n) => (n['controls']! as List).add(control('tax', 0, 1, 0.1, 0.5)),
      ),
      (
        'a start outside the range',
        (n) => (n['controls']! as List)[1] = control('years', 1, 40, 1, 50),
      ),
      (
        'a step of zero',
        (n) => (n['controls']! as List)[1] = control('years', 1, 40, 0, 30),
      ),
      (
        'a return from a dataset the node does not draw',
        (n) => n['return_from'] = {'dataset': 'ds.aapl', 'label': text('x')},
      ),
    ]) {
      test('refused: $what', () {
        final node = toy();
        edit(node);
        final pack = packWith(node);
        expect(
          () => decodeToy(pack.nodes.single, pack),
          throwsFormatException,
          reason: what,
        );
      });
    }
  });
}
