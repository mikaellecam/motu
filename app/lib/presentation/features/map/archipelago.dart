import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/tokens.dart';
import 'district.dart';
import 'island_growth.dart';
import 'iso.dart';
import 'living_island.dart';

/// The island a wallet's city stands on, as Actions & ETF (M13-1), and
/// Actions & ETF's district (M13-2).
enum IslandId { actionsEtf }

/// One island as the art direction draws it (BRIEF §4.2): its tiles on a grid
/// of its own, where that grid lies, and how big its blocks are. Coordinates
/// are the art direction's: a phone screen 390 px wide.
final class IslandLayout {
  const IslandLayout(
    this.id, {
    required this.origin,
    required this.tile,
    required this.unit,
    required this.tiles,
    required this.halo,
  });

  final IslandId id;

  /// Where the corner of tile (0, 0) lies.
  final Offset origin;

  /// A tile's width, and one unit of height (a block's), in px.
  final double tile;
  final double unit;

  /// Rows of tiles, back to front, one character each: `.` for the sea; `S`
  /// sand, `g` and `G` grass.
  final List<String> tiles;

  /// The shallow water round it.
  final Rect halo;

  IsoProjection get projection =>
      IsoProjection(tile: tile, unit: unit, origin: origin);
}

/// Actions & ETF where the art direction places it, the only island left
/// drawn this way since the map went (M13-6).
const archipelago = [
  IslandLayout(
    IslandId.actionsEtf,
    origin: Offset(214, 358.5),
    tile: 34,
    unit: 18,
    tiles: [
      '.SSS...',
      '.SgGS..',
      'SgGgGS.',
      'SGgGgGS',
      'SgGgGgS',
      'SGgGgS.',
      'SgSSSS.',
      '.S.....',
    ],
    halo: Rect.fromLTRB(85, 381, 292, 495),
  ),
];

/// Draws an island alone as the art direction does (BRIEF §4.2, §10.2): toy
/// blocks on the sea, its halo resting on the bottom centre. Actions & ETF
/// is a wallet's island in sand and grass, with trees and the wallet's
/// buildings ([buildings], the largest first, M7-2, M13-1); or, given the
/// lessons done, its business district (M13-2).
class ArchipelagoPainter extends CustomPainter {
  ArchipelagoPainter({
    required this.only,
    this.buildings = const [],
    this.grown = 1,
    this.lessonsDone,
    this.ferry = false,
  });

  final List<DrawnBuilding> buildings;

  /// The lessons done, by id: given, Actions & ETF is its business district,
  /// each lesson's building grown by it (M13-2), in place of a wallet's
  /// island ([buildings], [grown]).
  final Set<String>? lessonsDone;

  /// The district's ferry at its pier: the line from the port is open.
  final bool ferry;

  /// How grown a wallet's island is, 0 (sand, no tree) to 1 (as the art
  /// direction draws it): its grass and trees (`grownTiles`).
  final double grown;

  /// The island painted.
  final IslandLayout only;

  @override
  void paint(Canvas canvas, Size size) {
    final island = only;
    final corner = island.halo.bottomCenter - size.bottomCenter(Offset.zero);
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(-corner.dx, -corner.dy)
      ..drawOval(island.halo, Paint()..color = MapPalette.haloOpen);
    final pen = BlockPen(canvas, AppColors.ink, 1.3);
    final lessons = lessonsDone;
    if (lessons != null) {
      paintDistrict(
        pen,
        island.projection,
        island.tiles,
        grown: [for (final g in districtGrown(lessons)) g ? 1.0 : 0.0],
        ferry: ferry,
      );
    } else {
      ground(
        pen,
        island.projection,
        grownTiles(island.tiles, grown),
        locked: false,
      );
      _livingIsland(pen, island.projection);
    }
    canvas.restore();
  }

  /// The art direction's ripple on the sea, starting at [at].
  static Path ripple(Offset at) => Path()
    ..moveTo(at.dx, at.dy)
    ..relativeQuadraticBezierTo(5, -5, 10, 0)
    ..relativeQuadraticBezierTo(5, 5, 10, 0);

