import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/tokens.dart';
import 'island_growth.dart';
import 'iso.dart';
import 'living_island.dart';

enum IslandId { actionsEtf, trading, realEstate, crypto, basics }

/// One island as the art direction draws it (BRIEF §4.2): its tiles on a grid
/// of its own, where that grid lies on the map, and how big its blocks are.
/// Map coordinates are the art direction's: a phone screen 390 px wide.
final class IslandLayout {
  const IslandLayout(
    this.id, {
    required this.origin,
    required this.tile,
    required this.unit,
    required this.tiles,
    required this.halo,
    required this.label,
    this.clouds = const [],
    this.locked = true,
  });

  final IslandId id;

  /// Where the corner of tile (0, 0) lies on the map.
  final Offset origin;

  /// A tile's width, and one unit of height (a block's), in map px.
  final double tile;
  final double unit;

  /// Rows of tiles, back to front, one character each: `.` for the sea; `S`
  /// sand, `g` and `G` grass; `a`, `b` and `c` stone, light to dark.
  final List<String> tiles;

  /// The shallow water round it.
  final Rect halo;

  /// The top centre of its label.
  final Offset label;

  /// Its clouds: where each one's left puff floats, and its scale.
  final List<(Offset, double)> clouds;

  /// Visible, not playable yet (« Bientôt », BRIEF §4.2).
  final bool locked;

  IsoProjection get projection =>
      IsoProjection(tile: tile, unit: unit, origin: origin);

  /// The top centre of its label, on the map widget.
  Offset get labelAnchor => label - mapBounds.topLeft;
}

/// The five islands, back to front, where the art direction places them:
/// Actions & ETF in the centre, the locked ones round it.
const archipelago = [
  IslandLayout(
    IslandId.trading,
    origin: Offset(90, 208),
    tile: 30,
    unit: 14,
    tiles: ['aaaa', 'abca', 'acba', '.aa.'],
    halo: Rect.fromLTRB(35, 218, 160, 282.4),
    label: Offset(90, 292),
    clouds: [(Offset(38, 230), 1.0), (Offset(98, 260), 0.8)],
  ),
  IslandLayout(
    IslandId.realEstate,
    origin: Offset(305, 222),
    tile: 30,
    unit: 14,
    tiles: ['aaaa', 'abca', 'acba', 'aaaa'],
    halo: Rect.fromLTRB(235, 232, 375, 304),
    label: Offset(305, 306),
    clouds: [(Offset(253, 244), 1.0), (Offset(313, 274), 0.8)],
  ),
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
    label: Offset(197, 506),
    locked: false,
  ),
  IslandLayout(
    IslandId.crypto,
    origin: Offset(82, 526),
    tile: 30,
    unit: 14,
    tiles: ['.aa.', 'abca', 'acba', '.aa.'],
    halo: Rect.fromLTRB(27, 542.5, 137, 599.5),
    label: Offset(82, 604),
    clouds: [(Offset(30, 548), 1.0), (Offset(90, 578), 0.8)],
  ),
  IslandLayout(
    IslandId.basics,
    origin: Offset(312, 530),
    tile: 30,
    unit: 14,
    tiles: ['aaa.', 'abca', 'acba', '.aa.'],
    halo: Rect.fromLTRB(257, 539, 367, 603.4),
    label: Offset(312, 608),
    clouds: [(Offset(260, 552), 1.0), (Offset(320, 582), 0.8)],
  ),
];

/// The part of the art direction's screen the map shows: every island, its
/// tallest prop and its label.
const mapBounds = Rect.fromLTRB(0, 166, 390, 660);
final mapSize = mapBounds.size;

