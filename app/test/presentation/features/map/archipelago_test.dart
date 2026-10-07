import 'dart:ui';

import 'package:finance_companion/presentation/features/map/archipelago.dart';
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

  test('the painter draws every island without error', () {
    final recorder = PictureRecorder();
    ArchipelagoPainter(
      geometry,
      buildingHeights: const [1, 2, 0, 3],
    ).paint(Canvas(recorder), geometry.size);
    expect(recorder.endRecording(), isNotNull);
  });

  test('repaints when the buildings change, not otherwise', () {
    final a = ArchipelagoPainter(geometry, buildingHeights: const [1, 2]);
    expect(
      a.shouldRepaint(
        ArchipelagoPainter(geometry, buildingHeights: const [1, 2]),
      ),
      isFalse,
    );
    expect(
      a.shouldRepaint(
        ArchipelagoPainter(geometry, buildingHeights: const [1, 3]),
      ),
      isTrue,
    );
    expect(
      a.shouldRepaint(ArchipelagoPainter(geometry, buildingHeights: const [1])),
      isTrue,
    );
    expect(
      a.shouldRepaint(
        ArchipelagoPainter(
          ArchipelagoGeometry(tile: 32),
          buildingHeights: const [1, 2],
        ),
      ),
      isTrue,
    );
  });
}
