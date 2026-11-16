import 'package:flutter/rendering.dart';

import '../../../core/theme/tokens.dart';
import 'archipelago.dart';
import 'iso.dart';

// Actions & ETF as a New York style business district (BRIEF §4.2, M13-2):
// a street grid, every block standing from the start. Each lesson has its
// building, plain and low until the lesson is done, then grown, it alone.
// The blocks that are no lesson's never change.

/// A lesson's building: the node it grows with, where it stands on the
/// island's grid (a block's centre), and how it is drawn.
final class DistrictBuilding {
  const DistrictBuilding(
    this.nodeId,
    this.x,
    this.y,
    this._draw, {
    required this.top,
    this.low = 0.8,
  });

  final String nodeId;
  final double x, y;

  /// Its top grown, and plain: where its marker stands (M13-4).
  final double top, low;

  /// Its marker's point at [t] (0 plain, 1 grown): on its top, in the
  /// island's grid.
  ({double x, double y, double z}) anchor(double t) =>
      (x: x, y: y, z: low + (top - low) * t.clamp(0.0, 1.0));
  final void Function(IsoInk ink, double x, double y, {required double t})
  _draw;
}

/// The twelve, in the order of Actions & ETF's lessons (BRIEF §4.3).
const districtBuildings = [
  DistrictBuilding('ae.livret-vs-etf', 1.5, 5.5, _bank, top: 1.2),
  DistrictBuilding('ae.fees-toy', 0.5, 4.5, _tollBridge, top: 1.9, low: 0.5),
  DistrictBuilding('ae.mission-first-etf', 2.5, 5.5, _store, top: 1.3),
  DistrictBuilding(
    'ae.apple-vs-world-2022',
    3.5,
    5.5,
    _loneTower,
    top: 3.8,
    low: 1.3,
  ),
  DistrictBuilding('ae.march-2020', 5.5, 5.5, _wharf, top: 0.6, low: 0.4),
  DistrictBuilding('ae.risk-ladder', 4.5, 4.5, _fourTowers, top: 2.7, low: 1.0),
  DistrictBuilding('ae.compound-toy', 3.5, 4.5, _square, top: 1.6),
  DistrictBuilding(
    'ae.mission-three-regions',
    6.5,
    3.5,
    _harbour,
    top: 1.3,
    low: 0.5,
  ),
  DistrictBuilding('ae.dollar-trap', 4.5, 3.5, _exchange, top: 2.3),
  DistrictBuilding('ae.calm-portfolio', 2.5, 3.5, _roofGarden, top: 1.8),
  DistrictBuilding('ae.mission-dca', 3.5, 2.5, _clockTower, top: 3.4),
  DistrictBuilding('ae.checkpoint-1', 2.5, 2.5, _spire, top: 5.6, low: 0.9),
];

/// Which of [districtBuildings] stand grown: those whose lesson is in
/// [done], in any order. Ids that are no building's change nothing.
List<bool> districtGrown(Set<String> done) => [
  for (final b in districtBuildings) done.contains(b.nodeId),
];

/// The blocks round the lessons: where each stands and its kind (a row of
/// brownstones, a brick mid-rise, a limestone mid-rise).
const _fillers = [
  (3.5, 3.5, 1), (2.5, 4.5, 0), (1.5, 4.5, 2), (4.5, 5.5, 0), //
  (1.5, 3.5, 1), (4.5, 2.5, 2), (5.5, 4.5, 0), (5.5, 3.5, 1),
  (1.5, 2.5, 0), (2.5, 1.5, 2), (3.5, 1.5, 1), (1.5, 6.5, 0),
];

/// How a plain building stands against a grown one, and the blocks round
/// them.
const _plain = 0.35;
const _around = 0.7;

/// Zoomed in (a tile of 60 px or more), the drawing gets finer: windows,
/// lane lines, quay courses, sea-wall strata.
bool districtDetailed(IsoProjection p) => p.tile >= 60;

