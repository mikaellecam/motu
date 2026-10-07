import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../../core/theme/tokens.dart';
import 'iso.dart';

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
/// [buildingHeights] are the Actions & ETF buildings, in height units.
class ArchipelagoPainter extends CustomPainter {
  ArchipelagoPainter(this.geometry, {this.buildingHeights = const []});

  final ArchipelagoGeometry geometry;
  final List<double> buildingHeights;

  static const _buildingSpots = [
    (0.6, 0.6),
    (2.4, 0.6),
    (0.6, 2.4),
    (2.4, 2.4),
    (1.5, 1.5),
  ];

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
        for (var i = 0; i < _buildingSpots.length; i++) {
          final (bx, by) = _buildingSpots[i];
          final h = i < buildingHeights.length ? buildingHeights[i] : 0.4;
          if (h <= 0) continue;
          shade.draw(
            canvas,
            boxFacets(p, x + bx - 0.4, y + by - 0.4, 0.8, 0.8, h),
          );
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
      old.geometry != geometry ||
      !_sameHeights(old.buildingHeights, buildingHeights);

  static bool _sameHeights(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
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
