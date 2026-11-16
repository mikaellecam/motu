import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../application/learning/content.dart';
import '../../../core/theme/tokens.dart';
import 'archipelago.dart';
import 'district.dart';
import 'iso.dart';

// Les bases is the mainland and its harbour (BRIEF §4.2, M13-3). The coast
// runs along x = 0, the land at x < 0: inland only grass, a paved quayside
// and its railway. From the start an old wooden jetty and two rowboats; each
// lesson builds its part of the harbour.

/// A lesson's part of the harbour: the node it is built with, where it
/// stands, and how it is drawn.
final class PortPart {
  const PortPart(this.nodeId, this.x, this.y, this._draw, {required this.top});

  final String nodeId;
  final double x, y;

  /// Its top once built: where its marker stands (M13-4); before, the marker
  /// sits on its empty spot.
  final double top;

  ({double x, double y, double z}) anchor({required bool built}) =>
      (x: x, y: y, z: built ? top : 0.2);
  final void Function(IsoInk ink, double x, double y) _draw;
}

/// The nine, in the order of Les bases' lessons (BRIEF §4.3).
const portParts = [
  PortPart('lb.safety-cushion', 4.0, 3.5, _breakwater, top: 0.6),
  PortPart('lb.cash-inflation', 3.0, 0.9, _tideGauge, top: 1.4),
  PortPart('lb.livret-inflation', 0.9, 7.0, _lock, top: 0.5),
  PortPart('lb.mission-livret', -1.4, 4.3, _warehouse, top: 1.3),
  PortPart('lb.cushion-2020', 1.2, 1.5, _ferryQuay, top: 0.9),
  PortPart('lb.loan-cost', 1.4, 4.2, _crane, top: 2.0),
  PortPart('lb.save-or-repay', -1.0, 1.6, _harbourOffice, top: 2.0),
  PortPart('lb.spot-the-scam', -0.9, -0.9, _watchtower, top: 2.2),
  PortPart('lb.checkpoint-1', 4.0, 0.0, _lighthouse, top: 4.8),
];

/// How many parts stand for those who skip Les bases at onboarding: the port
/// through its ferry quay, the line to Actions & ETF open (decided
/// 2026-11-16).
const _skippedThrough = 5;

/// Which of [portParts] stand: those whose lesson is in [done], and the
/// first five for those who [skipped] Les bases. Ids that are no part's
/// change nothing.
List<bool> portBuilt(Set<String> done, {required bool skipped}) => [
  for (final (i, part) in portParts.indexed)
    done.contains(part.nodeId) || (skipped && i < _skippedThrough),
];

/// The islands whose sea line leaves the harbour, in the order they are
/// drawn from the harbour mouth out.
const _lines = [
  actionsEtfIsland,
  realEstateIsland,
  cryptoIsland,
  tradingIsland,
];

/// Paints the mainland's coast and its harbour on [size]: the parts [built]
/// as [portBuilt] gives them, the sea [lines] open (island ids, as
/// [portLines] gives them) leaving towards the right edge.
void paintPort(
  BlockPen pen,
  IsoProjection p,
  Size size, {
  required List<bool> built,
  required Set<String> lines,
}) {
  final ink = IsoInk(pen, p);
  _mainland(ink);
  final things = <(double, VoidCallback)>[..._oldJetty(ink)];
  for (final (i, part) in portParts.indexed) {
    if (i < built.length && built[i]) {
      things.add((part.x + part.y, () => part._draw(ink, part.x, part.y)));
    }
  }
  things.sort((a, b) => a.$1.compareTo(b.$1));
  for (final (_, draw) in things) {
    draw();
  }
  // From the ferry quay, round the lighthouse, out to the open sea.
  final from = p.project(2.4, 1.6), round = p.project(5.2, -0.4);
  for (final (k, island) in _lines.indexed) {
    if (!lines.contains(island)) continue;
    _seaLine(
      pen.canvas,
      from,
      round,
      Offset(size.width + 10, round.dy + size.height * (0.06 + 0.1 * k)),
    );
  }
}

void _seaLine(Canvas canvas, Offset from, Offset via, Offset to) {
  final path = Path()
    ..moveTo(from.dx, from.dy)
    ..quadraticBezierTo(via.dx, via.dy, to.dx, to.dy);
  final paint = Paint()
    ..color = PortPalette.seaLine
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  for (final m in path.computeMetrics()) {
    for (var d = 0.0; d < m.length; d += 11) {
      canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), paint);
    }
  }
}

