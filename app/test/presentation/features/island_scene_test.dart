import 'package:finance_companion/presentation/features/island/island_scene.dart';
import 'package:finance_companion/presentation/features/map/district.dart';
import 'package:finance_companion/presentation/features/map/port.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('markers stand on what their lessons grow', () {
    test('a marker per building, on its top, plain or grown', () {
      final plain = districtWorld(List.filled(12, 0), ferry: true);
      final grown = districtWorld(List.filled(12, 1), ferry: true);
      expect(plain.anchors, hasLength(12));
      // A height unit of the district up close, in px.
      const unit = 120 * 18 / 34;
      for (final (i, b) in districtBuildings.indexed) {
        expect(grown.anchors[i].dx, plain.anchors[i].dx, reason: b.nodeId);
        expect(
          plain.anchors[i].dy - grown.anchors[i].dy,
          closeTo((b.top - b.low) * unit, 1e-6),
          reason: b.nodeId,
        );
      }
      // Half grown, half way up.
      final half = districtWorld(List.filled(12, 0.5), ferry: true);
      expect(
        half.anchors[11].dy,
        closeTo((plain.anchors[11].dy + grown.anchors[11].dy) / 2, 1e-6),
      );
    });

    test('each building at its own place, the spire behind the bank', () {
      final world = districtWorld(List.filled(12, 0), ferry: false);
      expect(world.anchors.toSet(), hasLength(12));
      // Further back on the grid is higher on screen.
      expect(world.anchors[11].dy, lessThan(world.anchors[0].dy));
    });

    test('at the port, on the part once built, on its spot before', () {
      final bare = portWorld(List.filled(9, false), lines: const {});
      final built = portWorld(List.filled(9, true), lines: const {});
      expect(bare.anchors, hasLength(9));
      for (final (i, p) in portParts.indexed) {
        expect(
          built.anchors[i].dy,
          lessThan(bare.anchors[i].dy),
          reason: p.nodeId,
        );
      }
      expect(built.grown, List.filled(9, 1.0));
    });

    test('a short list draws the rest plain', () {
      final world = districtWorld(const [1], ferry: true);
      expect(world.anchors, hasLength(12));
    });
  });
}
