import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/tokens.dart';
import '../../../domain/learning/path.dart';
import '../map/archipelago.dart';
import '../map/iso.dart';

/// The island path's grid (BRIEF §4.3, the art direction's « stepping
/// islets »): the island art's iso grid, each lesson on an identical 2×2
/// islet, the next one 8 tiles along an iso axis. The path zig-zags one
/// constant step down and two across.
abstract final class IsletGrid {
  /// A tile's width and a block's depth, in px.
  static const tile = 52.0;
  static const unit = 24.0;

  /// Tiles from one islet to the next.
  static const span = 8.0;

  /// Down from one islet to the next; each column is as far from the middle.
  static const step = tile / 4 * span;

  /// From an islet's top centre down to its base.
  static const base = tile / 2 + unit;

  /// From an islet's top centre up to its lesson's bubble, and to the
  /// current lesson's bigger one.
  static const lift = 16.0;
  static const currentLift = 26.0;
}

/// Lessons [first] to [end] (exclusive) of a path whose lessons stand as
/// [states]: the screen cuts the path in two runs round the current lesson's
/// card. The first islet's top centre lies [top] down; [bottom] is the room
/// under the last one's base.
@immutable
final class IsletRun {
  const IsletRun(
    this.states, {
    required this.first,
    required this.end,
    required this.top,
    required this.bottom,
  });

  final List<NodeState> states;
  final int first;
  final int end;
  final double top;
  final double bottom;

  double get height =>
      top + (end - 1 - first) * IsletGrid.step + IsletGrid.base + bottom;

  /// Lesson [i]'s islet, its top centre, in a run [width] wide: the even
  /// lessons in the left column.
  Offset centre(int i, double width) => Offset(
    width / 2 + (i.isEven ? -IsletGrid.step : IsletGrid.step),
    top + (i - first) * IsletGrid.step,
  );

  bool locked(int i) => states[i] == NodeState.locked;

  @override
  bool operator ==(Object other) =>
      other is IsletRun &&
      listEquals(other.states, states) &&
      (other.first, other.end, other.top, other.bottom) ==
          (first, end, top, bottom);

  @override
  int get hashCode => Object.hash(Object.hashAll(states), first, end, top);
}

/// Paints a run: each islet in its shallow water with a pair of ripples on
/// its outer side, a plank bridge from each lesson done to the next, and a
/// plank route on the water for the rest. The routes into and out of the
/// card run under it, cut at the run's edges.
class IsletRunPainter extends CustomPainter {
  IsletRunPainter(this.run);

  final IsletRun run;

  // Along a bridge, in tiles: where it leaves its islet, the plank pitch, a
  // plank and a route mark; across it, half its width.
  static const _start = 2.0;
  static const _pitch = 0.5;
  static const _plank = 0.4;
  static const _mark = 0.26;
  static const _half = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    final w = size.width;
    for (var i = run.first; i < run.end; i++) {
      final c = run.centre(i, w);
      canvas.drawOval(
        Rect.fromCenter(
          center: c + const Offset(0, 18),
          width: 136,
          height: 76,
        ),
        Paint()..color = run.locked(i) ? MapPalette.halo : MapPalette.haloOpen,
      );
      for (final (dx, dy) in const [(72.0, 48.0), (58.0, 60.0)]) {
        final x = i.isEven ? c.dx - dx : c.dx + dx - 20;
        canvas.drawPath(
          ArchipelagoPainter.ripple(Offset(x, c.dy + dy)),
          ArchipelagoPainter.wavePaint,
        );
      }
    }
    // Bridges from the lesson above the run (behind the card) to the one
    // after it (on past the card).
    final from = run.first > 0 ? run.first - 1 : 0;
    final to = run.end < run.states.length ? run.end : run.end - 1;
    for (var i = from; i < to; i++) {
      if (run.states[i] != NodeState.done) _route(canvas, i, w);
    }
    // Back to front. The cut follows the current lesson, never done, so no
    // bridge built crosses it.
    for (var i = run.first; i < run.end; i++) {
      final locked = run.locked(i);
      final pen = locked
          ? BlockPen(canvas, MapPalette.lockedInk, 1.1)
          : BlockPen(canvas, AppColors.ink, 1.3);
      ArchipelagoPainter.ground(
        pen,
        _projection(i, w),
        locked ? const ['aa', 'aa'] : const ['SS', 'SS'],
        locked: locked,
      );
      if (i < to && run.states[i] == NodeState.done) _bridge(canvas, i, w);
    }
    canvas.restore();
  }

  /// Lesson [i]'s islet grid: tile (0, 0)'s back corner half a tile above
  /// the islet's top centre.
  IsoProjection _projection(int i, double width) => IsoProjection(
    tile: IsletGrid.tile,
    unit: IsletGrid.unit,
    origin: run.centre(i, width) - const Offset(0, IsletGrid.tile / 2),
  );

  /// From lesson [i] to the next, from [a] to [a] + [length] along the
  /// bridge (+x from the left column, +y from the right), from [b0] to [b1]
  /// across it.
  static Rect _span(int i, double a, double length, double b0, double b1) =>
      i.isEven
      ? Rect.fromLTRB(a, b0, a + length, b1)
      : Rect.fromLTRB(b0, a, b1, a + length);

  Iterable<double> get _plankStarts sync* {
    final count = ((IsletGrid.span - _start) / _pitch).round();
    for (var n = 0; n < count; n++) {
      yield _start + n * _pitch;
    }
  }

  void _bridge(Canvas canvas, int i, double width) {
    final p = _projection(i, width);
    final pen = BlockPen(canvas, AppColors.ink, 1.1);
    for (final a in const [_start + 0.6, IsletGrid.span - 0.6]) {
      final r = _span(i, a - 0.07, 0.14, 1 + _half - 0.14, 1 + _half);
      final [left, right, _] = boxFacets(
        p,
        r.left,
        r.top,
        r.width,
        r.height,
        0.8,
        z: -1,
      );
      pen
        ..fill(left.path, MapPalette.trunk.left)
        ..fill(right.path, MapPalette.trunk.right);
    }
    for (final a in _plankStarts) {
      final r = _span(
        i,
        a + (_pitch - _plank) / 2,
        _plank,
        1 - _half,
        1 + _half,
      );
      pen.block(
        boxFacets(p, r.left, r.top, r.width, r.height, 0.2, z: -0.2),
        MapPalette.plank,
      );
    }
  }

  void _route(Canvas canvas, int i, double width) {
    final p = _projection(i, width);
    final paint = Paint()..color = MapPalette.route;
    for (final a in _plankStarts) {
      final r = _span(i, a + (_pitch - _mark) / 2, _mark, 1 - _half, 1 + _half);
      canvas.drawPath(
        Path()..addPolygon([
          p.project(r.left, r.top),
          p.project(r.right, r.top),
          p.project(r.right, r.bottom),
          p.project(r.left, r.bottom),
        ], true),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(IsletRunPainter old) => old.run != run;
}
