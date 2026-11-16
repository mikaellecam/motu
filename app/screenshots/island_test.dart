import 'dart:io';

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/presentation/features/island/island_screen.dart';

import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// The islands up close (M13-4): Actions & ETF after its first six lessons,
// framed on the seventh, the square; Les bases after five, framed on the
// crane's empty spot.

void main() {
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );
  screenshot(
    'm6-9-island-path',
    const IslandScreen(islandId: actionsEtfIsland),
    overrides: [
      contentPackProvider(actionsEtfIsland).overrideWith((ref) async => pack),
      lesBasesPack,
      completedNodesProvider.overrideWith(
        (ref) => Stream.value({
          for (final n in pack.nodes.take(6)) n.id,
          'lb.cushion-2020',
        }),
      ),
    ],
  );

  final bases = decodePack(
    File('assets/packs/les-bases.json').readAsStringSync(),
  );
  screenshot(
    'm12-6-bases-path',
    const IslandScreen(islandId: lesBasesIsland),
    overrides: [
      lesBasesPack,
      completedNodesProvider.overrideWith(
        (ref) => Stream.value({for (final n in bases.nodes.take(5)) n.id}),
      ),
    ],
  );

  // The sea chart from the port (M13-5): Actions & ETF open at 6/12, the
  // others closed.
  screenshot(
    'm13-5-sea-chart',
    const IslandScreen(islandId: lesBasesIsland),
    overrides: [
      lesBasesPack,
      contentPackProvider(actionsEtfIsland).overrideWith((ref) async => pack),
      completedNodesProvider.overrideWith(
        (ref) => Stream.value({
          for (final n in bases.nodes.take(5)) n.id,
          for (final n in pack.nodes.take(6)) n.id,
        }),
      ),
    ],
    act: (tester) => tester.tap(find.text('Naviguer')),
  );
}