/// Where the art direction ripples the sea.
const _waves = [
  Offset(92.1, 87.1), Offset(154.5, 130.8), Offset(25.9, 338.9), //
  Offset(358, 675.6), Offset(298.4, 187.3), Offset(209.3, 233.5),
  Offset(67.3, 89.6), Offset(83.6, 782.8), Offset(323.3, 680.8),
  Offset(312.2, 163.3), Offset(120.8, 529.2), Offset(285.4, 721.3),
  Offset(343.2, 73.2), Offset(236.3, 566.9), Offset(197.3, 150.1),
  Offset(184.7, 75.4), Offset(364.5, 730.5), Offset(213.6, 253.4),
  Offset(354.5, 483.1), Offset(344.1, 715.7), Offset(198.3, 349.4),
  Offset(233.6, 363.8), Offset(62.9, 257.5), Offset(316.9, 36.5),
  Offset(18.1, 528.6), Offset(109.4, 451.2), Offset(183.8, 289.4),
  Offset(388.9, 165.1), Offset(161, 171.1), Offset(246.7, 233.2),
  Offset(138.8, 630.4), Offset(125.1, 471.4), Offset(352.7, 85.2),
  Offset(24, 193.2), Offset(298.4, 519.4), Offset(92.6, 279.4),
  Offset(69.2, 387.4), Offset(16.7, 588.5), Offset(349.4, 805.8),
  Offset(286.6, 810.1), Offset(7.1, 243.9), Offset(376.7, 654.3),
  Offset(160.1, 796.2), Offset(242, 690.3), Offset(114.4, 161.6),
  Offset(173.2, 115.2),
];

/// Draws the archipelago as the art direction does (BRIEF §4.2, §10.2): toy
/// blocks on the sea; Actions & ETF in sand and grass, with trees and the
/// live wallet's buildings ([buildings], the largest first, M7-2); the
/// locked islands in grey stone under clouds.
class ArchipelagoPainter extends CustomPainter {
  ArchipelagoPainter({this.buildings = const [], this.only, this.grown = 1});

  final List<DrawnBuilding> buildings;

  /// How far the lessons have greened Actions & ETF, 0 (sand, no tree) to 1
  /// (as the art direction draws it): its grass and trees (`grownTiles`).
  final double grown;

  /// Paints this island alone, its halo resting on the bottom centre, with
  /// no waves: the island path's header (BRIEF §4.3).
  final IslandLayout? only;

