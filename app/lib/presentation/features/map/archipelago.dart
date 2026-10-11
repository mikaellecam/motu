import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/tokens.dart';
import 'iso.dart';
import 'living_island.dart';

enum IslandId { actionsEtf, trading, realEstate, crypto, basics }

/// Where an island sits on the world grid and how big it is (tiles).
final class IslandLayout {
  const IslandLayout(this.id, this.x, this.y, this.size, {this.locked = true});

  final IslandId id;
  final double x;
  final double y;
  final int size;

  /// Visible, not playable yet (« Bientôt », BRIEF §4.2).
  final bool locked;
}

/// The five islands: Actions & ETF in the centre, the others around it.
const archipelago = [
  IslandLayout(IslandId.trading, -6, -6, 3),
  IslandLayout(IslandId.realEstate, 7, -3, 3),
  IslandLayout(IslandId.actionsEtf, 0, 0, 4, locked: false),
  IslandLayout(IslandId.crypto, -3, 7, 3),
  IslandLayout(IslandId.basics, 7, 7, 3),
];

/// Ground thickness, in height units.
const _ground = 0.6;

/// Lays the archipelago out on a canvas: the projection, the canvas size, and
/// where each island's label goes.
final class ArchipelagoGeometry {
  factory ArchipelagoGeometry({double tile = 64, double margin = 48}) {
    final raw = IsoProjection(tile: tile, unit: tile / 2);
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final island in archipelago) {
      final s = island.size.toDouble();
      for (final corner in [
        raw.project(island.x, island.y, 3),
        raw.project(island.x + s, island.y),
        raw.project(island.x, island.y + s),
        raw.project(island.x + s, island.y + s, -_ground),
      ]) {
        minX = math.min(minX, corner.dx);
        minY = math.min(minY, corner.dy);
        maxX = math.max(maxX, corner.dx);
        maxY = math.max(maxY, corner.dy);
      }
    }
    // Room below the lowest island for its label.
    final labelRoom = tile * 1.5;
    return ArchipelagoGeometry._(
      raw.shifted(Offset(margin - minX, margin - minY)),
      Size(maxX - minX + 2 * margin, maxY - minY + 2 * margin + labelRoom),
    );
  }

  ArchipelagoGeometry._(this.projection, this.size);

  final IsoProjection projection;
  final Size size;

  /// The point under an island's front corner, where its label hangs.
  Offset labelAnchor(IslandLayout island) => projection.project(
    island.x + island.size,
    island.y + island.size,
    -_ground,
  );

  /// The centre of an island's ground, on the canvas.
  Offset centre(IslandLayout island) => projection.project(
    island.x + island.size / 2,
    island.y + island.size / 2,
  );
}

/// Draws the archipelago in chunky toy blocks (BRIEF §10.1): white tops,
/// light sides, ink outlines. Locked islands are greyed and under clouds.
/// [buildings] stand on Actions & ETF, the largest first (M7-2).
class ArchipelagoPainter extends CustomPainter {
  ArchipelagoPainter(this.geometry, {this.buildings = const []});

  final ArchipelagoGeometry geometry;
  final List<DrawnBuilding> buildings;

  /// Where the buildings stand: a skyline across the island, the largest in
  /// the middle, then outwards left and right. All at the same depth, so
  /// none hides another.
  static const _buildingSpots = [
    (2.0, 2.0),
    (1.4, 2.6),
    (2.6, 1.4),
    (0.8, 3.2),
    (3.2, 0.8),
  ];

  /// The spots back to front, so that nearer buildings hide farther ones.
  static final _paintingOrder =
      [for (var i = 0; i < _buildingSpots.length; i++) i]..sort((a, b) {
        final (ax, ay) = _buildingSpots[a];
        final (bx, by) = _buildingSpots[b];
        return (ax + ay).compareTo(bx + by);
      });

  static const _footprint = 0.8;

  @override
  void paint(Canvas canvas, Size size) {
    final p = geometry.projection;
    final islands = [...archipelago]
      ..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    for (final island in islands) {
      final shade = _Shade(locked: island.locked);
      final s = island.size.toDouble();
      // Ground block, then its tiles.
      shade.draw(
        canvas,
        boxFacets(p, island.x, island.y, s, s, _ground, z: -_ground),
      );
      for (var i = 0; i < island.size; i++) {
        for (var j = 0; j < island.size; j++) {
          shade.draw(
            canvas,
            tileFacets(p, island.x + i, island.y + j),
            outline: 1,
          );
        }
      }
      _props(canvas, p, island, shade);
      if (island.locked) _clouds(canvas, geometry.centre(island));
    }
  }

