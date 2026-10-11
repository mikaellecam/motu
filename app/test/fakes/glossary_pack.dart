import 'dart:convert';

import 'lesson_pack.dart' show text;

/// A pack for the glossary: five terms (« Écart » files under E), one lesson
/// that links `etf`, a quiz on `etf`, live examples on `volatilite` and
/// `risque-de-change`.
Map<String, Object?> _term(
  String id,
  String title, {
  List<String> related = const [],
  String? widget,
  List<Object>? quiz,
  bool forYou = false,
}) => {
  'id': id,
  'status': 'draft',
  'title': text(title),
  'short': text('$title, en une ligne.'),
  'body': text('$title, expliqué. Voir aussi {{indice}}.'),
  if (forYou) 'for_you': text('Ce que $title change pour toi.'),
  'related': related,
  if (widget != null) 'live_example': {'widget': widget},
  'quiz': ?quiz,
};

String glossaryPackJson() => jsonEncode({
  'island': {
    'id': 'actions-etf',
    'version': 1,
    'title': text('Actions & ETF'),
    'nodes': ['ae.fees'],
  },
  'nodes': [
    {
      'id': 'ae.fees',
      'type': 'mission',
      'title': text('Ton premier ETF'),
      'status': 'draft',
      'glossary': ['etf'],
      'goal': text('Achète un ETF.'),
      'go': 'explorer',
    },
  ],
  'datasets': const [],
  'glossary': [
    _term(
      'etf',
      'ETF',
      related: ['indice', 'diversification'],
      forYou: true,
      quiz: [
        {
          'question': text('Un ETF suit…'),
          'choices': [
            {'id': 'index', 'label': text('Un indice')},
            {'id': 'one', 'label': text('Une seule action')},
          ],
          'answer': 'index',
        },
        {
          'question': text('Ses frais sont…'),
          'choices': [
            {'id': 'low', 'label': text('Souvent bas')},
            {'id': 'high', 'label': text('Toujours hauts')},
          ],
          'answer': 'low',
        },
      ],
    ),
    _term('indice', 'Indice'),
    _term('diversification', 'Diversification'),
    _term('ecart', 'Écart', widget: 'performance'),
    _term('volatilite', 'Volatilité', widget: 'volatility'),
    _term('risque-de-change', 'Risque de change', widget: 'currency'),
  ],
});
