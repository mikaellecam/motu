import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/learning/next_step_card.dart';
import 'package:finance_companion/application/learning/ui_level.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/next_step.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';

import 'screenshot.dart';

// The living island (M7-2): a live wallet holding the world ETF, Apple, ASML
// and Coca-Cola, with a buy of Nvidia waiting for the market to open. The
// next step (M7-3): the fees toy, at level 2.

final island = livingIslandProvider.overrideWith(
  (ref) async => islandBuildings(
    held: {
      'world': Decimal.fromInt(16820),
      'apple': Decimal.fromInt(4041),
      'asml': Decimal.fromInt(2357),
      'coca-cola': Decimal.fromInt(1783),
    },
    pending: {'nvidia': Decimal.fromInt(8000)},
  ),
);

void main() {
  screenshotRoute(
    'm7-1-map',
    '/',
    overrides: [
      livingIslandProvider.overrideWith((ref) async => const []),
      nextStepViewProvider.overrideWith((ref) async => null),
      currentUiLevelProvider.overrideWith((ref) async => 1),
    ],
  );

  screenshotRoute(
    'm7-2-living-island',
    '/',
    overrides: [
      island,
      nextStepViewProvider.overrideWith((ref) async => null),
      currentUiLevelProvider.overrideWith((ref) async => 2),
    ],
  );

  screenshotRoute(
    'm7-3-next-step',
    '/',
    overrides: [
      island,
      nextStepViewProvider.overrideWith(
        (ref) async => const NextStepView(
          PlayNode('lb.cash-inflation'),
          title: Localized(
            '10 000 € sous le matelas',
            '€10,000 under the mattress',
          ),
        ),
      ),
      currentUiLevelProvider.overrideWith((ref) async => 2),
    ],
  );
}
