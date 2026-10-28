import 'dart:io';

import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/domain/learning/missions.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:flutter_test/flutter_test.dart';

// The Les bases pack as the app bundles it (M12-5): the nine lessons of the
// canvas « Les bases », in order, each playable.

void main() {
  final pack = decodePack(
    File('assets/packs/les-bases.json').readAsStringSync(),
  );

  test('the nine lessons, in order, of the types the canvas gives', () {
    expect(pack.title.fr, 'Les bases');
    expect(pack.title.en, 'Foundations');
    expect(
      [for (final n in pack.nodes) (n.id, n.type)],
      [
        ('lb.safety-cushion', NodeType.toy),
        ('lb.cash-inflation', NodeType.predictReveal),
        ('lb.livret-inflation', NodeType.predictReveal),
        ('lb.mission-livret', NodeType.mission),
        ('lb.cushion-2020', NodeType.decision),
        ('lb.loan-cost', NodeType.toy),
        ('lb.save-or-repay', NodeType.sort),
        ('lb.spot-the-scam', NodeType.quiz),
        ('lb.checkpoint-1', NodeType.checkpoint),
      ],
    );
  });

  test('every lesson plays: its payload decodes for its player', () {
    for (final node in pack.nodes) {
      switch (node.type) {
        case NodeType.predictReveal:
          decodePredictReveal(node, pack);
        case NodeType.toy:
          decodeToy(node, pack);
        case NodeType.decision:
          decodeDecision(node, pack);
        case NodeType.sort:
          decodeSort(node, pack);
        case NodeType.buildPuzzle:
          decodePuzzle(node, pack);
        case NodeType.checkpoint || NodeType.quiz:
          decodeCheckpoint(node, pack);
        case NodeType.mission:
          decodeMission(node, pack);
      }
    }
    expect(
      pack.glossary.keys,
      unorderedEquals([
        'pouvoir-d-achat',
        'taeg',
        'mensualite',
        'credit-renouvelable',
      ]),
    );
  });

  test('its mission completes by itself; its ranking reads the Livret', () {
    for (final n in pack.nodes.where((n) => n.type == NodeType.mission)) {
      expect(missionDetectors, contains(n.id));
    }
    final sort = decodeSort(
      pack.nodes.firstWhere((n) => n.id == 'lb.save-or-repay'),
      pack,
    );
    expect(
      [
        for (final i in sort.items)
          if (i.livret) i.id,
      ],
      ['livret'],
    );
  });

  test('every link of every bundled pack resolves across the islands', () {
    final packs = [
      pack,
      decodePack(File('assets/packs/actions-etf.json').readAsStringSync()),
    ];
    final terms = {for (final p in packs) ...p.glossary.keys};
    for (final p in packs) {
      for (final n in p.nodes) {
        expect(terms, containsAll(n.glossary), reason: n.id);
      }
      for (final t in p.glossary.values) {
        expect(terms, containsAll(t.related), reason: t.id);
      }
    }
    // And no term is held twice (contentcheck refuses it too).
    expect(packs.fold(0, (n, p) => n + p.glossary.length), terms.length);
  });

  test('its inflation curves are restated at INSEE prices', () {
    expect(pack.datasets['ds.cash-real-2016-m']!.prices, 'insee');
    expect(pack.datasets['ds.livret-a-real-2022-m']!.prices, 'insee');
    expect(pack.datasets['ds.cash-2016-m']!.prices, isNull);
  });
}