  @override
  void paint(Canvas canvas, Size size) {
    final only = this.only;
    final corner = only == null
        ? mapBounds.topLeft
        : only.halo.bottomCenter - size.bottomCenter(Offset.zero);
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(-corner.dx, -corner.dy);
    if (only == null) {
      for (final o in _waves) {
        canvas.drawPath(ripple(o), wavePaint);
      }
    }
    for (final island in only == null ? archipelago : [only]) {
      canvas.drawOval(
        island.halo,
        Paint()..color = island.locked ? MapPalette.halo : MapPalette.haloOpen,
      );
      final pen = island.locked
          ? BlockPen(canvas, MapPalette.lockedInk, 1.1)
          : BlockPen(canvas, AppColors.ink, 1.3);
      ground(
        pen,
        island.projection,
        island.id == IslandId.actionsEtf
            ? grownTiles(island.tiles, grown)
            : island.tiles,
        locked: island.locked,
      );
      final p = island.projection;
      switch (island.id) {
        case IslandId.actionsEtf:
          _livingIsland(pen, p);
        case IslandId.trading:
          _trading(pen, p);
        case IslandId.realEstate:
          _realEstate(pen, p);
        case IslandId.crypto:
          _crypto(pen, p);
        case IslandId.basics:
          _basics(pen, p);
      }
      for (final (at, scale) in island.clouds) {
        _cloud(canvas, at, scale);
      }
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

  /// Trading: five candlesticks, two of them darker.
  static void _trading(BlockPen pen, IsoProjection p) {
    for (final (x, y, low, high, top, dark) in const [
      (0.8, 2.7, 0.71, 2.0, 2.57, false),
      (1.4, 2.2, 1.14, 3.29, 3.86, true),
      (2.0, 1.7, 0.57, 2.0, 2.57, false),
      (2.6, 1.2, 1.0, 3.71, 4.29, false),
      (3.1, 0.7, 1.85, 3.43, 4.0, true),
    ]) {
      final c = candle(p, x, y, bodyLow: low, bodyHigh: high, high: top);
      pen
        ..line(c.lowerWick.$1, c.lowerWick.$2, 2)
        ..block(c.body, dark ? MapPalette.blockDark : MapPalette.block)
        ..line(c.upperWick.$1, c.upperWick.$2, 2);
    }
  }

  /// Windows on a stone tower.
  static const _towerRows = (start: 0.35, step: 0.57, size: 0.29);

  /// Real estate: houses and two towers between two trees.
  static void _realEstate(BlockPen pen, IsoProjection p) {
    _tree(pen, p, 0.7, 1.4, MapPalette.stoneTrunk, MapPalette.stoneLeaves);
    _tower(pen, p, 2.2, 0.7, 2.29);
    _house(pen, p, 1.8, 1.9, w: 0.6, wall: 0.64, roof: 0.64);
    _house(pen, p, 1.0, 2.7, w: 0.6, wall: 0.64, roof: 0.64);
    _tower(pen, p, 2.9, 1.3, 3.57);
    _house(pen, p, 2.4, 2.9, w: 0.6, wall: 0.64, roof: 0.64);
    _tree(pen, p, 3.4, 2.4, MapPalette.stoneTrunk, MapPalette.stoneLeaves);
  }

  static void _tower(
    BlockPen pen,
    IsoProjection p,
    double cx,
    double cy,
    double height,
  ) {
    const w = 0.6;
    final (x, y) = (cx - w / 2, cy - w / 2);
    pen.block(boxFacets(p, x, y, w, w, height), MapPalette.block);
    _windows(
      pen.canvas,
      p,
      x,
      y,
      w,
      height,
      rows: _towerRows,
      window: MapPalette.stoneWindow,
      lit: MapPalette.wallDark.top,
      seed: 1,
    );
  }

  static void _house(
    BlockPen pen,
    IsoProjection p,
    double cx,
    double cy, {
    required double w,
    required double wall,
    required double roof,
  }) {
    final (x, y) = (cx - w / 2, cy - w / 2);
    pen
      ..block(boxFacets(p, x, y, w, w, wall), MapPalette.wall)
      ..block(gableFacets(p, x, y, w, w, roof, z: wall), MapPalette.roof);
  }

  /// Crypto: a crystal on its tip between two small blocks.
  static void _crypto(BlockPen pen, IsoProjection p) {
    _cube(pen, p, 1.2, 2.6, 0.4, 0.36);
    for (final (face, path) in crystalPaths(
      p,
      1.57,
      1.37,
      r: 0.42,
      mid: 1.2,
      h: 2.86,
    ).indexed) {
      pen.fill(path, MapPalette.crystal[face]);
    }
    _cube(pen, p, 2.9, 2.3, 0.32, 0.29);
  }

  static void _cube(
    BlockPen pen,
    IsoProjection p,
    double cx,
    double cy,
    double w,
    double h,
  ) => pen.block(
    boxFacets(p, cx - w / 2, cy - w / 2, w, w, h),
    MapPalette.blockDark,
  );

  /// Les bases: a house and a lighthouse of five courses.
  static void _basics(BlockPen pen, IsoProjection p) {
    _house(pen, p, 1.1, 2.6, w: 0.55, wall: 0.57, roof: 0.5);
    const cx = 2.3, cy = 1.7;
    Rect footprint(double w) =>
        Rect.fromCenter(center: const Offset(cx, cy), width: w, height: w);
    void course(double w, double z, double h, Shades shades) {
      final f = footprint(w);
      pen.block(boxFacets(p, f.left, f.top, w, w, h, z: z), shades);
    }

    const step = 9 / 14;
    for (var i = 0; i < 5; i++) {
      course(
        0.5,
        i * step,
        step,
        i.isEven ? MapPalette.wall : MapPalette.wallDark,
      );
    }
    course(0.72, 5 * step, 0.21, MapPalette.wall);
    course(0.38, 5 * step + 0.21, 0.57, MapPalette.wall);
    final cap = footprint(0.38);
    pen.block(
      roofFacets(p, cap.left, cap.top, 0.38, 0.38, 0.65, z: 5 * step + 0.78),
      MapPalette.wallDark,
    );
  }

  /// Six white puffs, as the art direction draws a cloud.
  static void _cloud(Canvas canvas, Offset at, double scale) {
    final paint = Paint()..color = MapPalette.cloud;
    for (final (dx, dy, r) in const [
      (0.0, 0.0, 14.0),
      (16.0, -6.0, 18.0),
      (34.0, 0.0, 14.0),
      (16.0, 6.0, 14.0),
      (-10.0, 6.0, 9.0),
      (46.0, 6.0, 9.0),
    ]) {
      canvas.drawCircle(at + Offset(dx, dy) * scale, r * scale, paint);
    }
  }

  @override
  bool shouldRepaint(ArchipelagoPainter old) =>
      old.only != only ||
      old.grown != grown ||
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
