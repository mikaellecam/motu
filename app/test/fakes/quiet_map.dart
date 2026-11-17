import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/learning/ui_level.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The « Archipel » tab with nothing behind it, for tests that only pass
/// through it (M13-6): level 1, islands without lessons, no
/// completion watched, a bare port.
final quietMap = <Override>[
  completedNodesProvider.overrideWith((ref) => Stream.value(const {})),
  portViewProvider.overrideWith(
    (ref) async => const PortView(completed: {}, skipped: false, lines: {}),
  ),
  currentUiLevelProvider.overrideWith((ref) async => 1),
  islandPathProvider(actionsEtfIsland).overrideWith(
    (ref) async =>
        const IslandPathView(Localized('Actions & ETF', 'Stocks & ETFs'), []),
  ),
  islandPathProvider(lesBasesIsland).overrideWith(
    (ref) async =>
        const IslandPathView(Localized('Les bases', 'Foundations'), []),
  ),
];