/// The mainland: grass inland, a paved quayside along the coast and its sea
/// wall in courses; zoomed in, its paving and railway.
void _mainland(IsoInk ink) {
  final p = ink.p, canvas = ink.pen.canvas;
  const far = 30.0;
  ink
    ..flat([
      p.project(-far, -far),
      p.project(0, -far),
      p.project(0, far),
      p.project(-far, far),
    ], MapPalette.grass)
    ..flat([
      p.project(-1.9, -far),
      p.project(0, -far),
      p.project(0, far),
      p.project(-1.9, far),
    ], PortPalette.quay.top);
  if (ink.detailed) {
    final seam = Paint()
      ..color = DistrictPalette.seam
      ..strokeWidth = 0.6;
    for (var a = -far; a < far; a += 0.5) {
      canvas.drawLine(p.project(-1.9, a), p.project(0, a), seam);
    }
    for (var b = -1.9; b < 0; b += 0.5) {
      canvas.drawLine(p.project(b, -far), p.project(b, far), seam);
    }
    final rail = Paint()
      ..color = PortPalette.rail
      ..strokeWidth = 1.6;
    final sleeper = Paint()
      ..color = PortPalette.sleeper
      ..strokeWidth = 3;
    for (var a = -far; a < far; a += 0.22) {
      canvas.drawLine(p.project(-1.62, a), p.project(-1.18, a), sleeper);
    }
    for (final b in const [-1.55, -1.25]) {
      canvas.drawLine(p.project(b, -far), p.project(b, far), rail);
    }
  }
  // The sea wall: the right face of the coast.
  ink.pen.block(
    boxFacets(p, -far, -far, far, 2 * far, 0.6, z: -0.6).sublist(1, 2),
    PortPalette.quay,
  );
  _courses(ink, -far, -far, 0, far, 0, -0.6);
}

/// Stone courses on a wall's sea faces, staggered; zoomed in only.
void _courses(
  IsoInk ink,
  double x0,
  double y0,
  double x1,
  double y1,
  double zTop,
  double zBottom,
) {
  if (!ink.detailed) return;
  final p = ink.p;
  final seam = Paint()
    ..color = PortPalette.course
    ..strokeWidth = 1;
  for (var z = zTop - 0.18; z > zBottom + 0.05; z -= 0.18) {
    ink.pen.canvas
      ..drawLine(p.project(x0, y1, z), p.project(x1, y1, z), seam)
      ..drawLine(p.project(x1, y0, z), p.project(x1, y1, z), seam);
    final odd = ((zTop - z) / 0.18).round().isOdd;
    for (var a = x0 + (odd ? 0.2 : 0.4); a < x1; a += 0.4) {
      ink.pen.canvas.drawLine(
        p.project(a, y1, z),
        p.project(a, y1, z + 0.18),
        seam,
      );
    }
    for (var a = y0 + (odd ? 0.2 : 0.4); a < y1; a += 0.4) {
      ink.pen.canvas.drawLine(
        p.project(x1, a, z),
        p.project(x1, a, z + 0.18),
        seam,
      );
    }
  }
}

/// A stone quay jutting into the sea, its walls in courses; zoomed in, its
/// fenders and bollards.
void _stoneQuay(IsoInk ink, double x0, double y0, double x1, double y1) {
  ink.pen.block(
    boxFacets(ink.p, x0, y0, x1 - x0, y1 - y0, 0.6, z: -0.6),
    PortPalette.quay,
  );
  _courses(ink, x0, y0, x1, y1, 0, -0.6);
  if (!ink.detailed) return;
  for (var a = x0 + 0.15; a < x1 - 0.1; a += 0.35) {
    ink.pane(
      PortPalette.fender,
      y: y1,
      a0: a,
      a1: a + 0.12,
      z0: -0.34,
      z1: -0.08,
    );
  }
  for (var a = y0 + 0.15; a < y1 - 0.1; a += 0.35) {
    ink.pane(
      PortPalette.fender,
      x: x1,
      a0: a,
      a1: a + 0.12,
      z0: -0.34,
      z1: -0.08,
    );
  }
  for (var a = x0 + 0.4; a < x1 - 0.1; a += 0.6) {
    ink.box(a, y1 - 0.08, 0.08, 0.08, 0.1, PortPalette.iron);
  }
  for (var a = y0 + 0.25; a < y1; a += 0.5) {
    ink.box(x1 - 0.08, a, 0.08, 0.08, 0.1, PortPalette.iron);
  }
}