  static final wavePaint = Paint()
    ..color = MapPalette.wave
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  /// [rows] of tiles (as [IslandLayout.tiles]), each a block one unit deep,
  /// its sides showing where no tile stands in front. Sides carry the
  /// outline; tops only a thin seam.
  static void ground(
    BlockPen pen,
    IsoProjection p,
    List<String> rows, {
    required bool locked,
  }) {
    bool land(int i, int j) =>
        j < rows.length && i < rows[j].length && rows[j][i] != '.';
    final sides = locked ? MapPalette.stoneSides : MapPalette.dirt;
    final seam = Paint()
      ..color = locked ? MapPalette.stoneSeam : MapPalette.seam
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4;
    final cells = [
      for (var j = 0; j < rows.length; j++)
        for (var i = 0; i < rows[j].length; i++)
          if (land(i, j)) (i, j),
    ]..sort((a, b) => (a.$1 + a.$2).compareTo(b.$1 + b.$2));
    for (final (i, j) in cells) {
      final [left, right, top] = boxFacets(
        p,
        i.toDouble(),
        j.toDouble(),
        1,
        1,
        1,
        z: -1,
      );
      if (!land(i, j + 1)) pen.fill(left.path, sides.left);
      if (!land(i + 1, j)) pen.fill(right.path, sides.right);
      pen.canvas
        ..drawPath(top.path, Paint()..color = _groundColour(rows[j][i]))
        ..drawPath(top.path, seam);
    }
  }

  static Color _groundColour(String tile) => switch (tile) {
    'S' => MapPalette.sand,
    'g' => MapPalette.grass,
    'G' => MapPalette.grassDark,
    'a' => MapPalette.stone,
    'b' => MapPalette.stoneMid,
    _ => MapPalette.stoneDark,
  };

  /// Where buildings stand on Actions & ETF, left to right, rising to the
  /// right as in the art direction: the largest position takes the last
  /// spot, and the flag.
  static const _spots = [
    (1.0, 4.85),
    (1.9, 4.25),
    (2.8, 3.65),
    (3.7, 3.05),
    (4.6, 2.45),
  ];

  /// Its trees, in the order the lessons sprout them: the island's middle
  /// first, as the grass.
  static const _trees = [
    (3.4, 5.5),
    (2.4, 5.8),
    (4.6, 5.3),
    (5.3, 4.4),
    (0.6, 3.1),
  ];
  static const _footprint = 0.72;

  /// Where each of [buildings] stands on [island]'s canvas, in their order
  /// (the largest first), for taps (M11-4): a strip as wide as the step from
  /// one spot to the next, from its roof (its ghost's while a buy waits) to
  /// its foot. At most the island's five spots.
  static List<Rect> buildingRects(
    IslandLayout island,
    List<DrawnBuilding> buildings,
  ) {
    final p = island.projection;
    final step =
        p.project(_spots[1].$1, _spots[1].$2).dx -
        p.project(_spots[0].$1, _spots[0].$2).dx;
    const half = _footprint / 2;
    return [
      for (var i = 0; i < buildings.length && i < _spots.length; i++)
        if (_spots[_spots.length - 1 - i] case (final cx, final cy))
          Rect.fromLTRB(
            p.project(cx, cy).dx - step / 2,
            p.project(cx - half, cy - half, buildings[i].height).dy,
            p.project(cx, cy).dx + step / 2,
            p.project(cx + half, cy + half).dy,
          ),
    ];
  }

  /// Where Actions & ETF's landmark stands once every lesson is done (M9-19):
  /// its right end, clear of the buildings and the trees.
  static const _landmarkSpot = (6.5, 3.5);

  /// A stone column on its plinth, capped in the levels' gold.
  static void _landmark(BlockPen pen, IsoProjection p) {
    final (x, y) = _landmarkSpot;
    Rect around(double size) =>
        Rect.fromCenter(center: Offset(x, y), width: size, height: size);
    final base = around(0.7);
    final shaft = around(0.38);
    pen
      ..block(
        boxFacets(p, base.left, base.top, base.width, base.height, 0.3),
        MapPalette.wall,
      )
      ..block(
        boxFacets(
          p,
          shaft.left,
          shaft.top,
          shaft.width,
          shaft.height,
          2,
          z: 0.3,
        ),
        MapPalette.wall,
      )
      ..block(
        roofFacets(
          p,
          shaft.left,
          shaft.top,
          shaft.width,
          shaft.height,
          0.75,
          z: 2.3,
        ),
        MapPalette.crown,
      );
  }

  /// Windows on Actions & ETF: the first row's height, the step between
  /// rows and a window's height, in units.
  static const _windowRows = (start: 0.28, step: 0.5, size: 0.25);

