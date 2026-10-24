import 'package:decimal/decimal.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';
import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:finance_companion/presentation/features/map/archipelago_map.dart';
import 'package:finance_companion/presentation/features/map/living_island.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers.dart';

void main() {
  Future<List<IslandId>> pumpMap(
    WidgetTester tester, {
    ({int done, int total})? progress,
  }) async {
    final opened = <IslandId>[];
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      ArchipelagoMap(onOpen: opened.add, progress: progress),
    );
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
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
  });

  testWidgets('it opens on all five islands, above the next-step card', (
    tester,
  ) async {
    await pumpMap(tester);
    // The card covers the bottom 200 px of the 844 px screen.
    const free = Rect.fromLTRB(0, 0, 390, 844 - 200);
    for (final name in [
      'Actions & ETF',
      'Trading',
      'Immobilier',
      'Crypto',
      'Les bases',
    ]) {
      final label = tester.getRect(find.text(name));
      expect(free.contains(label.topLeft), isTrue, reason: name);
      expect(free.contains(label.bottomRight), isTrue, reason: name);
    }
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

  testWidgets('Actions & ETF shows its lessons done, to the eye and the ear', (
    tester,
  ) async {
    await pumpMap(tester, progress: (done: 2, total: 12));
    expect(find.text('2/12'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Actions & ETF, 2 sur 12 terminées'),
      findsOneWidget,
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
    // The opening view, all five islands, is the smallest.
    expect(viewer.minScale, 1);
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

  group('the lessons green the island (M9-19)', () {
    /// The map, its lessons done in [lessons]; how green the painter is.
    Future<double Function()> pumpLessons(
      WidgetTester tester,
      ValueNotifier<({int done, int total})?> lessons, {
      bool reducedMotion = false,
    }) async {
      await pumpApp(
        tester,
        MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: ValueListenableBuilder(
            valueListenable: lessons,
            builder: (_, progress, _) =>
                ArchipelagoMap(onOpen: (_) {}, progress: progress),
          ),
        ),
      );
      return () => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<ArchipelagoPainter>()
          .single
          .grown;
    }

    testWidgets('a lesson done greens it a step further, easing in', (
      tester,
    ) async {
      final lessons = ValueNotifier<({int done, int total})?>((
        done: 2,
        total: 12,
      ));
      final grown = await pumpLessons(tester, lessons);
      expect(grown(), 2 / 12);

      lessons.value = (done: 3, total: 12);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(grown(), inExclusiveRange(2 / 12, 3 / 12));
      await tester.pumpAndSettle();
      expect(grown(), closeTo(3 / 12, 1e-9));
    });

    testWidgets('lessons known at last: no greening back from the full art', (
      tester,
    ) async {
      final lessons = ValueNotifier<({int done, int total})?>(null);
      final grown = await pumpLessons(tester, lessons);
      expect(grown(), 1);

      lessons.value = (done: 2, total: 12);
      await tester.pump();
      expect(grown(), 2 / 12);
    });

    testWidgets('with animations off, it greens at once', (tester) async {
      final lessons = ValueNotifier<({int done, int total})?>((
        done: 2,
        total: 12,
      ));
      final grown = await pumpLessons(tester, lessons, reducedMotion: true);
      lessons.value = (done: 3, total: 12);
      await tester.pump();
      expect(grown(), 3 / 12);
    });
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await pumpMap(tester);
    await expectAccessible(tester);
  });
}
