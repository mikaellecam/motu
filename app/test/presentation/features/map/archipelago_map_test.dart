import 'package:decimal/decimal.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';
import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:finance_companion/presentation/features/map/archipelago_map.dart';
import 'package:finance_companion/presentation/features/map/living_island.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers.dart';

void main() {
  Future<List<IslandId>> pumpMap(WidgetTester tester) async {
    final opened = <IslandId>[];
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, ArchipelagoMap(onOpen: opened.add));
    return opened;
  }

  testWidgets('five labelled islands, four of them coming soon', (
    tester,
  ) async {
    await pumpMap(tester);
    for (final name in [
      'Actions & ETF',
      'Trading',
      'Immobilier',
      'Crypto',
      'Les bases',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Bientôt'), findsNWidgets(4));
  });

  testWidgets('Actions & ETF opens; locked islands do nothing', (tester) async {
    final opened = await pumpMap(tester);
    await tester.tap(find.text('Actions & ETF'));
    await tester.tap(find.text('Trading'), warnIfMissed: false);
    expect(opened, [IslandId.actionsEtf]);
  });

  testWidgets('screen readers hear each island, and which ones are not open', (
    tester,
  ) async {
    await pumpMap(tester);
    expect(find.bySemanticsLabel('Actions & ETF'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Actions & ETF')),
      matchesSemantics(
        label: 'Actions & ETF',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Trading, bientôt')),
      matchesSemantics(label: 'Trading, bientôt'),
    );
  });

  testWidgets('labels are comfortable tap targets', (tester) async {
    await pumpMap(tester);
    // Measured on screen, at the opening zoom: the smallest the map allows.
    for (final name in ['Actions & ETF', 'Trading']) {
      final target = find
          .ancestor(of: find.text(name), matching: find.byType(GestureDetector))
          .first;
      expect(
        tester.getRect(target).height,
        greaterThanOrEqualTo(44),
        reason: name,
      );
    }
  });

  testWidgets('pan and zoom within bounds', (tester) async {
    await pumpMap(tester);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.minScale, 0.75);
    expect(viewer.maxScale, 2.5);
    expect(viewer.panEnabled, isTrue);
    expect(viewer.scaleEnabled, isTrue);
  });

  group('the living island (M7-2)', () {
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

    /// The map, its buildings in [island]; the painter on each frame.
    Future<List<DrawnBuilding> Function()> pumpIsland(
      WidgetTester tester,
      ValueNotifier<List<IslandBuilding>> island, {
      bool reducedMotion = false,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpApp(
        tester,
        MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: ValueListenableBuilder(
            valueListenable: island,
            builder: (_, buildings, _) =>
                ArchipelagoMap(onOpen: (_) {}, buildings: buildings),
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
      final island = ValueNotifier<List<IslandBuilding>>(const []);
      final drawn = await pumpIsland(tester, island);
      expect(drawn(), isEmpty);

      island.value = [world, apple];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final [growing, site] = drawn();
      expect(growing.height, inExclusiveRange(0, maxBuildingHeight));
      expect(site.scaffold, 1, reason: 'a pending buy: its frame goes up');

      await tester.pumpAndSettle();
      expect(drawn(), drawnBuildings([world, apple]));
    });

    testWidgets('a buy that fills completes its building', (tester) async {
      final island = ValueNotifier([world, apple]);
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
      expect(drawn()[1].scaffold, 0);
    });

    testWidgets('with animations off, the island changes at once', (
      tester,
    ) async {
      final island = ValueNotifier<List<IslandBuilding>>(const []);
      final drawn = await pumpIsland(tester, island, reducedMotion: true);
      island.value = [world];
      await tester.pump();
      expect(drawn(), drawnBuildings([world]));
    });
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await pumpMap(tester);
    await expectAccessible(tester);
  });
}