/// A ship along x from [x0] to [x1], at [y]: a ferry, or a container ship.
void _ship(
  IsoInk ink,
  double x0,
  double x1,
  double y,
  Shades hull, {
  bool ferry = false,
}) {
  final w = x1 - x0, cx = (x0 + x1) / 2;
  ink
    ..box(cx, y, w, 0.5, 0.26, hull, z: -0.4)
    ..pen.block(boxFacets(ink.p, x1, y - 0.25, 0.25, 0.5, 0.26, z: -0.4), hull)
    ..box(cx, y, w + 0.2, 0.46, 0.05, DistrictPalette.deck, z: -0.14);
  if (ferry) {
    ink
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
    return;
  }
  for (var k = 0; k < (w / 0.32).floor(); k++) {
    for (var h = 0; h < 2; h++) {
      ink.box(
        x0 + 0.2 + k * 0.32,
        y,
        0.3,
        0.38,
        0.14,
        MapPalette.buildings[(k + h) % 4].$1,
        z: -0.09 + h * 0.14,
      );
    }
  }
  ink.box(x0 + 0.05, y, 0.25, 0.36, 0.4, DistrictPalette.white, z: -0.09);
}

void _rowboat(IsoInk ink, double x, double y, Shades s) => ink
  ..box(x, y, 0.5, 0.2, 0.1, s, z: -0.36)
  ..box(x, y, 0.08, 0.18, 0.04, DistrictPalette.wood, z: -0.26);

/// What the shore holds from the start: an old wooden jetty, two rowboats.
List<(double, VoidCallback)> _oldJetty(IsoInk ink) => [
  (
    9.2,
    () {
      for (var a = 0.3; a < 1.4; a += 0.45) {
        ink.box(a, 8.75, 0.07, 0.07, 0.5, DistrictPalette.wood, z: -0.6);
      }
      ink.pen.block(
        boxFacets(ink.p, 0, 8.6, 1.4, 0.36, 0.07, z: -0.05),
        DistrictPalette.wood,
      );
    },
  ),
  (9.6, () => _rowboat(ink, 0.8, 9.2, MapPalette.roofCoral)),
  (8.9, () => _rowboat(ink, 1.2, 8.2, DistrictPalette.hull)),
];

// ---------------------------------------------------------------- the nine

void _breakwater(IsoInk ink, double x, double y) {
  // Armour rocks either side of a concrete crown wall and its walkway.
  void rocks(double dx, int seed) {
    final rnd = math.Random(seed);
    final fine = ink.detailed;
    for (var a = 0.4; a < 7.1; a += fine ? 0.2 : 0.4) {
      final r = (fine ? 0.16 : 0.3) + rnd.nextDouble() * (fine ? 0.1 : 0.12);
      ink.box(
        x + dx + (rnd.nextDouble() - 0.5) * 0.1,
        a + (rnd.nextDouble() - 0.5) * 0.08,
        r,
        r,
        0.28 + rnd.nextDouble() * 0.14,
        rnd.nextBool() ? PortPalette.rock : PortPalette.rockLight,
        z: -0.6,
      );
    }
  }

  rocks(-0.3, 3);
  ink.pen.block(
    boxFacets(ink.p, x - 0.16, 0.3, 0.32, 6.9, 0.62, z: -0.6),
    PortPalette.quay,
  );
  _courses(ink, x - 0.16, 0.3, x + 0.16, 7.2, 0.02, -0.6);
  ink.box(x + 0.08, 3.7, 0.08, 6.8, 0.12, PortPalette.quay, z: 0.02);
  rocks(0.3, 4);
}

void _tideGauge(IsoInk ink, double x, double y) {
  ink.box(x, y, 0.16, 0.16, 0.2, PortPalette.rock, z: -0.6);
  for (var i = 0; i < 8; i++) {
    ink.box(
      x,
      y,
      0.09,
      0.09,
      0.18,
      i.isEven ? MapPalette.lighthouseBand : DistrictPalette.white,
      z: -0.4 + i * 0.18,
    );
  }
}

