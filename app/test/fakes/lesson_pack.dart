import 'dart:convert';

/// A lesson pack for the node players: `ae.apple` (predict_reveal: Apple vs
/// the world ETF in 2022, from 1 000 $, live over a year), `ae.fees` (toy:
/// two fee levels, the return from a world ETF that doubled from 2010 to
/// 2020), and `ae.mission`, a mission done in the Explorer (or [missionGo]). `ae.apple` bridges
/// into a trip on 2022-01-03.

Map<String, Object> text(String s) => {'fr': s, 'en': s};

Map<String, Object> dataset(
  String id,
  List<List<Object>> points, {
  String? asset,
}) => {
  'id': id,
  'source': 'twelvedata',
  'asset': ?asset,
  'adjusted': true,
  'currency': 'USD',
  'interval': '1week',
  'frozen_at': '2026-10-06',
  'points': points,
};

String packJson({
  String? worldAsset = 'world',
  Object? choices,
  String missionGo = 'explorer',
}) => jsonEncode({
  'island': {
    'id': 'actions-etf',
    'version': 1,
    'title': text('Actions & ETF'),
    'nodes': ['ae.apple', 'ae.fees', 'ae.mission'],
  },
  'nodes': [
    {
      'id': 'ae.apple',
      'type': 'predict_reveal',
      'title': text('Apple ou ETF Monde ?'),
      'status': 'draft',
      'bridge': {'date': '2022-01-03', 'difficulty': 'realiste'},
      'datasets': ['ds.aapl', 'ds.acwi'],
      'question': text('Lequel a le plus chuté ?'),
      'choices':
          choices ??
          [
            {'id': 'apple', 'label': text('Apple')},
            {'id': 'world', 'label': text('ETF Monde')},
          ],
      'answer': 'apple',
      'series': [
        {'dataset': 'ds.aapl', 'label': text('Apple')},
        {'dataset': 'ds.acwi', 'label': text('ETF Monde')},
      ],
      'invested': 1000,
      'explanation': text(
        'Une seule entreprise : pas de {{diversification|diversification}}, '
        'la {{diversification}} se voit sur la durée.',
      ),
      'live_variant': {'widget': 'compare_returns', 'period': '1y'},
    },
    {
      'id': 'ae.fees',
      'type': 'toy',
      'title': text('Le jouet des frais'),
      'status': 'draft',
      'datasets': ['ds.acwi-10y'],
      'formula': 'fees',
      'intro': text('Deux niveaux de frais.'),
      'explanation': text('Les frais se composent.'),
      'return_from': {'dataset': 'ds.acwi-10y', 'label': text("l'ETF Monde")},
      'controls': [
        for (final (id, min, max, step, init) in [
          ('amount', 1000, 100000, 1000, 10000),
          ('years', 1, 40, 1, 30),
          ('return', -0.05, 0.12, 0.005, 0.05),
          ('fee_low', 0, 0.03, 0.001, 0.002),
          ('fee_high', 0, 0.03, 0.001, 0.015),
        ])
          {
            'id': id,
            'label': text(id),
            'min': min,
            'max': max,
            'step': step,
            'default': init,
          },
      ],
    },
    {
      'id': 'ae.mission',
      'type': 'mission',
      'title': text('Ton premier ETF'),
      'status': 'draft',
      'goal': text('Achète un ETF dans ton portefeuille.'),
      'go': missionGo,
    },
  ],
  'datasets': [
    dataset('ds.aapl', [
      ['2022-01-07', 172.17],
      ['2022-12-30', 129.93],
    ], asset: 'apple'),
    dataset('ds.acwi', [
      ['2022-01-07', 100],
      ['2022-12-30', 82],
    ], asset: worldAsset),
    // × 2 in 10 years.
    dataset('ds.acwi-10y', [
      ['2010-01-01', 50],
      ['2020-01-01', 100],
    ]),
  ],
  'glossary': [
    {
      'id': 'diversification',
      'status': 'draft',
      'title': {'fr': 'Diversification', 'en': 'Diversification'},
      'short': text('Ne pas tout miser sur un seul actif.'),
      'body': text('Répartir son argent.'),
    },
  ],
});

/// Les bases with no lesson nor term: tests of Actions & ETF's lessons load
/// it beside theirs, as every playable island loads (M12-6).
String emptyBasesJson() => jsonEncode({
  'island': {
    'id': 'les-bases',
    'version': 1,
    'title': text('Les bases'),
    'nodes': <String>[],
  },
  'nodes': <Object>[],
  'datasets': <Object>[],
  'glossary': <Object>[],
});
