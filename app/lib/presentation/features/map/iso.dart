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

/// A gable roof over the footprint (x, y, w, d), its base at [z], its ridge
/// [h] above, running along x: the back slope, the front slope, then the
/// gable end facing +x.
List<Facet> gableFacets(
  IsoProjection p,
  double x,
  double y,
  double w,
  double d,
  double h, {
  required double z,
}) {
  final ridgeBack = p.project(x, y + d / 2, z + h);
  final ridgeFront = p.project(x + w, y + d / 2, z + h);
  return [
    (
      face: Face.top,
      path: _polygon([
        p.project(x, y, z),
        p.project(x + w, y, z),
        ridgeFront,
        ridgeBack,
      ]),
    ),
    (
      face: Face.left,
      path: _polygon([
        p.project(x, y + d, z),
        p.project(x + w, y + d, z),
        ridgeFront,
        ridgeBack,
      ]),
    ),
    (
      face: Face.right,
      path: _polygon([
        p.project(x + w, y, z),
        p.project(x + w, y + d, z),
        ridgeFront,
      ]),
    ),
  ];
}

/// A candlestick standing on (x, y): a wick from the ground up to its body,
/// the body from [bodyLow] to [bodyHigh], a wick on to [high].
({(Offset, Offset) lowerWick, List<Facet> body, (Offset, Offset) upperWick})
candle(
  IsoProjection p,
  double x,
  double y, {
  required double bodyLow,
  required double bodyHigh,
  required double high,
  double width = 0.34,
}) => (
  lowerWick: (p.project(x, y), p.project(x, y, bodyLow)),
  body: boxFacets(
    p,
    x - width / 2,
    y - width / 2,
    width,
    width,
    bodyHigh - bodyLow,
    z: bodyLow,
  ),
  upperWick: (p.project(x, y, bodyHigh), p.project(x, y, high)),
);

/// A crystal standing on its tip at (x, y): two pyramids base to base, their
/// ring of radius [r] on the axes at [mid], the top tip at [h]. Its six faces
/// towards the viewer: the lower three right to left, then the upper three.
List<Path> crystalPaths(
  IsoProjection p,
  double x,
  double y, {
  required double r,
  required double mid,
  required double h,
}) {
  final bottom = p.project(x, y);
  final top = p.project(x, y, h);
  final back = p.project(x, y - r, mid);
  final right = p.project(x + r, y, mid);
  final front = p.project(x, y + r, mid);
  final left = p.project(x - r, y, mid);
  return [
    for (final tip in [bottom, top]) ...[
      _polygon([tip, back, right]),
      _polygon([tip, right, front]),
      _polygon([tip, front, left]),
    ],
  ];
}