void _lock(IsoInk ink, double x, double y) {
  final p = ink.p;
  _stoneQuay(ink, 0, 6.1, 1.9, 6.35);
  // The water held at its level between the gates.
  ink.flat([
    p.project(0, 6.35, -0.15),
    p.project(1.8, 6.35, -0.15),
    p.project(1.8, 7.65, -0.15),
    p.project(0, 7.65, -0.15),
  ], PortPalette.lockWater);
  for (final gx in const [0.9, 1.8]) {
    ink.box(gx, 7.0, 0.1, 1.3, 0.55, DistrictPalette.wood, z: -0.6);
    if (ink.detailed) {
      ink.pen.line(
        p.project(gx + 0.05, 6.4, -0.05),
        p.project(gx + 0.05, 7.6, -0.05),
        1,
      );
    }
  }
  _stoneQuay(ink, 0, 7.65, 1.9, 7.9);
}

void _warehouse(IsoInk ink, double x, double y) {
  ink
    ..box(x, y, 1.0, 1.8, 0.8, DistrictPalette.brick)
    ..facade(x, y, 1.0, 1.8, 0.35, 0.45, DistrictPalette.darkWindow);
  for (final dy in const [-0.5, 0.0, 0.5]) {
    ink.pane(
      PortPalette.loadingDoor,
      x: x + 0.5,
      a0: y + dy - 0.15,
      a1: y + dy + 0.15,
      z0: 0,
      z1: 0.32,
    );
  }
  ink
    ..gable(x, y, 1.0, 1.8, 0.4, DistrictPalette.slate, z: 0.8)
    ..box(x + 0.75, y + 0.3, 0.22, 0.22, 0.22, DistrictPalette.wood)
    ..box(x + 0.75, y + 0.6, 0.22, 0.22, 0.22, DistrictPalette.wood);
}

void _ferryQuay(IsoInk ink, double x, double y) {
  final p = ink.p;
  _stoneQuay(ink, 0, 1.0, 2.3, 1.95);
  for (final (cx, cy) in const [(0.25, 1.25), (0.25, 1.5), (0.5, 1.3)]) {
    ink.box(cx, cy, 0.18, 0.18, 0.16, DistrictPalette.wood);
  }
  ink
    ..lamp(0.5, 1.2)
    ..lamp(1.7, 1.2);
  _ship(ink, 0.3, 2.0, 2.3, DistrictPalette.hull, ferry: true);
  if (ink.detailed) {
    // Its mooring lines.
    ink.pen
      ..line(p.project(0.6, 1.9, 0.1), p.project(0.6, 2.1, -0.1), 1)
      ..line(p.project(1.9, 1.9, 0.1), p.project(1.8, 2.1, -0.1), 1);
  }
}

void _crane(IsoInk ink, double x, double y) {
  final yellow = MapPalette.buildings[1].$1;
  _stoneQuay(ink, 0, 3.3, 2.7, 4.9);
  final colours = [for (final (s, _) in MapPalette.buildings) s];
  for (final (cx, cy, k) in const [
    (0.45, 3.65, 0),
    (0.45, 4.0, 2),
    (0.85, 3.65, 1),
    (0.45, 4.35, 3),
  ]) {
    ink
      ..box(cx, cy, 0.36, 0.3, 0.16, colours[k])
      ..box(cx, cy, 0.36, 0.3, 0.16, colours[k == 0 ? 1 : 0], z: 0.16);
  }
  for (final (lx, ly) in const [
    (1.6, 3.55),
    (1.6, 4.65),
    (2.25, 3.55),
    (2.25, 4.65),
  ]) {
    ink.box(lx, ly, 0.08, 0.08, 1.4, yellow);
  }
  ink
    ..box(1.92, 3.55, 0.75, 0.1, 0.1, yellow, z: 1.4)
    ..box(1.92, 4.65, 0.75, 0.1, 0.1, yellow, z: 1.4)
    ..box(2.3, 4.1, 2.0, 0.14, 0.12, yellow, z: 1.5)
    ..box(1.75, 4.1, 0.3, 0.3, 0.25, DistrictPalette.white, z: 1.5)
    ..pen.line(ink.p.project(3.0, 4.1, 1.5), ink.p.project(3.0, 4.1, 0.75), 1)
    ..box(3.0, 4.1, 0.36, 0.3, 0.16, colours[2], z: 0.6);
  _ship(ink, 0.4, 2.4, 5.3, PortPalette.cargoHull);
}

