import 'package:decimal/decimal.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';
import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:finance_companion/presentation/features/map/living_island.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers.dart';

void main() {
  group('a wallet\'s island follows its positions (M7-2, M13-1)', () {
    final world = IslandBuilding(
      'world',
      height: Decimal.one,
      built: Decimal.one,
    );
    final apple = IslandBuilding(
      'apple',
      height: Decimal.parse('0.5'),
      built: Decimal.zero,
    );

    /// A wallet's island, its buildings in [island]; the painter on each
    /// frame.
    Future<List<DrawnBuilding> Function()> pumpIsland(
      WidgetTester tester,
      ValueNotifier<List<IslandBuilding>?> island, {
      bool reducedMotion = false,
    }) async {
      await pumpApp(
        tester,
        MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: ValueListenableBuilder(
            valueListenable: island,
            builder: (_, buildings, _) => StagedIsland(
              buildings: buildings,
              builder: (_, frame) => CustomPaint(
                painter: ArchipelagoPainter(
                  only: archipelago.single,
                  buildings: frame,
                ),
              ),
            ),
          ),
        ),
      );
      return () => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<ArchipelagoPainter>()
          .single
          .buildings;
    }

    testWidgets('buildings grow when positions arrive, in stages', (
      tester,
    ) async {
      final island = ValueNotifier<List<IslandBuilding>?>(const []);
      final drawn = await pumpIsland(tester, island);
      expect(drawn(), isEmpty);

      island.value = [world, apple];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final [growing, site] = drawn();
      expect(growing.height, inExclusiveRange(0, maxBuildingHeight));
      expect(site.ghost, 1, reason: 'a pending buy: its ghost shows');

      await tester.pumpAndSettle();
      expect(drawn(), drawnBuildings([world, apple]));
    });

    testWidgets('a buy that fills completes its building', (tester) async {
      final island = ValueNotifier<List<IslandBuilding>?>([world, apple]);
      final drawn = await pumpIsland(tester, island);
      final filled = IslandBuilding(
        'apple',
        height: Decimal.parse('0.5'),
        built: Decimal.one,
      );

      island.value = [world, filled];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 840));
      expect(drawn()[1].built, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(drawn()[1], drawnBuildings([filled]).single);
      expect(drawn()[1].ghost, 0);
    });

    testWidgets('known at last (it was loading): it stands at once', (
      tester,
    ) async {
      final island = ValueNotifier<List<IslandBuilding>?>(null);
      final drawn = await pumpIsland(tester, island);
      expect(drawn(), isEmpty);
      island.value = [world, apple];
      await tester.pump();
      expect(drawn(), drawnBuildings([world, apple]));
    });

    testWidgets('with animations off, the island changes at once', (
      tester,
    ) async {
      final island = ValueNotifier<List<IslandBuilding>?>(const []);
      final drawn = await pumpIsland(tester, island, reducedMotion: true);
      island.value = [world];
      await tester.pump();
      expect(drawn(), drawnBuildings([world]));
    });
  });
}