/// Paints the district on [tiles] (as `IslandLayout.tiles`: `S` the
/// promenade round it, any other land a block), each building [grown] from 0
/// (plain) to 1 (as [districtGrown] says once its lesson is done), the
/// [ghosts] (their lessons unlocked, not done) under the ghost of themselves
/// grown
/// gives it, its ferry pier on the mainland side, the ferry at its end when
/// [ferry].
void paintDistrict(
  BlockPen pen,
  IsoProjection p,
  List<String> tiles, {
  required List<double> grown,
  required bool ferry,
  Set<int> ghosts = const {},
}) {
  final ink = IsoInk(pen, p);
  final ghost = IsoInk(GhostPen(pen.canvas), p);
  _ground(ink, tiles);
  // Back to front: what stands further back is painted first.
  final things = <(double, VoidCallback)>[
    (5.0, () => _pier(ink, ferry: ferry)),
    for (final (x, y, kind) in _fillers)
      (x + y, () => _filler(ink, x, y, kind)),
    for (final (i, b) in districtBuildings.indexed)
      (
        b.x + b.y,
        () {
          b._draw(ink, b.x, b.y, t: i < grown.length ? grown[i] : 0);
          // Unlocked, not done: the ghost of it grown, over it (M13-7).
          if (ghosts.contains(i)) b._draw(ghost, b.x, b.y, t: 1);
        },
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  for (final (_, draw) in things) {
    draw();
  }
}

/// Draws what a lesson unlocked but not done will build (M13-7): its colours
/// see-through, its edges faint.
final class GhostPen extends BlockPen {
  GhostPen(Canvas canvas) : super(canvas, DistrictPalette.ghostEdge, 1.2);

  @override
  void fill(Path path, Color color) => canvas
    ..drawPath(
      path,
      Paint()..color = color.withValues(alpha: DistrictPalette.ghostAlpha),
    )
    ..drawPath(
      path,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round,
    );
}

/// A pen and a projection, with the shapes the district and the port are
/// built from.
final class IsoInk {
  IsoInk(this.pen, this.p);

  final BlockPen pen;
  final IsoProjection p;

  bool get detailed => districtDetailed(p);

  void box(
    double cx,
    double cy,
    double w,
    double d,
    double h,
    Shades s, {
    double z = 0,
  }) => pen.block(boxFacets(p, cx - w / 2, cy - d / 2, w, d, h, z: z), s);

  void gable(
    double cx,
    double cy,
    double w,
    double d,
    double h,
    Shades s, {
    required double z,
  }) => pen.block(gableFacets(p, cx - w / 2, cy - d / 2, w, d, h, z: z), s);

  void pyramid(
    double cx,
    double cy,
    double w,
    double h,
    Shades s, {
    required double z,
  }) => pen.block(roofFacets(p, cx - w / 2, cy - w / 2, w, w, h, z: z), s);

  /// Fills [points] flat, no outline.
  void flat(List<Offset> points, Color c) => pen.canvas.drawPath(
    Path()..addPolygon(points, true),
    Paint()
      ..color = pen is GhostPen
          ? c.withValues(alpha: DistrictPalette.ghostAlpha)
          : c,
  );

  /// A quad on the face x = [x] (facing right) or y = [y] (facing left).
  void pane(
    Color c, {
    double? x,
    double? y,
    required double a0,
    required double a1,
    required double z0,
    required double z1,
  }) => flat(
    x != null
        ? [
            p.project(x, a0, z0),
            p.project(x, a1, z0),
            p.project(x, a1, z1),
            p.project(x, a0, z1),
          ]
        : [
            p.project(a0, y!, z0),
            p.project(a1, y, z0),
            p.project(a1, y, z1),
            p.project(a0, y, z1),
          ],
    c,
  );

  /// Rows of windows on a box's two visible faces; finer when zoomed in.
  void facade(
    double cx,
    double cy,
    double w,
    double d,
    double z0,
    double h,
    Color c, {
    double? step,
  }) {
    final s = step ?? (detailed ? 0.2 : 0.42);
    final half = detailed ? 0.035 : 0.06;
    final tall = detailed ? 0.09 : 0.18;
    final x0 = cx - w / 2, y0 = cy - d / 2;
    final nx = detailed ? (w / 0.12).floor().clamp(2, 9) : (w > 0.5 ? 3 : 2);
    final ny = detailed ? (d / 0.12).floor().clamp(2, 9) : (d > 0.5 ? 3 : 2);
    for (var z = z0 + s * 0.6; z + tall < z0 + h - 0.06; z += s) {
      for (var k = 0; k < nx; k++) {
        final f = x0 + w * (k + 0.5) / nx;
        pane(c, y: y0 + d, a0: f - half, a1: f + half, z0: z, z1: z + tall);
      }
      for (var k = 0; k < ny; k++) {
        final f = y0 + d * (k + 0.5) / ny;
        pane(c, x: x0 + w, a0: f - half, a1: f + half, z0: z, z1: z + tall);
      }
    }
  }

  /// A tower of setbacks, windows on each, as tall as [grow] (0 to 1): the
  /// upper tiers only once grown past plain. Returns its roof's height.
  double setbacks(
    double cx,
    double cy,
    List<(double, double)> tiers,
    Shades s,
    Color window, {
    required double grow,
  }) {
    var z = 0.0;
    for (final (i, (w, h0)) in tiers.indexed) {
      if (i > 0 && grow <= _plain) break;
      final h = h0 * grow;
      box(cx, cy, w, w, h, s, z: z);
      facade(cx, cy, w, w, z, h, window);
      z += h;
    }
    return z;
  }

  void waterTower(double x, double y, double z) {
    for (final (dx, dy) in const [(-0.05, -0.05), (0.05, 0.05)]) {
      pen.line(
        p.project(x + dx, y + dy, z),
        p.project(x + dx, y + dy, z + 0.12),
        1,
      );
    }
    box(x, y, 0.15, 0.15, 0.16, DistrictPalette.wood, z: z + 0.12);
    pyramid(x, y, 0.17, 0.1, DistrictPalette.wood, z: z + 0.28);
  }

  void lamp(double x, double y) {
    if (!detailed) return;
    pen.line(p.project(x, y), p.project(x, y, 0.55), 1.2);
    pen.canvas.drawCircle(
      p.project(x, y, 0.58),
      p.tile * 0.025,
      Paint()..color = DistrictPalette.lamp,
    );
  }
}

// ---------------------------------------------------------------- the ground

Path _diamond(
  IsoProjection p,
  double i,
  double j,
  double inset, [
  double size = 1,
]) => Path()
  ..addPolygon([
    p.project(i + inset, j + inset),
    p.project(i + size - inset, j + inset),
    p.project(i + size - inset, j + size - inset),
    p.project(i + inset, j + size - inset),
  ], true);

/// Tile by tile, back to front: a stone sea wall over the dirt where no tile
/// stands in front, then the top: the promenade, or a street block (asphalt,
/// sidewalk, its lot).
void _ground(IsoInk ink, List<String> rows) {
  final p = ink.p, pen = ink.pen;
  final det = ink.detailed;
  bool land(int i, int j) =>
      j >= 0 &&
      j < rows.length &&
      i >= 0 &&
      i < rows[j].length &&
      rows[j][i] != '.';
  final cells = [
    for (var j = 0; j < rows.length; j++)
      for (var i = 0; i < rows[j].length; i++)
        if (land(i, j)) (i, j),
  ]..sort((a, b) => (a.$1 + a.$2).compareTo(b.$1 + b.$2));
  final seam = Paint()
    ..color = DistrictPalette.seam
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6;
  for (final (i, j) in cells) {
    final x = i.toDouble(), y = j.toDouble();
    // Zoomed in, shallower and in strata.
    final depth = det ? 0.5 : 1.0;
    final wall = det ? 0.18 : 0.3;
    final [dl, dr, _] = boxFacets(p, x, y, 1, 1, depth - wall, z: -depth);
    final [wl, wr, _] = boxFacets(p, x, y, 1, 1, wall, z: -wall);
    for (final (show, d, w, a, b, dirt, stone) in [
      (
        !land(i, j + 1),
        dl,
        wl,
        p.project(x, y + 1),
        p.project(x + 1, y + 1),
        MapPalette.dirt.left,
        DistrictPalette.seawall.left,
      ),
      (
        !land(i + 1, j),
        dr,
        wr,
        p.project(x + 1, y),
        p.project(x + 1, y + 1),
        MapPalette.dirt.right,
        DistrictPalette.seawall.right,
      ),
    ]) {
      if (!show) continue;
      if (!det) {
        pen
          ..fill(d.path, dirt)
          ..fill(w.path, stone);
        continue;
      }
      pen.canvas
        ..drawPath(d.path, Paint()..color = dirt)
        ..drawPath(w.path, Paint()..color = stone);
      final down = Offset(0, p.unit);
      for (final z in const [0.2, 0.32, 0.42]) {
        pen.canvas.drawLine(a + down * z, b + down * z, seam);
      }
      pen
        ..line(a, b, 1.5)
        ..line(a + down * depth, b + down * depth, 1.5);
    }
    if (rows[j][i] == 'S') {
      ink.pen.canvas.drawPath(
        _diamond(p, x, y, 0),
        Paint()..color = DistrictPalette.promenade,
      );
      if (det) {
        // Finer ground: a checker of quarter tiles.
        const n = 4;
        final alt = Color.lerp(
          DistrictPalette.promenade,
          AppColors.ink,
          0.045,
        )!;
        for (var a = 0; a < n; a++) {
          for (var b = 0; b < n; b++) {
            if ((a + b).isOdd) {
              pen.canvas.drawPath(
                _diamond(p, x + a / n, y + b / n, 0, 1 / n),
                Paint()..color = alt,
              );
            }
          }
        }
      }
      pen.canvas.drawPath(_diamond(p, x, y, 0), seam);
      continue;
    }
    pen.canvas.drawPath(
      _diamond(p, x, y, 0),
      Paint()..color = DistrictPalette.asphalt,
    );
    if (det) {
      final lane = Paint()
        ..color = DistrictPalette.laneLine
        ..strokeWidth = 1.2;
      pen.canvas
        ..drawLine(
          p.project(x + 0.04, y + 0.3),
          p.project(x + 0.04, y + 0.7),
          lane,
        )
        ..drawLine(
          p.project(x + 0.3, y + 0.04),
          p.project(x + 0.7, y + 0.04),
          lane,
        );
    }
    pen.canvas
      ..drawPath(
        _diamond(p, x, y, 0.09),
        Paint()..color = DistrictPalette.sidewalk,
      )
      ..drawPath(_diamond(p, x, y, 0.15), Paint()..color = DistrictPalette.lot);
  }
}

// ---------------------------------------------------------------- around

/// Actions & ETF's ferry pier, on its mainland side, the ferry at its end.
void _pier(IsoInk ink, {required bool ferry}) {
  for (final a in const [-0.8, -0.3]) {
    ink.box(a, 5.58, 0.06, 0.06, 0.5, DistrictPalette.wood, z: -0.55);
  }
  ink.pen.block(
    boxFacets(ink.p, -1.0, 5.4, 1.2, 0.36, 0.08, z: -0.05),
    DistrictPalette.wood,
  );
  ink.lamp(-0.9, 5.45);
  if (!ferry) return;
  const x0 = -2.9, x1 = -1.3, y = 5.58, cx = (x0 + x1) / 2, w = x1 - x0;
  ink
    ..box(cx, y, w, 0.5, 0.26, DistrictPalette.hull, z: -0.4)
    ..pen.block(
      boxFacets(ink.p, x1, y - 0.25, 0.25, 0.5, 0.26, z: -0.4),
      DistrictPalette.hull,
    )
    ..box(cx, y, w + 0.2, 0.46, 0.05, DistrictPalette.deck, z: -0.14)
    ..box(cx - 0.1, y, w * 0.6, 0.38, 0.24, DistrictPalette.white, z: -0.09)
    ..facade(
      cx - 0.1,
      y,
      w * 0.6,
      0.38,
      -0.09,
      0.24,
      DistrictPalette.glassWindow,
      step: 0.12,
    )
    ..box(cx - 0.1, y, w * 0.45, 0.3, 0.18, DistrictPalette.white, z: 0.15)
    ..box(cx - 0.3, y, 0.12, 0.12, 0.25, DistrictPalette.funnel, z: 0.33);
}

/// The blocks that are no lesson's: a row of brownstones, a brick mid-rise
/// and its water tower, a limestone mid-rise.
void _filler(IsoInk ink, double x, double y, int kind) {
  switch (kind % 3) {
    case 0:
      for (var k = 0; k < 3; k++) {
        final h = (0.55 + (k == 1 ? 0.12 : 0)) * (0.6 + 0.4 * _around);
        final s = k.isEven ? DistrictPalette.brownstone : DistrictPalette.brick;
        ink
          ..box(x - 0.22 + k * 0.22, y, 0.22, 0.6, h, s)
          ..facade(
            x - 0.22 + k * 0.22,
            y,
            0.22,
            0.6,
            0,
            h,
            DistrictPalette.darkWindow,
          );
      }
    case 1:
      final top = ink.setbacks(
        x,
        y,
        const [(0.62, 1.15)],
        DistrictPalette.brick,
        DistrictPalette.litWindow,
        grow: _around,
      );
      ink.waterTower(x + 0.1, y - 0.1, top);
    default:
      final top = ink.setbacks(
        x,
        y,
        const [(0.62, 1.4), (0.44, 0.35)],
        DistrictPalette.limestone,
        DistrictPalette.darkWindow,
        grow: _around,
      );
      ink.waterTower(x - 0.08, y + 0.05, top);
  }
}

// ---------------------------------------------------------------- the twelve

/// A building's heights at [t] (0 plain, 1 grown): eased in between when its
/// lesson is just done (M13-4).
double _grow(double t) => _plain + (1 - _plain) * t.clamp(0.0, 1.0);

void _bank(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  const s = DistrictPalette.limestone;
  if (!grown) {
    ink
      ..box(x, y, 0.62, 0.62, 0.45, s)
      ..facade(x, y, 0.62, 0.62, 0, 0.45, DistrictPalette.darkWindow);
    return;
  }
  ink
    ..box(x, y, 0.72, 0.72, 0.12, s)
    ..box(x, y, 0.62, 0.62, 0.7, s, z: 0.12);
  // Its columns.
  final n = ink.detailed ? 6 : 3;
  final width = ink.detailed ? 2.0 : 1.2;
  for (var k = 0; k < n; k++) {
    final f = -0.31 + 0.62 * (k + 0.5) / n;
    ink.pen
      ..line(
        ink.p.project(x + f, y + 0.31, 0.18),
        ink.p.project(x + f, y + 0.31, 0.74),
        width,
      )
      ..line(
        ink.p.project(x + 0.31, y + f, 0.18),
        ink.p.project(x + 0.31, y + f, 0.74),
        width,
      );
  }
  ink
    ..box(x, y, 0.7, 0.7, 0.08, s, z: 0.82)
    ..gable(x, y, 0.7, 0.7, 0.24, s, z: 0.9);
}

void _tollBridge(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  final p = ink.p;
  if (!grown) {
    // A plank footbridge on piles.
    for (final dx in const [-1.3, -0.8, -0.3]) {
      ink.box(x + dx, y, 0.07, 0.07, 0.8, DistrictPalette.wood, z: -0.6);
    }
    ink.pen.block(
      boxFacets(p, x - 1.6, y - 0.12, 1.9, 0.24, 0.05, z: 0.2),
      DistrictPalette.wood,
    );
    return;
  }
  ink.pen.block(
    boxFacets(p, x - 1.6, y - 0.15, 1.9, 0.3, 0.08, z: 0.45),
    DistrictPalette.slate,
  );
  for (final dy in const [-0.22, 0.22]) {
    ink.box(x, y + dy, 0.26, 0.16, 1.7, DistrictPalette.limestone);
  }
  ink
    ..box(x, y, 0.3, 0.6, 0.18, DistrictPalette.limestone, z: 1.15)
    ..box(x, y, 0.3, 0.6, 0.12, DistrictPalette.limestone, z: 1.7);
  for (final dy in const [-0.15, 0.15]) {
    ink.pen
      ..line(p.project(x, y + dy, 1.8), p.project(x - 1.5, y + dy, 0.55), 1)
      ..line(p.project(x, y + dy, 1.8), p.project(x + 0.3, y + dy, 0.6), 1);
  }
  // Its toll booths.
  for (final dy in const [-0.08, 0.08]) {
    ink.box(x + 0.25, y + dy, 0.12, 0.1, 0.2, MapPalette.roofCoral, z: 0.53);
  }
}

void _store(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  final top = ink.setbacks(
    x,
    y,
    const [(0.7, 1.15)],
    DistrictPalette.brick,
    DistrictPalette.litWindow,
    grow: _grow(t),
  );
  if (!grown) return;
  // Its awnings, then its sign on the roof.
  for (final (k, (s, _)) in MapPalette.buildings.take(4).indexed) {
    final f = x - 0.35 + 0.7 * (k + 0.5) / 4;
    final p = ink.p;
    ink.pen.fill(
      Path()..addPolygon([
        p.project(f - 0.07, y + 0.35, 0.3),
        p.project(f + 0.07, y + 0.35, 0.3),
        p.project(f + 0.07, y + 0.47, 0.22),
        p.project(f - 0.07, y + 0.47, 0.22),
      ], true),
      s.right,
    );
  }
  ink.box(x, y, 0.5, 0.06, 0.16, DistrictPalette.white, z: top);
}

void _loneTower(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  final top = ink.setbacks(
    x,
    y,
    const [(0.4, 3.3)],
    DistrictPalette.glass,
    DistrictPalette.glassWindow,
    grow: _grow(t),
  );
  if (grown) {
    ink.pen.line(
      ink.p.project(x, y, top),
      ink.p.project(x, y, top + 0.45),
      1.4,
    );
  }
}

void _wharf(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  final p = ink.p;
  for (final dx in grown ? const [0.6, 1.1, 1.5] : const [0.6]) {
    for (final dy in const [-0.18, 0.18]) {
      ink.box(x + dx, y + dy, 0.07, 0.07, 0.5, DistrictPalette.wood, z: -0.55);
    }
  }
  ink.pen.block(
    boxFacets(p, x - 0.3, y - 0.22, grown ? 2.0 : 1.0, 0.44, 0.08, z: -0.05),
    DistrictPalette.wood,
  );
  if (!grown) return;
  ink
    ..box(x + 0.95, y, 0.6, 0.34, 0.3, DistrictPalette.steel, z: 0.03)
    ..gable(x + 0.95, y, 0.6, 0.34, 0.14, DistrictPalette.slate, z: 0.33);
}

void _fourTowers(IsoInk ink, double x, double y, {required double t}) {
  for (final (i, (s, h)) in [
    (MapPalette.buildings[3].$1, 0.7),
    (MapPalette.buildings[0].$1, 1.3),
    (MapPalette.buildings[1].$1, 1.9),
    (MapPalette.buildings[2].$1, 2.5),
  ].indexed) {
    ink.setbacks(
      x - 0.27 + i * 0.18,
      y,
      [(0.16, h)],
      s,
      AppColors.surface.withValues(alpha: 0.7),
      grow: _grow(t),
    );
  }
}

void _square(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  final i = x.floor().toDouble(), j = y.floor().toDouble();
  ink.flat([
    ink.p.project(i + 0.1, j + 0.1),
    ink.p.project(i + 0.9, j + 0.1),
    ink.p.project(i + 0.9, j + 0.9),
    ink.p.project(i + 0.1, j + 0.9),
  ], MapPalette.grass);
  // Its tree: a sapling, then a tree of three tiers.
  final g = 0.5 + 0.5 * _grow(t);
  ink
    ..box(x, y, 0.16, 0.16, 0.55 * g, MapPalette.trunk)
    ..box(x, y, 0.72 * g, 0.72 * g, 0.36 * g, MapPalette.leaves, z: 0.55 * g);
  if (!grown) return;
  ink
    ..box(x, y, 0.5, 0.5, 0.32, MapPalette.leaves, z: 0.91)
    ..box(x, y, 0.28, 0.28, 0.24, MapPalette.leaves, z: 1.23);
}

void _harbour(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  final colours = [for (final (s, _) in MapPalette.buildings.take(3)) s];
  for (final (k, s) in colours.indexed) {
    if (!grown && k > 0) break;
    for (var h = 0; h < (grown ? 3 - k % 2 : 1); h++) {
      ink.box(x - 0.25, y - 0.28 + k * 0.28, 0.4, 0.2, 0.12, s, z: h * 0.12);
    }
  }
  if (!grown) return;
  final yellow = MapPalette.buildings[1].$1;
  for (final dy in const [-0.3, 0.3]) {
    ink.box(x + 0.25, y + dy, 0.06, 0.06, 1.0, yellow);
  }
  ink
    ..box(x + 0.5, y, 1.1, 0.08, 0.08, yellow, z: 1.0)
    ..box(x + 1.4, y, 0.9, 0.36, 0.16, DistrictPalette.white, z: -0.2);
  for (final (k, s) in colours.indexed) {
    ink.box(x + 1.15 + k * 0.25, y, 0.22, 0.28, 0.12, s, z: -0.04);
  }
}

void _exchange(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  final top = ink.setbacks(
    x,
    y,
    const [(0.6, 2.0)],
    DistrictPalette.slate,
    DistrictPalette.glassWindow,
    grow: _grow(t),
  );
  if (!grown) return;
  // Its ticker band, gold.
  ink
    ..pane(
      DistrictPalette.lamp,
      y: y + 0.3,
      a0: x - 0.3,
      a1: x + 0.3,
      z0: 1.25,
      z1: 1.45,
    )
    ..pane(
      MapPalette.crown.left,
      x: x + 0.3,
      a0: y - 0.3,
      a1: y + 0.3,
      z0: 1.25,
      z1: 1.45,
    )
    ..box(x, y, 0.3, 0.3, 0.2, DistrictPalette.slate, z: top);
}

void _roofGarden(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  final top = ink.setbacks(
    x,
    y,
    const [(0.64, 1.35)],
    DistrictPalette.limestone,
    DistrictPalette.darkWindow,
    grow: _grow(t),
  );
  if (!grown) return;
  ink.box(x, y, 0.5, 0.5, 0.06, MapPalette.leaves, z: top);
  for (final (dx, dy) in const [(-0.12, -0.12), (0.12, 0.12)]) {
    ink.box(x + dx, y + dy, 0.14, 0.14, 0.16, MapPalette.leaves, z: top + 0.06);
  }
}

void _clockTower(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  final top = ink.setbacks(
    x,
    y,
    const [(0.62, 1.7), (0.46, 0.7)],
    DistrictPalette.limestone,
    DistrictPalette.darkWindow,
    grow: _grow(t),
  );
  if (!grown) return;
  final p = ink.p;
  final c = p.project(x + 0.23, y, 2.05);
  ink.pen
    ..fill(
      Path()..addOval(
        Rect.fromCenter(center: c, width: p.tile * 0.14, height: p.tile * 0.2),
      ),
      AppColors.surface,
    )
    ..line(c, c - Offset(0, p.tile * 0.07), 1)
    ..line(c, c + Offset(p.tile * 0.04, p.tile * 0.02), 1);
  ink.pyramid(x, y, 0.46, 0.7, DistrictPalette.copper, z: top);
}

void _spire(IsoInk ink, double x, double y, {required double t}) {
  final grown = t >= 1;
  final top = ink.setbacks(
    x,
    y,
    const [(0.66, 2.1), (0.52, 1.0), (0.4, 0.7), (0.28, 0.4)],
    DistrictPalette.limestone,
    DistrictPalette.litWindow,
    grow: _grow(t),
  );
  if (!grown) return;
  // Its gold crown: the checkpoint.
  ink.pyramid(x, y, 0.28, 0.65, MapPalette.crown, z: top);
  ink.pen.line(
    ink.p.project(x, y, top + 0.6),
    ink.p.project(x, y, top + 1.2),
    1.6,
  );
}