  void _livingIsland(BlockPen pen, IsoProjection p) {
    // Trees and buildings, back to front.
    final things = <(double, VoidCallback)>[
      for (final (x, y) in _trees.take(grownTrees(_trees.length, grown)))
        (x + y, () => _tree(pen, p, x, y, MapPalette.trunk, MapPalette.leaves)),
      if (landmarkStands(grown))
        (_landmarkSpot.$1 + _landmarkSpot.$2, () => _landmark(pen, p)),
      for (var i = 0; i < buildings.length && i < _spots.length; i++)
        (
          _spots[_spots.length - 1 - i].$1 + _spots[_spots.length - 1 - i].$2,
          () => _building(pen, p, _spots.length - 1 - i, buildings[i]),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, draw) in things) {
      draw();
    }
  }

  static void _building(
    BlockPen pen,
    IsoProjection p,
    int spot,
    DrawnBuilding b,
  ) {
    final (cx, cy) = _spots[spot];
    _buildingAt(pen, p, cx, cy, spot, b);
  }

  /// [b] centred on ([cx], [cy]), in [spot]'s colours, windows and flag.
  static void _buildingAt(
    BlockPen pen,
    IsoProjection p,
    double cx,
    double cy,
    int spot,
    DrawnBuilding b,
  ) {
    if (b.height <= 0) return;
    final (x, y) = (cx - _footprint / 2, cy - _footprint / 2);
    final (shades, lit) = MapPalette.buildings[spot];
    final standing = b.height * b.built.clamp(0, 1);
    // A pending buy: its finished volume first, so that what stands covers
    // the ghost's foot.
    if (b.ghost > 0) _ghost(pen, p, x, y, b.height, shades, b.ghost);
    if (standing > 0) {
      pen.block(boxFacets(p, x, y, _footprint, _footprint, standing), shades);
      _windows(
        pen.canvas,
        p,
        x,
        y,
        _footprint,
        standing,
        rows: _windowRows,
        window: MapPalette.window,
        lit: lit,
        seed: spot,
      );
      if (spot == _spots.length - 1) {
        _flag(pen, p.project(cx, cy, standing), p.unit);
      }
    } else if (b.ghost > 0) {
      // Nothing built yet: the foundation slab.
      pen.block(boxFacets(p, x, y, _footprint, _footprint, 0.06), shades);
    }
  }

  /// Two columns of windows on each visible side, a row every [rows] step up
  /// to just under the roof; one window in three lit.
  static void _windows(
    Canvas canvas,
    IsoProjection p,
    double x,
    double y,
    double w,
    double height, {
    required ({double start, double step, double size}) rows,
    required Color window,
    required Color lit,
    required int seed,
  }) {
    var row = 0;
    for (
      var z = rows.start;
      z + rows.size <= height - 0.4;
      z += rows.step, row++
    ) {
      for (final (col, (a, b)) in const [(0.14, 0.36), (0.64, 0.86)].indexed) {
        final paint = Paint()
          ..color = (seed + row + col) % 3 == 0 ? lit : window;
        final top = z + rows.size;
        // The right side (x + w), then the left (y + w).
        canvas
          ..drawPath(
            _quad([
              p.project(x + w, y + a * w, z),
              p.project(x + w, y + b * w, z),
              p.project(x + w, y + b * w, top),
              p.project(x + w, y + a * w, top),
            ]),
            paint,
          )
          ..drawPath(
            _quad([
              p.project(x + a * w, y + w, z),
              p.project(x + b * w, y + w, z),
              p.project(x + b * w, y + w, top),
              p.project(x + a * w, y + w, top),
            ]),
            paint,
          );
      }
    }
  }

  static Path _quad(List<Offset> corners) => Path()..addPolygon(corners, true);

  /// A pennant on a pole one unit high, above [roof].
  static void _flag(BlockPen pen, Offset roof, double unit) {
    final top = roof - Offset(0, unit);
    pen.line(roof, top, 1.5);
    pen.fill(
      _quad([top, top + const Offset(12, 4), top + const Offset(0, 8)]),
      MapPalette.flag,
    );
  }

  /// A tree standing on (x, y): a trunk 6 px high, a cubic crown on it.
  static void _tree(
    BlockPen pen,
    IsoProjection p,
    double x,
    double y,
    Shades trunk,
    Shades leaves,
  ) {
    const t = 0.12, c = 0.46;
    final trunkHeight = 6 / p.unit;
    pen
      ..block(boxFacets(p, x - t / 2, y - t / 2, t, t, trunkHeight), trunk)
      ..block(
        boxFacets(p, x - c / 2, y - c / 2, c, c, 12 / p.unit, z: trunkHeight),
        leaves,
      );
  }

  /// How opaque a ghost's faces are, at its full [DrawnBuilding.ghost].
  static const _ghostFill = 0.32;

