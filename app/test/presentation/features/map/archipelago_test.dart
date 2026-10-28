import 'dart:ui';

import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:finance_companion/presentation/features/map/living_island.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('five islands, only Actions & ETF playable', () {
    expect(archipelago.map((i) => i.id), unorderedEquals(IslandId.values));
    expect(archipelago.where((i) => !i.locked).map((i) => i.id), [
      IslandId.actionsEtf,
    ]);
  });

  test('every island, its shallows and its label lie on the map', () {
    final map = Offset.zero & mapSize;
    for (final island in archipelago) {
      final halo = island.halo.shift(-mapBounds.topLeft);
      expect(map.contains(halo.topLeft), isTrue, reason: '${island.id}');
      expect(map.contains(halo.bottomRight), isTrue, reason: '${island.id}');
      expect(map.contains(island.labelAnchor), isTrue, reason: '${island.id}');
    }
  });

  test('tiles are sea or a known ground, on rows of one width', () {
    for (final island in archipelago) {
      final width = island.tiles.first.length;
      for (final row in island.tiles) {
        expect(row.length, width, reason: '${island.id}');
        expect(
          row.split('').every('.SgGabc'.contains),
          isTrue,
          reason: '${island.id}: $row',
        );
      }
      // Sand and grass are Actions & ETF's; stone is the others'.
      final ground = island.tiles.join().replaceAll('.', '');
      expect(
        ground
            .split('')
            .every((c) => (island.locked ? 'abc' : 'SgG').contains(c)),
        isTrue,
        reason: '${island.id}',
      );
    }
  });

  test('back to front: each island is drawn after the ones behind it', () {
    final rows = [for (final i in archipelago) i.origin.dy];
    expect(rows, [...rows]..sort());
  });

  const b1 = DrawnBuilding(height: 1, built: 1, ghost: 0);
  const b2 = DrawnBuilding(height: 2, built: 1, ghost: 0);
  const b3 = DrawnBuilding(height: 2, built: 0.5, ghost: 1);

  test('the painter draws every island, buildings and ghosts, without '
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
      ArchipelagoPainter(buildings: buildings).paint(Canvas(recorder), mapSize);
      expect(recorder.endRecording(), isNotNull);
    }
  });

  test('repaints when the buildings change, not otherwise', () {
    final a = ArchipelagoPainter(buildings: const [b1, b2]);
    expect(
      a.shouldRepaint(ArchipelagoPainter(buildings: const [b1, b2])),
      isFalse,
    );
    expect(
      a.shouldRepaint(ArchipelagoPainter(buildings: const [b1, b3])),
      isTrue,
    );
    expect(a.shouldRepaint(ArchipelagoPainter(buildings: const [b1])), isTrue);
  });
}
