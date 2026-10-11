import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';

import 'screenshot.dart';

// The living island (M7-2): a live wallet holding the world ETF, Apple, ASML
// and Coca-Cola, with a buy of Nvidia waiting for the market to open.

void main() {
  screenshotRoute('m7-1-map', '/');

  screenshotRoute(
    'm7-2-living-island',
    '/',
    overrides: [
      livingIslandProvider.overrideWith(
        (ref) async => islandBuildings(
          held: {
            'world': Decimal.fromInt(16820),
            'apple': Decimal.fromInt(4041),
            'asml': Decimal.fromInt(2357),
            'coca-cola': Decimal.fromInt(1783),
          },
          pending: {'nvidia': Decimal.fromInt(8000)},
        ),
      ),
    ],
  );
}