void _harbourOffice(IsoInk ink, double x, double y) {
  final p = ink.p;
  ink
    ..box(x, y, 0.8, 0.8, 0.9, DistrictPalette.white)
    ..facade(x, y, 0.8, 0.8, 0, 0.9, DistrictPalette.darkWindow)
    ..box(x, y, 0.36, 0.36, 0.5, DistrictPalette.white, z: 0.9);
  // Its clock, its roof and flag.
  final c = p.project(x + 0.18, y, 1.15);
  ink.pen.fill(
    Path()..addOval(
      Rect.fromCenter(center: c, width: p.tile * 0.1, height: p.tile * 0.14),
    ),
    AppColors.surface,
  );
  ink.pyramid(x, y, 0.36, 0.35, PortPalette.blueRoof, z: 1.4);
  final top = p.project(x, y, 1.75), mast = top - const Offset(0, 16);
  ink.pen
    ..line(top, mast, 1.5)
    ..fill(
      Path()..addPolygon([
        mast,
        mast + const Offset(12, 4),
        mast + const Offset(0, 8),
      ], true),
      AppColors.primary,
    );
}

void _watchtower(IsoInk ink, double x, double y) {
  final p = ink.p;
  for (final (dx, dy) in const [
    (-0.2, -0.2),
    (0.2, -0.2),
    (-0.2, 0.2),
    (0.2, 0.2),
  ]) {
    ink.box(x + dx, y + dy, 0.07, 0.07, 1.5, DistrictPalette.wood);
  }
  if (ink.detailed) {
    ink.pen
      ..line(
        p.project(x - 0.2, y + 0.2, 0.2),
        p.project(x + 0.2, y + 0.2, 1.1),
        1,
      )
      ..line(
        p.project(x + 0.2, y - 0.2, 0.2),
        p.project(x + 0.2, y + 0.2, 1.1),
        1,
      );
  }
  ink
    ..box(x, y, 0.56, 0.56, 0.36, DistrictPalette.wood, z: 1.5)
    ..pyramid(x, y, 0.66, 0.38, MapPalette.roofCoral, z: 1.86);
}

void _lighthouse(IsoInk ink, double x, double y) {
  const z = 0.15, step = 9 / 14;
  ink.box(x, y, 0.8, 0.8, 0.75, PortPalette.rock, z: -0.6);
  for (var i = 0; i < 5; i++) {
    ink.box(
      x,
      y,
      0.5,
      0.5,
      step,
      i.isEven ? MapPalette.lighthouse : MapPalette.lighthouseBand,
      z: z + i * step,
    );
  }
  ink
    ..box(x, y, 0.72, 0.72, 0.21, MapPalette.lighthouse, z: z + 5 * step)
    ..box(x, y, 0.38, 0.38, 0.57, MapPalette.crown, z: z + 5 * step + 0.21)
    ..pyramid(x, y, 0.38, 0.65, MapPalette.roofCoral, z: z + 5 * step + 0.78);
  // Lit: its two beams.
  final p = ink.p;
  final lamp = p.project(x, y, z + 5 * step + 0.5);
  for (final side in const [-1.0, 1.0]) {
    ink.pen.canvas.drawPath(
      Path()..addPolygon([
        lamp,
        lamp + Offset(side * p.tile * 2, -p.tile * 0.5),
        lamp + Offset(side * p.tile * 2, p.tile * 0.2),
      ], true),
      Paint()..color = MapPalette.beam,
    );
  }
}

/// The port on a panel of sea: [centre] (a point of the harbour's grid) at
/// [at] of the panel's size, [tile] px a tile.
class PortPainter extends CustomPainter {
  PortPainter({
    required this.built,
    required this.lines,
    this.tile = 34,
    this.centre = (1.5, 4.0),
    this.at = const Alignment(0.05, -0.05),
  });

  final List<bool> built;
  final Set<String> lines;
  final double tile;
  final (double, double) centre;
  final Alignment at;

  @override
  void paint(Canvas canvas, Size size) {
    final p0 = IsoProjection(tile: tile, unit: tile * 14 / 30);
    final p = p0.shifted(at.alongSize(size) - p0.project(centre.$1, centre.$2));
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    paintPort(
      BlockPen(canvas, AppColors.ink, districtDetailed(p) ? 1.4 : 1.2),
      p,
      size,
      built: built,
      lines: lines,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(PortPainter old) =>
      old.tile != tile ||
      old.centre != centre ||
      old.at != at ||
      !listEquals(old.built, built) ||
      !setEquals(old.lines, lines);
}
