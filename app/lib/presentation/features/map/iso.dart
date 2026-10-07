import 'dart:ui';

/// 2:1 isometric projection: world x runs down-right, y down-left, z up.
/// A tile is [tile] wide and half as tall; one unit of height is [unit].
class IsoProjection {
  const IsoProjection({
    this.tile = 64,
    this.unit = 32,
    this.origin = Offset.zero,
  });

  final double tile;
  final double unit;

  /// Where world (0, 0, 0) lands on the canvas.
  final Offset origin;

  Offset project(double x, double y, [double z = 0]) =>
      origin + Offset((x - y) * tile / 2, (x + y) * tile / 4 - z * unit);

  IsoProjection shifted(Offset by) =>
      IsoProjection(tile: tile, unit: unit, origin: origin + by);
}

/// Which way a face looks; the painter shades by it. With the viewer at
/// +x +y, only the top, the +y face (left) and the +x face (right) show.
enum Face { top, left, right }

typedef Facet = ({Face face, Path path});

Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

/// The top of one ground tile.
List<Facet> tileFacets(IsoProjection p, double x, double y, {double z = 0}) => [
  (
    face: Face.top,
    path: _polygon([
      p.project(x, y, z),
      p.project(x + 1, y, z),
      p.project(x + 1, y + 1, z),
      p.project(x, y + 1, z),
    ]),
  ),
];

/// A box from (x, y, z) spanning [w] along x, [d] along y, [h] up: its two
/// visible sides, then its top, in painting order.
List<Facet> boxFacets(
  IsoProjection p,
  double x,
  double y,
  double w,
  double d,
  double h, {
  double z = 0,
}) => [
  (
    face: Face.left,
    path: _polygon([
      p.project(x, y + d, z),
      p.project(x + w, y + d, z),
      p.project(x + w, y + d, z + h),
      p.project(x, y + d, z + h),
    ]),
  ),
  (
    face: Face.right,
    path: _polygon([
      p.project(x + w, y, z),
      p.project(x + w, y + d, z),
      p.project(x + w, y + d, z + h),
      p.project(x + w, y, z + h),
    ]),
  ),
  (
    face: Face.top,
    path: _polygon([
      p.project(x, y, z + h),
      p.project(x + w, y, z + h),
      p.project(x + w, y + d, z + h),
      p.project(x, y + d, z + h),
    ]),
  ),
];

/// A pyramid roof over the footprint (x, y, w, d), its base at [z].
List<Facet> roofFacets(
  IsoProjection p,
  double x,
  double y,
  double w,
  double d,
  double h, {
  required double z,
}) {
  final apex = p.project(x + w / 2, y + d / 2, z + h);
  return [
    (
      face: Face.left,
      path: _polygon([
        p.project(x, y + d, z),
        p.project(x + w, y + d, z),
        apex,
      ]),
    ),
    (
      face: Face.right,
      path: _polygon([
        p.project(x + w, y, z),
        p.project(x + w, y + d, z),
        apex,
      ]),
    ),
  ];
}

/// A candlestick: a thin body from [low] to [high] (heights) with its wick,
/// centred on (x, y).
({List<Facet> body, List<(Offset, Offset)> wick}) candle(
  IsoProjection p,
  double x,
  double y, {
  required double low,
  required double high,
  double width = 0.3,
}) {
  final top = high - (high - low) * 0.2;
  final bottom = low + (high - low) * 0.2;
  return (
    body: boxFacets(
      p,
      x - width / 2,
      y - width / 2,
      width,
      width,
      top - bottom,
      z: bottom,
    ),
    wick: [
      (p.project(x, y, bottom), p.project(x, y, low)),
      (p.project(x, y, top), p.project(x, y, high)),
    ],
  );
}

/// A crystal (two pyramids base to base) centred on (x, y), from [z] up to
/// [z] + [h]: its four faces towards the viewer.
List<Facet> crystalFacets(
  IsoProjection p,
  double x,
  double y, {
  double r = 0.35,
  double h = 1.4,
  double z = 0,
}) {
  final mid = z + h / 2;
  final top = p.project(x, y, z + h);
  final bottom = p.project(x, y, z);
  final front = p.project(x + r, y + r, mid);
  final left = p.project(x - r, y + r, mid);
  final right = p.project(x + r, y - r, mid);
  return [
    (face: Face.left, path: _polygon([bottom, left, front])),
    (face: Face.right, path: _polygon([bottom, front, right])),
    (face: Face.left, path: _polygon([top, left, front])),
    (face: Face.top, path: _polygon([top, front, right])),
  ];
}
