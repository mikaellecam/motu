import 'dart:ui';

import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:finance_companion/presentation/features/map/living_island.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tiles are sea or a known ground, on rows of one width', () {
    for (final island in archipelago) {
      final width = island.tiles.first.length;
      for (final row in island.tiles) {
        expect(row.length, width, reason: '${island.id}');
        expect(
          row.split('').every('.SgG'.contains),
          isTrue,
          reason: '${island.id}: $row',
        );
      }
    }
  });

  const b1 = DrawnBuilding(height: 1, built: 1, ghost: 0);
  const b2 = DrawnBuilding(height: 2, built: 1, ghost: 0);
  const b3 = DrawnBuilding(height: 2, built: 0.5, ghost: 1);

  test('the painter draws a wallet\'s island, buildings and ghosts, and '
      'the district, without '
      'error', () {
    for (final buildings in [
      const <DrawnBuilding>[],
      const [
        DrawnBuilding(height: 4, built: 1, ghost: 0),
        DrawnBuilding(height: 2.5, built: 0.6, ghost: 1),
        DrawnBuilding(height: 0, built: 1, ghost: 0),
        DrawnBuilding(height: 1, built: 0, ghost: 0.5),
        b1,
        b2,
      ],
    ]) {
      final recorder = PictureRecorder();
      ArchipelagoPainter(
        only: archipelago.single,
        buildings: buildings,
      ).paint(Canvas(recorder), const Size(390, 300));
      expect(recorder.endRecording(), isNotNull);
    }
    final recorder = PictureRecorder();
    ArchipelagoPainter(
      only: archipelago.single,
      lessonsDone: const {'ae.livret-vs-etf'},
    ).paint(Canvas(recorder), const Size(390, 300));
    expect(recorder.endRecording(), isNotNull);
  });

  test('where each building stands, for taps: left to right, the largest '
      'last; a strip per spot, from its roof to its foot', () {
    final island = archipelago.firstWhere((i) => i.id == IslandId.actionsEtf);
    const tall = DrawnBuilding(height: 4, built: 1, ghost: 0);
    const short = DrawnBuilding(height: 1, built: 0, ghost: 1);
    final rects = ArchipelagoPainter.buildingRects(island, [tall, short]);
    expect(rects, hasLength(2));
    final (largest, second) = (rects[0], rects[1]);
    // Neighbours: the second spot just left of the largest's, touching it.
    expect(second.right, closeTo(largest.left, 1e-9));
    expect(largest.width, closeTo(second.width, 1e-9));
    // A taller building reaches higher; both rest on the ground.
    expect(largest.top, lessThan(second.top - 2 * island.unit));
    expect(largest.height, greaterThan(4 * island.unit));
    // A ghost counts at its full height: what will stand.
    expect(second.height, greaterThan(island.unit));
    // No more than the island's five spots.
    expect(
      ArchipelagoPainter.buildingRects(island, List.filled(7, tall)),
      hasLength(5),
    );
    expect(ArchipelagoPainter.buildingRects(island, const []), isEmpty);
  });

  test('one building alone, as on the island: each rank, built, rising or '
      'a ghost on its slab (M11-6)', () {
    for (final rank in [0, 1, 2, 3, 4]) {
      for (final b in const [
        DrawnBuilding(height: 4, built: 1, ghost: 0),
        DrawnBuilding(height: 2, built: 0.5, ghost: 1),
        DrawnBuilding(height: 1, built: 0, ghost: 1),
      ]) {
        final recorder = PictureRecorder();
        BuildingPortraitPainter(
          b,
          rank: rank,
        ).paint(Canvas(recorder), BuildingPortraitPainter.size);
        expect(recorder.endRecording(), isNotNull);
      }
    }
    const b = DrawnBuilding(height: 2, built: 1, ghost: 0);
    final painter = BuildingPortraitPainter(b, rank: 1);
    expect(painter.shouldRepaint(BuildingPortraitPainter(b, rank: 1)), isFalse);
    expect(painter.shouldRepaint(BuildingPortraitPainter(b, rank: 0)), isTrue);
    expect(
      painter.shouldRepaint(
        BuildingPortraitPainter(
          const DrawnBuilding(height: 3, built: 1, ghost: 0),
          rank: 1,
        ),
      ),
      isTrue,
    );
  });

  test('repaints when the buildings change, not otherwise', () {
    final a = ArchipelagoPainter(
      only: archipelago.single,
      buildings: const [b1, b2],
    );
    expect(
      a.shouldRepaint(
        ArchipelagoPainter(only: archipelago.single, buildings: const [b1, b2]),
      ),
      isFalse,
    );
    expect(
      a.shouldRepaint(
        ArchipelagoPainter(only: archipelago.single, buildings: const [b1, b3]),
      ),
      isTrue,
    );
    expect(
      a.shouldRepaint(
        ArchipelagoPainter(only: archipelago.single, buildings: const [b1]),
      ),
      isTrue,
    );
  });
}
