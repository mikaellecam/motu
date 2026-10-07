import 'dart:ui';

import 'package:finance_companion/presentation/features/map/iso.dart';
import 'package:flutter_test/flutter_test.dart';

const p = IsoProjection(tile: 64, unit: 32);

/// The corners of a polygon path, read back from its bounds and contains().
Rect bounds(Path path) => path.getBounds();

void main() {
  group('projection (2:1 isometric)', () {
    test('x runs down-right, y down-left, z up', () {
      expect(p.project(0, 0), Offset.zero);
      expect(p.project(1, 0), const Offset(32, 16));
      expect(p.project(0, 1), const Offset(-32, 16));
      expect(p.project(0, 0, 1), const Offset(0, -32));
      expect(p.project(2, 2, 1), const Offset(0, 32));
    });

    test('shifting moves the origin', () {
      expect(
        p.shifted(const Offset(10, 20)).project(1, 0),
        const Offset(42, 36),
      );
    });
  });

  test('a tile is a diamond twice as wide as tall', () {
    final facets = tileFacets(p, 0, 0);
    expect(facets.single.face, Face.top);
    expect(bounds(facets.single.path), const Rect.fromLTRB(-32, 0, 32, 32));
  });

  test('a box shows its left side, right side, then top', () {
    final facets = boxFacets(p, 0, 0, 1, 1, 1);
    expect(facets.map((f) => f.face), [Face.left, Face.right, Face.top]);
    // The top is the base tile lifted by one unit.
    expect(bounds(facets[2].path), const Rect.fromLTRB(-32, -32, 32, 0));
    // The sides reach down to the front corner of the base.
    expect(bounds(facets[0].path).bottom, 32);
    expect(bounds(facets[1].path).right, 32);
  });

  test('a roof meets at its apex, above the footprint centre', () {
    final facets = roofFacets(p, 0, 0, 1, 1, 1, z: 1);
    expect(facets.map((f) => f.face), [Face.left, Face.right]);
    final apex = p.project(0.5, 0.5, 2);
    for (final facet in facets) {
      expect(bounds(facet.path).top, apex.dy);
    }
  });

  test('a candle: body between the wicks, wicks to low and high', () {
    final c = candle(p, 0, 0, low: 0, high: 2);
    expect(c.body.map((f) => f.face), [Face.left, Face.right, Face.top]);
    expect(c.wick.first.$2, p.project(0, 0, 0));
    expect(c.wick.last.$2, p.project(0, 0, 2));
    // The body stops short of both ends.
    expect(bounds(c.body.last.path).top, greaterThan(p.project(0, 0, 2).dy));
  });

  test('a crystal shows four faces between its tips', () {
    final facets = crystalFacets(p, 0, 0, h: 2);
    expect(facets, hasLength(4));
    final all = facets
        .map((f) => bounds(f.path))
        .reduce((a, b) => a.expandToInclude(b));
    expect(all.top, p.project(0, 0, 2).dy);
    expect(all.bottom, p.project(0, 0).dy);
  });
}
