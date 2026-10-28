import 'dart:convert';
import 'dart:io';

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/presentation/features/node/node_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// The island's lessons as the app bundles them (M6-8, draft copy on
// datasets frozen by cmd/freeze).

void main() {
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );
  final overrides = <Override>[
    contentPackProvider(actionsEtfIsland).overrideWith((ref) async => pack),
    cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
  ];

  screenshot(
    'm6-3-predict-reveal',
    const NodeScreen(nodeId: 'ae.apple-vs-world-2022'),
    size: const Size(390, 1050),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('Apple'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );

  // Captured a second into the reveal: the curves half drawn, the figures
  // still counting (M7-4).
  screenshot(
    'm7-4-reveal-drawing',
    const NodeScreen(nodeId: 'ae.livret-vs-etf'),
    size: const Size(390, 1150),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('À peu près pareil'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
    },
  );

  screenshot(
    'm6-8-livret-vs-etf',
    const NodeScreen(nodeId: 'ae.livret-vs-etf'),
    size: const Size(390, 1150),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('À peu près pareil'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );

  screenshot(
    'm6-8-dollar-trap',
    const NodeScreen(nodeId: 'ae.dollar-trap'),
    size: const Size(390, 1250),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('Environ 14\u202f%'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );

  screenshot(
    'm6-8-compound-toy',
    const NodeScreen(nodeId: 'ae.compound-toy'),
    size: const Size(390, 1050),
    overrides: overrides,
  );

  // Les bases' toys (M12-3), on the canvas's draft copy, beside the
  // bundled pack (its glossary).
  Map<String, String> t(String fr, String en) => {'fr': fr, 'en': en};
  Map<String, Object> slider(
    String id,
    String fr,
    num min,
    num max,
    num step,
    num start,
  ) => {
    'id': id,
    'label': t(fr, fr),
    'min': min,
    'max': max,
    'step': step,
    'default': start,
  };
  final bases = decodePack(
    jsonEncode({
      'island': {
        'id': 'les-bases',
        'version': 1,
        'title': t('Les bases', 'Foundations'),
        'nodes': ['lb.safety-cushion', 'lb.loan-cost'],
      },
      'nodes': [
        {
          'id': 'lb.safety-cushion',
          'type': 'toy',
          'status': 'draft',
          'title': t('Ton matelas de sécurité', 'Your safety cushion'),
          'formula': 'cushion',
          'intro': t(
            'Un matelas de sécurité, ce sont quelques mois de dépenses mis de '
                'côté pour les imprévus. Bouge les curseurs : combien de '
                'temps pour le remplir ?',
            'A safety cushion is a few months of spending put aside for the '
                'unexpected. Move the sliders: how long does it take to fill?',
          ),
          'explanation': t(
            "On l'évalue souvent à trois à six mois de dépenses. Sur un "
                '{{livret-a|Livret A}}, il reste disponible tout de suite et ne '
                'peut pas baisser : c\'est le {{matelas-de-securite|matelas de '
                'sécurité}}.',
            'It is often put at three to six months of spending. On a '
                '{{livret-a|Livret A}}, it stays available at once and cannot '
                'fall: that is the {{matelas-de-securite|safety cushion}}.',
          ),
          'controls': [
            slider('spending', 'Tes dépenses du mois', 500, 3000, 100, 1500),
            slider('months', 'Mois de réserve', 3, 6, 1, 3),
            slider('saving', 'Mis de côté chaque mois', 50, 500, 50, 200),
          ],
        },
        {
          'id': 'lb.loan-cost',
          'type': 'toy',
          'status': 'draft',
          'title': t("Le vrai prix d'un crédit", 'What a loan really costs'),
          'formula': 'loan',
          'intro': t(
            'Tu empruntes une somme et tu la rends chaque mois, avec des '
                'intérêts. Bouge les curseurs et regarde ce que le crédit '
                'coûte.',
            'You borrow a sum and pay it back each month, with interest. '
                'Move the sliders and see what the loan costs.',
          ),
          'explanation': t(
            'Plus le taux est haut et la durée longue, plus le crédit coûte '
                'cher : ce que tu paies en plus, ce sont les intérêts.',
            'The higher the rate and the longer the loan, the more it costs: '
                'what you pay on top is the interest.',
          ),
          'controls': [
            slider('amount', 'Somme empruntée', 500, 10000, 100, 3000),
            slider('months', 'Durée', 6, 60, 6, 36),
            slider('rate', 'Taux par an', 0.01, 0.22, 0.005, 0.2),
          ],
        },
      ],
      'datasets': <Object>[],
      'glossary': <Object>[],
    }),
  );
  final withBases = [
    ...overrides,
    contentPacksProvider.overrideWith((ref) async => [pack, bases]),
  ];
  screenshot(
    'm12-3-cushion-toy',
    const NodeScreen(nodeId: 'lb.safety-cushion'),
    size: const Size(390, 1150),
    overrides: withBases,
  );
  screenshot(
    'm12-3-loan-toy',
    const NodeScreen(nodeId: 'lb.loan-cost'),
    size: const Size(390, 1150),
    overrides: withBases,
  );

  screenshot(
    'm6-3-toy',
    const NodeScreen(nodeId: 'ae.fees-toy'),
    size: const Size(390, 1110),
    overrides: overrides,
  );

  screenshot(
    'm6-4-decision',
    const NodeScreen(nodeId: 'ae.march-2020'),
    size: const Size(390, 1400),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('Garder'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );

  screenshot(
    'm6-4-sort',
    const NodeScreen(nodeId: 'ae.risk-ladder'),
    size: const Size(390, 760),
    overrides: overrides,
    act: (tester) async {
      // Apple from the top to the bottom, then the real order.
      final handle = find.byIcon(Icons.drag_handle).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );

  screenshot(
    'm6-4-build-puzzle',
    const NodeScreen(nodeId: 'ae.calm-portfolio'),
    size: const Size(390, 900),
    overrides: overrides,
    act: (tester) async {
      // US bonds 50 %, international bonds 30 %, European stocks 20 %.
      for (final (i, share) in [(1, 0.5), (2, 0.3), (3, 0.2)]) {
        final slider = tester.getRect(find.byType(Slider).at(i));
        // The track starts and ends 24 px inside the slider.
        await tester.tapAt(
          Offset(
            slider.left + 24 + (slider.width - 48) * share,
            slider.center.dy,
          ),
        );
        await tester.pumpAndSettle();
      }
    },
  );

  screenshot(
    'm6-4-checkpoint',
    const NodeScreen(nodeId: 'ae.checkpoint-1'),
    size: const Size(390, 760),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.textContaining("Des milliers d'entreprises"));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );
}