  /// The building a pending buy raises (BRIEF §10.5, M9-45): its finished
  /// volume up to [height], in its own [shades] seen through, its visible
  /// edges dashed. [opacity] fades it as the building completes.
  static void _ghost(
    BlockPen pen,
    IsoProjection p,
    double x,
    double y,
    double height,
    Shades shades,
    double opacity,
  ) {
    for (final (:face, :path) in boxFacets(
      p,
      x,
      y,
      _footprint,
      _footprint,
      height,
    )) {
      final color = switch (face) {
        Face.top => shades.top,
        Face.left => shades.left,
        Face.right => shades.right,
      };
      pen.canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: _ghostFill * opacity),
      );
    }
    final (x1, y1) = (x + _footprint, y + _footprint);
    final paint = Paint()
      ..color = pen.ink.withValues(alpha: opacity)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    // Its nine visible edges, each dashed once: the foot, the three front
    // corners, the roof.
    for (final (a, b) in [
      ((x, y1, 0.0), (x1, y1, 0.0)),
      ((x1, y1, 0.0), (x1, y, 0.0)),
      ((x, y1, 0.0), (x, y1, height)),
      ((x1, y1, 0.0), (x1, y1, height)),
      ((x1, y, 0.0), (x1, y, height)),
      ((x, y1, height), (x1, y1, height)),
      ((x1, y1, height), (x1, y, height)),
      ((x1, y, height), (x, y, height)),
      ((x, y, height), (x, y1, height)),
    ]) {
      _dash(
        pen.canvas,
        p.project(a.$1, a.$2, a.$3),
        p.project(b.$1, b.$2, b.$3),
        paint,
      );
    }
  }

  /// A dashed line from [a] to [b]: dashes of 4 px, gaps of 3.
  static void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 3.0;
    final length = (b - a).distance;
    if (length == 0) return;
    final along = (b - a) / length;
    for (var d = 0.0; d < length; d += dash + gap) {
      final end = d + dash < length ? d + dash : length;
      canvas.drawLine(a + along * d, a + along * end, paint);
    }
  }

  @override
  bool shouldRepaint(ArchipelagoPainter old) =>
      old.only != only ||
      old.grown != grown ||
      old.ferry != ferry ||
      !setEquals(old.lessonsDone, lessonsDone) ||
      !listEquals(old.buildings, buildings);
}

/// Fills shapes and outlines them, as the art direction draws its blocks.
final
/// One building alone, as it stands on Actions & ETF (BRIEF §4.8, M11-6):
/// at the island's scale, in the colours, windows and flag of its place there
/// ([rank], the largest 0), a pending buy's ghost included, on a plot of
/// sand. The asset page's « Ta position ».
class BuildingPortraitPainter
    extends CustomPainter {
  BuildingPortraitPainter(this.building, {required this.rank})
    : assert(rank >= 0 && rank < 5, 'one of the island\'s five spots');

  final DrawnBuilding building;
  final int rank;

  /// Room for the tallest building and its flag over its plot.
  static const size = Size(92, 116);

  @override
  void paint(Canvas canvas, Size size) {
    final island = archipelago.firstWhere((i) => i.id == IslandId.actionsEtf);
    // The plot's front corner just above the bottom edge.
    final p = IsoProjection(
      tile: island.tile,
      unit: island.unit,
      origin: Offset(
        size.width / 2,
        size.height - 4 - island.tile / 4 - 0.4 * island.unit,
      ),
    );
    final pen = BlockPen(canvas, AppColors.ink, 1.3);
    pen.block(boxFacets(p, -0.5, -0.5, 1, 1, 0.4, z: -0.4), MapPalette.dirt);
    final spot = ArchipelagoPainter._spots.length - 1 - rank;
    ArchipelagoPainter._buildingAt(pen, p, 0, 0, spot, building);
  }

  @override
  bool shouldRepaint(BuildingPortraitPainter oldDelegate) =>
      oldDelegate.building != building || oldDelegate.rank != rank;
}

class BlockPen {
  BlockPen(this.canvas, this.ink, double width)
    : _outline = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round;

  final Canvas canvas;
  final Color ink;
  final Paint _outline;

  void fill(Path path, Color color) => canvas
    ..drawPath(path, Paint()..color = color)
    ..drawPath(path, _outline);

  void block(List<Facet> facets, Shades shades) {
    for (final (:face, :path) in facets) {
      fill(path, switch (face) {
        Face.top => shades.top,
        Face.left => shades.left,
        Face.right => shades.right,
      });
    }
  }

  void line(Offset a, Offset b, double width) => canvas.drawLine(
    a,
    b,
    Paint()
      ..color = ink
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round,
  );
}
