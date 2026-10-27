import 'dart:io';

import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled Actions & ETF pack (M6-8): every lesson plays. What its copy
/// says happened is checked against the real prices in
/// actions_etf_copy_test.dart.
void main() {
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );

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
        case NodeType.checkpoint:
          decodeCheckpoint(node, pack);
        case NodeType.mission:
          decodeMission(node, pack);
      }
    }
    expect(pack.glossary, hasLength(26));
  });
}
