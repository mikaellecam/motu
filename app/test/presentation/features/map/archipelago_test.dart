import 'dart:ui';

import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:finance_companion/presentation/features/map/living_island.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final geometry = ArchipelagoGeometry();

  test('five islands, only Actions & ETF playable', () {
    expect(archipelago.map((i) => i.id), unorderedEquals(IslandId.values));
    expect(archipelago.where((i) => !i.locked).map((i) => i.id), [
      IslandId.actionsEtf,
    ]);
  });

  test('every island and its label fit on the canvas', () {
    final canvas = Offset.zero & geometry.size;
    for (final island in archipelago) {
      expect(
        canvas.contains(geometry.centre(island)),
        isTrue,
        reason: '${island.id}',
      );
      expect(
        canvas.contains(geometry.labelAnchor(island)),
        isTrue,
        reason: '${island.id}',
      );
    }
  });

  const b1 = DrawnBuilding(height: 1, built: 1, scaffold: 0);
  const b2 = DrawnBuilding(height: 2, built: 1, scaffold: 0);
  const b3 = DrawnBuilding(height: 2, built: 0.5, scaffold: 1);

  test('the painter draws every island, buildings and scaffolds, without '
      'error', () {
    final recorder = PictureRecorder();
    ArchipelagoPainter(
      geometry,
      buildings: const [
        DrawnBuilding(height: 2.5, built: 1, scaffold: 0),
        DrawnBuilding(height: 1.5, built: 0.6, scaffold: 1),
        DrawnBuilding(height: 0, built: 1, scaffold: 0),
        DrawnBuilding(height: 1, built: 0, scaffold: 0.5),
      ],
    ).paint(Canvas(recorder), geometry.size);
    expect(recorder.endRecording(), isNotNull);
  });

  test('repaints when the buildings change, not otherwise', () {
    final a = ArchipelagoPainter(geometry, buildings: const [b1, b2]);
    expect(
      a.shouldRepaint(ArchipelagoPainter(geometry, buildings: const [b1, b2])),
      isFalse,
    );
    expect(
      a.shouldRepaint(ArchipelagoPainter(geometry, buildings: const [b1, b3])),
      isTrue,
    );
    expect(
      a.shouldRepaint(ArchipelagoPainter(geometry, buildings: const [b1])),
      isTrue,
    );
    expect(
      a.shouldRepaint(
        ArchipelagoPainter(
          ArchipelagoGeometry(tile: 32),
          buildings: const [b1, b2],
        ),
      ),
      isTrue,
    );
  });
}
