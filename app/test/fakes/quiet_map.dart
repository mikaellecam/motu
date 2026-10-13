import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/learning/next_step_card.dart';
import 'package:finance_companion/application/learning/ui_level.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The map with nothing behind it, for tests that only pass through it: no
/// wallet on the island, no next step, level 1, an island without lessons.
final quietMap = <Override>[
  livingIslandProvider.overrideWith((ref) async => const []),
  nextStepViewProvider.overrideWith((ref) async => null),
  currentUiLevelProvider.overrideWith((ref) async => 1),
  islandPathProvider(actionsEtfIsland).overrideWith(
    (ref) async =>
        const IslandPathView(Localized('Actions & ETF', 'Stocks & ETFs'), []),
  ),
];
