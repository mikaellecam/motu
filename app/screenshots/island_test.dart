import 'dart:io';

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/presentation/features/island/island_screen.dart';
import 'package:flutter/material.dart';

import 'map_test.dart' show island;
import 'screenshot.dart';

// The bundled Actions & ETF path for someone who did nodes 1 and 2: the
// mission « Ton premier ETF » is current and, missions not blocking, the
// lesson after it is open. The whole path, under the living island of the
// map's screenshot.

void main() {
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );
  screenshot(
    'm6-9-island-path',
    const IslandScreen(islandId: actionsEtfIsland),
    size: const Size(390, 1850),
    overrides: [
      island,
      contentPackProvider(actionsEtfIsland).overrideWith((ref) async => pack),
      lesBasesPack,
      completedNodesProvider.overrideWith(
        (ref) => Stream.value({'ae.livret-vs-etf', 'ae.fees-toy'}),
      ),
    ],
  );

  // Les bases after its first three lessons (M12-6): « Range ton matelas »
  // current, the island with its house and two courses of its lighthouse.
  final bases = decodePack(
    File('assets/packs/les-bases.json').readAsStringSync(),
  );
  screenshot(
    'm12-6-bases-path',
    const IslandScreen(islandId: lesBasesIsland),
    size: const Size(390, 1500),
    overrides: [
      contentPackProvider(lesBasesIsland).overrideWith((ref) async => bases),
      completedNodesProvider.overrideWith(
        (ref) => Stream.value({
          'lb.safety-cushion',
          'lb.cash-inflation',
          'lb.livret-inflation',
        }),
      ),
    ],
  );
}
