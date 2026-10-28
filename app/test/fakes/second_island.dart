import 'dart:convert';

import 'lesson_pack.dart';

/// A second island beside the lesson pack's Actions & ETF: `les-bases`, a
/// checkpoint `lb.quiz`, the mission `lb.mission` (its goal links a term of
/// its own and the lesson pack's `diversification`), then `lb.last`.
String secondIslandJson() => jsonEncode({
  'island': {
    'id': 'les-bases',
    'version': 1,
    'title': text('Les bases'),
    'nodes': ['lb.quiz', 'lb.mission', 'lb.last'],
  },
  'nodes': [
    {
      'id': 'lb.quiz',
      'type': 'checkpoint',
      'title': text('Repère l\'arnaque'),
      'status': 'draft',
    },
    {
      'id': 'lb.mission',
      'type': 'mission',
      'title': text('Range ton matelas'),
      'status': 'draft',
      'goal': text(
        'Verse sur ton Livret A : ton {{pouvoir-d-achat}}, '
        'puis la {{diversification}}.',
      ),
      'go': 'wallet',
    },
    {
      'id': 'lb.last',
      'type': 'checkpoint',
      'title': text('Point d\'étape'),
      'status': 'draft',
    },
  ],
  'datasets': <Object>[],
  'glossary': [
    {
      'id': 'pouvoir-d-achat',
      'status': 'draft',
      'title': {'fr': "Pouvoir d'achat", 'en': 'Purchasing power'},
      'short': text("Ce qu'une somme permet d'acheter."),
      'body': text('Il baisse quand les prix montent.'),
    },
  ],
});