  void _props(
    Canvas canvas,
    IsoProjection p,
    IslandLayout island,
    _Shade shade,
  ) {
    final (x, y) = (island.x, island.y);
    switch (island.id) {
      case IslandId.actionsEtf:
        for (final i in _paintingOrder) {
          if (i >= buildings.length) continue;
          final b = buildings[i];
          if (b.height <= 0) continue;
          final (bx, by) = _buildingSpots[i];
          final (left, top) = (
            x + bx - _footprint / 2,
            y + by - _footprint / 2,
          );
          final standing = b.height * b.built.clamp(0, 1);
          if (standing > 0) {
            shade.draw(
              canvas,
              boxFacets(p, left, top, _footprint, _footprint, standing),
            );
          }
          if (b.scaffold > 0) {
            if (standing <= 0) {
              // Nothing built yet: the foundation slab.
              shade.draw(
                canvas,
                boxFacets(p, left, top, _footprint, _footprint, 0.06),
              );
            }
            _scaffold(canvas, p, left, top, b.height, b.scaffold, shade);
          }
        }
      case IslandId.trading:
        for (final (i, (low, high)) in [
          (0.3, 1.6),
          (0.8, 2.4),
          (0.5, 2.0),
        ].indexed) {
          final c = candle(p, x + 0.8 + i * 0.7, y + 1.5, low: low, high: high);
          shade.draw(canvas, c.body);
          for (final (a, b) in c.wick) {
            canvas.drawLine(a, b, shade.outlinePaint(2));
          }
        }
      case IslandId.realEstate:
        for (final (hx, hy) in [(0.4, 0.4), (1.6, 1.4)]) {
          shade.draw(canvas, boxFacets(p, x + hx, y + hy, 1, 1, 0.9));
          shade.draw(canvas, roofFacets(p, x + hx, y + hy, 1, 1, 0.8, z: 0.9));
        }
      case IslandId.crypto:
        shade.draw(canvas, crystalFacets(p, x + 1, y + 1));
        shade.draw(canvas, crystalFacets(p, x + 2, y + 2, h: 1.0, r: 0.25));
      case IslandId.basics:
        for (var level = 0; level < 3; level++) {
          shade.draw(
            canvas,
            boxFacets(
              p,
              x + 0.9 + level * 0.1,
              y + 0.9,
              1.2,
              1.2,
              0.3,
              z: level * 0.3,
            ),
          );
        }
    }
  }

  /// A construction frame round a building's footprint, up to [height]
  /// (BRIEF §10.5: a pending buy is a building under construction): a pole
  /// at each corner, and on each visible side a rail every half unit, braced
  /// across.
  void _scaffold(
    Canvas canvas,
    IsoProjection p,
    double x,
    double y,
    double height,
    double opacity,
    _Shade shade,
  ) {
    const gap = 0.08;
    final (x0, y0) = (x - gap, y - gap);
    final (x1, y1) = (x + _footprint + gap, y + _footprint + gap);
    final paint = shade.outlinePaint(1.5)
      ..color = shade.ink.withValues(alpha: opacity);
    void line(
      double ax,
      double ay,
      double az,
      double bx,
      double by,
      double bz,
    ) => canvas.drawLine(p.project(ax, ay, az), p.project(bx, by, bz), paint);
    // The back pole first: the others stand in front of it.
    for (final (cx, cy) in [(x0, y0), (x1, y0), (x0, y1), (x1, y1)]) {
      line(cx, cy, 0, cx, cy, height);
    }
    final levels = [for (var z = 0.0; z < height - 0.05; z += 0.5) z, height];
    for (var i = 0; i < levels.length; i++) {
      final z = levels[i];
      // The two visible sides: y = y1 (left) and x = x1 (right).
      line(x0, y1, z, x1, y1, z);
      line(x1, y0, z, x1, y1, z);
      if (i == 0) continue;
      final below = levels[i - 1];
      line(x0, y1, below, x1, y1, z);
      line(x1, y0, below, x1, y1, z);
    }
  }

  void _clouds(Canvas canvas, Offset centre) {
    final fill = Paint()..color = AppColors.surface.withValues(alpha: 0.9);
    final outline = Paint()
      ..color = AppColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final (dx, dy, w) in [
      (-34.0, -28.0, 64.0),
      (6.0, -40.0, 84.0),
      (40.0, -22.0, 56.0),
    ]) {
      final rect = Rect.fromCenter(
        center: centre + Offset(dx, dy),
        width: w,
        height: w * 0.45,
      );
      canvas.drawOval(rect, fill);
      canvas.drawOval(rect, outline);
    }
  }

  @override
  bool shouldRepaint(ArchipelagoPainter old) =>
      old.geometry != geometry || !listEquals(old.buildings, buildings);
}

/// Neutral tokens only: the art carries no meaning a colour could suggest.
class _Shade {
  _Shade({required bool locked})
    : _top = locked ? AppColors.page : AppColors.surface,
      _left = locked ? AppColors.line : AppColors.page,
      _right = AppColors.line,
      _ink = locked ? AppColors.muted : AppColors.ink;

  final Color _top;
  final Color _left;
  final Color _right;
  final Color _ink;

  Color get ink => _ink;

  Paint outlinePaint(double width) => Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  void draw(Canvas canvas, List<Facet> facets, {double outline = 2.5}) {
    for (final (:face, :path) in facets) {
      canvas.drawPath(
        path,
        Paint()
          ..color = switch (face) {
            Face.top => _top,
            Face.left => _left,
            Face.right => _right,
          },
      );
      canvas.drawPath(path, outlinePaint(outline));
    }
  }
}
