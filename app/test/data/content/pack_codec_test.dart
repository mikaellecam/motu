import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small valid pack; [edit] breaks it on purpose.
String pack({void Function(Map<String, dynamic> json)? edit}) {
  final json = <String, dynamic>{
    'island': {
      'id': 'actions-etf',
      'version': 3,
      'title': {'fr': 'Actions & ETF', 'en': 'Stocks & ETFs'},
      'nodes': ['ae.one', 'ae.two'],
    },
    'nodes': [
      {
        'id': 'ae.two',
        'type': 'toy',
        'title': {'fr': 'Deux', 'en': 'Two'},
        'status': 'published',
      },
      {
        'id': 'ae.one',
        'type': 'predict_reveal',
        'title': {'fr': 'Un', 'en': 'One'},
        'status': 'draft',
        'question': {'fr': 'Lequel ?', 'en': 'Which?'},
        'answer': 'apple',
        'datasets': ['ds.aapl'],
        'glossary': ['volatilite'],
        'bridge': {'date': '2020-02-18', 'difficulty': 'realiste'},
      },
    ],
    'datasets': [
      {
        'id': 'ds.aapl',
        'source': 'twelvedata',
        'adjusted': true,
        'currency': 'USD',
        'interval': '1week',
        'frozen_at': '2026-10-06',
        'points': [
          ['2022-01-03', 177.57],
          ['2022-01-10', 172],
        ],
      },
    ],
    'glossary': [
      {
        'id': 'volatilite',
        'title': {'fr': 'Volatilité', 'en': 'Volatility'},
        'short': {'fr': 'Une ligne.', 'en': 'One line.'},
        'body': {'fr': 'Un texte.', 'en': 'A text.'},
        'related': ['pire-baisse'],
      },
      {
        'id': 'pire-baisse',
        'title': {'fr': 'Pire baisse', 'en': 'Worst drop'},
        'short': {'fr': 'Une ligne.', 'en': 'One line.'},
        'body': {'fr': 'Un texte.', 'en': 'A text.'},
      },
    ],
  };
  edit?.call(json);
  return jsonEncode(json);
}

void main() {
  test('the bundled Actions & ETF pack reads: 12 nodes in path order', () {
    final bundled = decodePack(
      File('assets/packs/actions-etf.json').readAsStringSync(),
    );
    expect(bundled.id, 'actions-etf');
    expect(bundled.title.of('en'), 'Stocks & ETFs');
    expect(bundled.nodes, hasLength(12));
    expect(bundled.nodes.first.id, 'ae.livret-vs-etf');
    expect(bundled.nodes.first.title.of('fr'), 'Livret ou ETF ?');
    expect(bundled.nodes.last.type, NodeType.checkpoint);
    expect(
      [
        for (final n in bundled.nodes)
          if (n.bridge != null) (n.id, n.bridge!.date),
      ],
      [('ae.march-2020', DateTime.utc(2020, 2, 18))],
    );
    expect(
      [for (final n in bundled.path) n.type]
          .where((t) => t == NodeType.mission),
      hasLength(3),
    );
  });

  test('nodes, datasets and terms, with type fields kept for the player', () {
    final p = decodePack(pack());
    expect(
      [for (final n in p.nodes) n.id],
      ['ae.one', 'ae.two'],
      reason: 'island order',
    );
    final one = p.nodes.first;
    expect(one.status, ContentStatus.draft);
    expect(one.payload['answer'], 'apple');
    expect(one.payload.containsKey('title'), isFalse);
    final points = p.datasets['ds.aapl']!.points;
    expect(points.first, (DateTime.utc(2022, 1, 3), Decimal.parse('177.57')));
    expect(points.last.$2, Decimal.parse('172'));
    expect(p.glossary['volatilite']!.related, ['pire-baisse']);
    expect(one.bridge!.date, DateTime.utc(2020, 2, 18));
    expect(one.bridge!.difficulty, 'realiste');
    expect(one.payload.containsKey('bridge'), isFalse);
    expect(p.nodes.last.bridge, isNull);
  });

  group('a corrupt pack is refused', () {
    for (final (what, edit) in <(String, void Function(Map<String, dynamic>))>[
      ('a missing locale', (j) => (j['island']['title'] as Map).remove('en')),
      ('an empty text', (j) => j['nodes'][0]['title']['fr'] = ''),
      ('an unknown node type', (j) => j['nodes'][0]['type'] = 'quiz'),
      ('an unknown status', (j) => j['nodes'][0]['status'] = 'final'),
      (
        'an island node without content',
        (j) => (j['island']['nodes'] as List).add('ae.three'),
      ),
      ('an unknown dataset', (j) => j['nodes'][1]['datasets'] = ['ds.nope']),
      ('an unknown term', (j) => j['nodes'][1]['glossary'] = ['nope']),
      (
        'an unknown related term',
        (j) => j['glossary'][1]['related'] = ['nope'],
      ),
      (
        'a malformed point',
        (j) => j['datasets'][0]['points'] = [
          ['2022-01-03'],
        ],
      ),
      ('a bad date', (j) => j['datasets'][0]['frozen_at'] = 'hier'),
      ('a version that is not a number', (j) => j['island']['version'] = '3'),
      ('no glossary list', (j) => j.remove('glossary')),
      (
        'a bridge without a date',
        (j) => j['nodes'][1]['bridge'] = {'difficulty': 'serre'},
      ),
    ]) {
      test(what, () {
        expect(() => decodePack(pack(edit: edit)), throwsFormatException);
      });
    }

    test('not JSON at all', () {
      expect(() => decodePack('{"island": '), throwsFormatException);
    });
  });
}
