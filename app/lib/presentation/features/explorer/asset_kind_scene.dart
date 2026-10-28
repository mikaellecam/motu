import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../domain/market/asset.dart';
import '../map/archipelago.dart';
import '../map/iso.dart';

/// What a section of Explore holds, as a small scene on a square of sea
/// (BRIEF §4.9, M11-5): ETFs, several companies on one plot; stocks, one
/// company, one tower. Decorative: the header says it in words.
class AssetKindScene extends StatelessWidget {
  const AssetKindScene(this.type, {super.key});

  final AssetType type;

  static const size = Size(60, 56);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size.width,
      height: size.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.sea,
        borderRadius: BorderRadius.circular(AppSpace.x3),
      ),
      child: CustomPaint(painter: _ScenePainter(type)),
    ),
  );
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter(this.type);

  final AssetType type;

  /// A plot two tiles wide, the tower and its flag within the square.
  static const _tileOfHeight = 1 / 2.35;

  @override
  void paint(Canvas canvas, Size size) {
    final tile = size.height * _tileOfHeight;
    final p = IsoProjection(
      tile: tile,
      unit: tile / 2,
      // The plot's front corner just above the bottom edge.
      origin: Offset(size.width / 2, size.height - 3 - 0.7 * tile),
    );
    final pen = BlockPen(canvas, AppColors.ink, 1.2);
    final plot = (
      top: MapPalette.grass,
      left: MapPalette.dirt.left,
      right: MapPalette.dirt.right,
    );
    for (final (x, y) in const [
      (-1.0, -1.0),
      (0.0, -1.0),
      (-1.0, 0.0),
      (0.0, 0.0),
    ]) {
      pen.block(boxFacets(p, x, y, 1, 1, 0.4, z: -0.4), plot);
    }
    switch (type) {
      // Back to front.
      case AssetType.etf:
        for (final (x, y, h, colour) in [
          (-0.8, -0.8, 1.2, 0),
          (0.2, -0.8, 1.7, 1),
          (-0.8, 0.2, 0.9, 3),
          (0.2, 0.2, 1.4, 2),
        ]) {
          _building(pen, p, x, y, 0.6, h, colour);
        }
      case AssetType.stock:
        _building(pen, p, -0.4, -0.4, 0.8, 2.2, 0);
        _flag(canvas, p, 0, 0, 2.2);
    }
  }

  static void _building(
    BlockPen pen,
    IsoProjection p,
    double x,
    double y,
    double w,
    double h,
    int colour,
  ) {
    final (shades, lit) = MapPalette.buildings[colour];
    pen.block(boxFacets(p, x, y, w, w, h), shades);
    // Two columns of windows on each visible side, one in three lit.
    final canvas = pen.canvas;
    final light = Paint();
    var row = 0;
    for (var z = 0.3; z + 0.22 <= h - 0.1; z += 0.45, row++) {
      for (final (i, a) in const [0.18, 0.58].indexed) {
        light.color = (row + i) % 3 == 0 ? lit : MapPalette.window;
        final (u0, u1) = (a * w, (a + 0.24) * w);
        canvas
          ..drawPath(
            Path()..addPolygon([
              p.project(x + u0, y + w, z),
              p.project(x + u1, y + w, z),
              p.project(x + u1, y + w, z + 0.22),
              p.project(x + u0, y + w, z + 0.22),
            ], true),
            light,
          )
          ..drawPath(
            Path()..addPolygon([
              p.project(x + w, y + u0, z),
              p.project(x + w, y + u1, z),
              p.project(x + w, y + u1, z + 0.22),
              p.project(x + w, y + u0, z + 0.22),
            ], true),
            light,
          );
      }
    }
  }

  /// The pole from the roof's centre, its pennant in the map's flag colour.
  static void _flag(
    Canvas canvas,
    IsoProjection p,
    double x,
    double y,
    double h,
  ) {
    final foot = p.project(x, y, h);
    final top = p.project(x, y, h + 0.6);
    final ink = Paint()
      ..color = AppColors.ink
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final pennant = Path()
      ..addPolygon([
        top,
        top + Offset(p.unit * 0.9, p.unit * 0.25),
        top + Offset(0, p.unit * 0.5),
      ], true);
    canvas
      ..drawLine(foot, top, ink)
      ..drawPath(pennant, Paint()..color = MapPalette.flag)
      ..drawPath(pennant, ink);
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => oldDelegate.type != type;
}
