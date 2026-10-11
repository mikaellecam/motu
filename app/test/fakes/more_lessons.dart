import 'dart:convert';

import 'lesson_pack.dart' show text;

/// A lesson pack for the players of M6-4: `ae.march` (decision on the world
/// ETF in March 2020), `ae.ladder` (sort: a Livret, a calm and a wild
/// series), `ae.calm` (build_puzzle: two series moving against each other
/// and a wild one) and `ae.quiz` (checkpoint, two questions).

/// [n] daily closes from 2024-01-01, each day moving by the next of [moves].
List<List<Object>> daily(int n, List<double> moves) {
  var price = 100.0;
  return [
    for (var i = 0; i < n; i++)
      [
        DateTime.utc(2024, 1, 1 + i).toIso8601String().substring(0, 10),
        num.parse(
          (i == 0 ? price : price *= 1 + moves[i % moves.length])
              .toStringAsFixed(4),
        ),
      ],
  ];
}

Map<String, Object> _dataset(
  String id,
  String interval,
  List<List<Object>> points,
) => {
  'id': id,
  'source': 'twelvedata',
  'adjusted': true,
  'currency': 'USD',
  'interval': interval,
  'frozen_at': '2026-10-06',
  'points': points,
};

String morePackJson() => jsonEncode({
  'island': {
    'id': 'actions-etf',
    'version': 1,
    'title': text('Actions & ETF'),
    'nodes': ['ae.march', 'ae.ladder', 'ae.calm', 'ae.quiz'],
  },
  'nodes': [
    {
      'id': 'ae.march',
      'type': 'decision',
      'title': text('Mars 2020 : vendre ou tenir ?'),
      'status': 'draft',
      'datasets': ['ds.world-2020'],
      'context': text(
        'Le 20 mars 2020, les marchés ont perdu un tiers en un mois.',
      ),
      'moment': '2020-03-20',
      'series': {'dataset': 'ds.world-2020', 'label': text('ETF Monde')},
      'invested': 10000,
      'choices': [
        for (final (id, label, kept) in [
          ('hold', 'Garder', 1),
          ('half', 'Vendre la moitié', 0.5),
          ('sell', 'Tout vendre', 0),
        ])
          {
            'id': id,
            'label': text(label),
            'upside': text('Si ça remonte : $label gagne.'),
            'downside': text('Si ça baisse : $label perd.'),
            'kept': kept,
          },
      ],
      'explanation': text('Le marché a tout repris en quelques mois.'),
    },
    {
      'id': 'ae.ladder',
      'type': 'sort',
      'title': text('Classe par risque'),
      'status': 'draft',
      'datasets': ['ds.calm', 'ds.wild'],
      'prompt': text('Range-les du moins risqué au plus risqué.'),
      'scale': {'low': text('Moins risqué'), 'high': text('Plus risqué')},
      'items': [
        {'id': 'wild', 'label': text('Action seule'), 'dataset': 'ds.wild'},
        {'id': 'livret', 'label': text('Livret A'), 'value': 0},
        {'id': 'calm', 'label': text('ETF Monde'), 'dataset': 'ds.calm'},
      ],
      'explanation': text('Plus ça bouge, plus c\'est risqué.'),
    },
    {
      'id': 'ae.calm',
      'type': 'build_puzzle',
      'title': text('Construis un portefeuille calme'),
      'status': 'draft',
      'datasets': ['ds.calm', 'ds.counter', 'ds.wild'],
      'prompt': text('Moins de 5 % de volatilité, avec au moins 2 actifs.'),
      'assets': [
        {'dataset': 'ds.calm', 'label': text('ETF Monde'), 'region': 'world'},
        {'dataset': 'ds.counter', 'label': text('Obligations'), 'region': 'us'},
        {'dataset': 'ds.wild', 'label': text('Action seule'), 'region': 'us'},
      ],
      'rules': {'max_volatility': 0.05, 'min_assets': 2, 'min_regions': 2},
      'step': 0.1,
      'explanation': text('Des actifs qui ne bougent pas ensemble se calment.'),
    },
    {
      'id': 'ae.quiz',
      'type': 'checkpoint',
      'title': text('Point d\'étape'),
      'status': 'draft',
      'questions': [
        {
          'question': text('Un ETF Monde, c\'est…'),
          'choices': [
            {'id': 'one', 'label': text('Une seule entreprise')},
            {'id': 'many', 'label': text('Des milliers d\'entreprises')},
          ],
          'answer': 'many',
          'explanation': text('Il suit un indice de milliers d\'entreprises.'),
        },
        {
          'question': text('Les frais se composent-ils ?'),
          'choices': [
            {'id': 'yes', 'label': text('Oui')},
            {'id': 'no', 'label': text('Non')},
          ],
          'answer': 'yes',
        },
      ],
    },
  ],
  'datasets': [
    _dataset('ds.world-2020', '1week', [
      ['2020-02-14', 80],
      ['2020-02-21', 78],
      ['2020-03-20', 56],
      ['2020-06-19', 70],
      ['2021-02-26', 95.2],
    ]),
    _dataset('ds.calm', '1day', daily(60, [0.004, -0.004])),
    _dataset('ds.counter', '1day', daily(60, [-0.004, 0.004])),
    _dataset('ds.wild', '1day', daily(60, [0.03, -0.03])),
  ],
  'glossary': const [],
});
