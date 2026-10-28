import 'dart:convert';

import 'lesson_pack.dart';

/// Les bases' two toys (M12-3): `lb.safety-cushion` (1 500 € a month, 3
/// months, 200 € put aside, from nothing) and `lb.loan-cost` (3 000 € over 36
/// months at 20 % a year), then `lb.spot-the-scam`, a quiz (M12-4). Its
/// explanations link the lesson pack's term.
String basesToysJson() => jsonEncode({
  'island': {
    'id': 'les-bases',
    'version': 1,
    'title': text('Les bases'),
    'nodes': ['lb.safety-cushion', 'lb.loan-cost', 'lb.spot-the-scam'],
  },
  'nodes': [
    {
      'id': 'lb.safety-cushion',
      'type': 'toy',
      'title': text('Ton matelas de sécurité'),
      'status': 'draft',
      'formula': 'cushion',
      'intro': text('Quelques mois de dépenses mis de côté.'),
      'explanation': text('Pas de {{diversification}} pour un matelas.'),
      'controls': [
        for (final (id, min, max, step, init) in [
          ('spending', 500, 3000, 100, 1500),
          ('months', 3, 6, 1, 3),
          ('saving', 0, 500, 50, 200),
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
      'id': 'lb.loan-cost',
      'type': 'toy',
      'title': text("Le vrai prix d'un crédit"),
      'status': 'draft',
      'formula': 'loan',
      'intro': text('Tu empruntes et tu rends chaque mois.'),
      'explanation': text('Les intérêts.'),
      'controls': [
        for (final (id, min, max, step, init) in [
          ('amount', 500, 10000, 100, 3000),
          ('months', 6, 60, 6, 36),
          ('rate', 0.01, 0.22, 0.005, 0.2),
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
      'id': 'lb.spot-the-scam',
      'type': 'quiz',
      'title': text("Repère l'arnaque"),
      'status': 'draft',
      'questions': [
        {
          'question': text('Un placement « garanti » à 10 % par mois…'),
          'choices': [
            {'id': 'scam', 'label': text('Une arnaque')},
            {'id': 'deal', 'label': text('Une bonne affaire')},
          ],
          'answer': 'scam',
        },
      ],
    },
  ],
  'datasets': <Object>[],
  'glossary': <Object>[],
});
