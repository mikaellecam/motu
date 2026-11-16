import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../map/archipelago.dart';
import '../map/district.dart';
import '../map/iso.dart';
import '../map/port.dart';

/// An island up close (BRIEF §4.3, M13-4): its picture at full detail, how
/// big it is, and where each lesson's marker stands on it, in its own px.
final class IslandWorld {
  const IslandWorld({
    required this.size,
    required this.anchors,
    required this.paint,
    required this.grown,
    this.ferry,
  });

  final Size size;

  /// Its ferry at its pier, once its line is open: touching it opens the sea
  /// chart, and a crossing lands there (M13-5).
  final Offset? ferry;

  /// How far each lesson's building or part stands, 0 to 1, in its lessons'
  /// order.
  final List<double> grown;

  /// Each lesson's marker, in the order of its lessons.
  final List<Offset> anchors;

  /// Paints it on a canvas of the given size, the world centred on it.
  final void Function(Canvas canvas, Size canvasSize) paint;
}

/// Actions & ETF's district, 120 px a tile, its buildings at [grown] (0
/// plain, 1 grown, eased between), its ferry at its pier when [ferry].
IslandWorld districtWorld(List<double> grown, {required bool ferry}) {
  const tile = 120.0, unit = tile * 18 / 34;
  // Room for the ferry left, the island's right corner, the spire's crown
  // above and the sea wall below.
  const origin = Offset(tile / 2 * 9.1, unit * 7.6);
  const size = Size(tile / 2 * 16.7, tile / 4 * 15 + unit * 7.6 + 70);
  const p = IsoProjection(tile: tile, unit: unit, origin: origin);
  final tiles = archipelago
      .firstWhere((i) => i.id == IslandId.actionsEtf)
      .tiles;
  return IslandWorld(
    size: size,
    grown: grown,
    ferry: ferry ? p.project(-2.1, 5.58, 0.1) : null,
    anchors: [
      for (final (i, b) in districtBuildings.indexed)
        if (b.anchor(i < grown.length ? grown[i] : 0) case (
          :final x,
          :final y,
          :final z,
        ))
          p.project(x, y, z),
    ],
    paint: (canvas, canvasSize) {
      final at = p.shifted(_centring(size, canvasSize));
      _waves(canvas, canvasSize);
      paintDistrict(
        BlockPen(canvas, AppColors.ink, 1.5),
        at,
        tiles,
        grown: grown,
        ferry: ferry,
      );
    },
  );
}

/// Les bases' port, 100 px a tile, its parts [built], its sea [lines] open.
IslandWorld portWorld(List<bool> built, {required Set<String> lines}) {
  const tile = 100.0, unit = tile * 14 / 30;
  const origin = Offset(tile / 2 * 13.6, 425);
  const size = Size(tile / 2 * 20.8, 870);
  const p = IsoProjection(tile: tile, unit: unit, origin: origin);
  return IslandWorld(
    size: size,
    grown: [for (final b in built) b ? 1.0 : 0.0],
    // Its ferry quay is Les bases' fifth part.
    ferry: built.length > 4 && built[4] ? p.project(1.15, 2.3, 0.1) : null,
    anchors: [
      for (final (i, part) in portParts.indexed)
        if (part.anchor(built: i < built.length && built[i]) case (
          :final x,
          :final y,
          :final z,
        ))
          p.project(x, y, z),
    ],
    paint: (canvas, canvasSize) {
      final at = p.shifted(_centring(size, canvasSize));
      _waves(canvas, canvasSize);
      paintPort(
        BlockPen(canvas, AppColors.ink, 1.4),
        at,
        canvasSize,
        built: built,
        lines: lines,
      );
    },
  );
}

Offset _centring(Size world, Size canvas) => Offset(
  (canvas.width - world.width) / 2,
  (canvas.height - world.height) / 2,
);

void _waves(Canvas canvas, Size size) {
  for (var i = 0; i < 9; i++) {
    final o = Offset(
      size.width * ((i * 0.37 + 0.11) % 1),
      size.height * ((i * 0.61 + 0.07) % 1),
    );
    canvas.drawPath(ArchipelagoPainter.ripple(o), ArchipelagoPainter.wavePaint);
  }
}

/// Where a lesson stands, as its marker shows it.
enum MarkerKind {
  /// Done: a navy disc with a check.
  done,

  /// The lesson to do: a gold pin that pulses.
  current,

  /// Any other: a small white dot.
  later,
}

/// A lesson's marker on the island.
final class Marker {
  const Marker(this.kind, this.label);
  final MarkerKind kind;

  /// What a screen reader says of it.
  final String label;
}

/// The island up close: drag pans it, pinch zooms it, within bounds (it never
/// leaves the screen; zooming out stops when it fits whole). Its markers keep
/// their size whatever the zoom. Opens framed on [focus]; [glideTo] moves the
/// view to a marker.
class IslandScene extends StatefulWidget {
  const IslandScene({
    super.key,
    required this.world,
    required this.markers,
    required this.onMarker,
    this.focus,
    this.onFerry,
    this.arriving = false,
  });

  /// Touching the ferry: the sea chart (M13-5).
  final VoidCallback? onFerry;

  /// Just landed from the sea: the view opens on the pier, then glides to
  /// [focus].
  final bool arriving;

  final IslandWorld world;
  final List<Marker> markers;
  final ValueChanged<int> onMarker;

  /// The marker the view opens on.
  final int? focus;

  /// The scale the view opens at, and glides to a marker at.
  static const closeUp = 0.7;

  /// Where on the scene a framed marker sits: across the middle, above the
  /// card at the bottom.
  static const framed = Alignment(0, -0.3);

  @override
  State<IslandScene> createState() => IslandSceneState();
}

class IslandSceneState extends State<IslandScene>
    with TickerProviderStateMixin {
  final _view = TransformationController();
  late final _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  Size? _viewport;
  Size _canvas = Size.zero;
  double _minScale = 0.1;
  Animation<Matrix4>? _glideTo;

  @override
  void initState() {
    super.initState();
    _glide.addListener(() {
      if (_glideTo case final to?) _view.value = to.value;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(IslandScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  /// The gold pin pulses while there is one, unless animations are off.
  void _syncPulse() {
    final pin = widget.markers.any((m) => m.kind == MarkerKind.current);
    if (!pin || MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _view.dispose();
    _glide.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Offset get _offset => _centring(widget.world.size, _canvas);

  /// The view at [scale] with marker [index] where [IslandScene.framed]
  /// says, kept within bounds.
  Matrix4 _framing(int index, double scale) =>
      _framingPoint(widget.world.anchors[index], scale);

  Matrix4 _framingPoint(Offset worldPoint, double scale) {
    final viewport = _viewport!;
    final s = scale.clamp(_minScale, 1.0).toDouble();
    final point = worldPoint + _offset;
    final target = IslandScene.framed.alongSize(viewport);
    final double x = (target.dx - point.dx * s).clamp(
      math.min(0.0, viewport.width - _canvas.width * s),
      0.0,
    );
    final double y = (target.dy - point.dy * s).clamp(
      math.min(0.0, viewport.height - _canvas.height * s),
      0.0,
    );
    return Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  /// Moves the view to marker [index], gliding unless animations are off.
  void glideTo(int index) {
    if (_viewport == null || index >= widget.world.anchors.length) return;
    final to = _framing(index, IslandScene.closeUp);
    if (MediaQuery.disableAnimationsOf(context)) {
      _view.value = to;
      return;
    }
    _glideTo = Matrix4Tween(
      begin: _view.value.clone(),
      end: to,
    ).animate(CurvedAnimation(parent: _glide, curve: Curves.easeInOut));
    _glide.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final viewport = box.biggest;
        final world = widget.world.size;
        _minScale = math.min(
          1.0,
          math.min(
            viewport.width / world.width,
            viewport.height / world.height,
          ),
        );
        // The picture padded with sea so that, zoomed all the way out, it
        // still covers the screen.
        _canvas = Size(
          math.max(world.width, viewport.width / _minScale),
          math.max(world.height, viewport.height / _minScale),
        );
        if (_viewport != viewport) {
          final first = _viewport == null;
          _viewport = viewport;
          if (first) {
            final pier = widget.world.ferry;
            final focus = widget.focus;
            _view.value = widget.arriving && pier != null
                ? _framingPoint(pier, IslandScene.closeUp)
                : focus == null
                ? _framing(0, _minScale)
                : _framing(focus, IslandScene.closeUp);
            if (widget.arriving && pier != null && focus != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) glideTo(focus);
              });
            }
          }
        }
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _view,
                constrained: false,
                boundaryMargin: EdgeInsets.zero,
                minScale: _minScale,
                maxScale: 1,
                onInteractionStart: (_) => _glide.stop(),
                child: RepaintBoundary(
                  child: SizedBox.fromSize(
                    size: _canvas,
                    child: ExcludeSemantics(
                      child: CustomPaint(painter: _WorldPainter(widget.world)),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _view,
              builder: (context, _) => Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if ((widget.world.ferry, widget.onFerry) case (
                    final ferry?,
                    final onFerry?,
                  ))
                    _ferry(ferry, onFerry),
                  for (final (i, m) in widget.markers.indexed)
                    if (i < widget.world.anchors.length) _place(i, m),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// The ferry's touch target; the « Naviguer » button speaks for it.
  Widget _ferry(Offset ferry, VoidCallback onTap) {
    final at = MatrixUtils.transformPoint(_view.value, ferry + _offset);
    const size = 64.0;
    return Positioned(
      left: at.dx - size / 2,
      top: at.dy - size / 2,
      width: size,
      height: size,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const ValueKey('ferry'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _place(int i, Marker m) {
    final at = MatrixUtils.transformPoint(
      _view.value,
      widget.world.anchors[i] + _offset,
    );
    const target = AppSpace.minTarget;
    // The pin's tip on the point; the others centred on it.
    final lift = m.kind == MarkerKind.current ? 24.0 : 0.0;
    return Positioned(
      left: at.dx - target / 2,
      top: at.dy - target / 2 - lift,
      width: target,
      height: target,
      child: Semantics(
        button: true,
        label: m.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onMarker(i),
          child: Center(
            child: switch (m.kind) {
              MarkerKind.done => const _Done(),
              MarkerKind.current => _Pin(pulse: _pulse),
              MarkerKind.later => const _Later(),
            },
          ),
        ),
      ),
    );
  }
}

class _WorldPainter extends CustomPainter {
  _WorldPainter(this.world);

  final IslandWorld world;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    world.paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WorldPainter old) => old.world != world;
}

class _Done extends StatelessWidget {
  const _Done();

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      color: AppColors.ink,
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.surface, width: 2.5),
    ),
    child: const Icon(Icons.check, size: 15, color: AppColors.surface),
  );
}

class _Later extends StatelessWidget {
  const _Later();

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      color: AppColors.surface,
      shape: BoxShape.circle,
      border: Border.all(color: MapPalette.lockedInk, width: 3),
    ),
  );
}

/// The lesson to do: a gold pin, its ring pulsing out from its head.
class _Pin extends StatelessWidget {
  const _Pin({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 48,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        AnimatedBuilder(
          animation: pulse,
          builder: (context, _) => Positioned(
            top: 3,
            child: Opacity(
              opacity: pulse.isAnimating ? 1 - pulse.value : 0,
              child: Transform.scale(
                scale: 0.8 + pulse.value * 1.1,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.progress, width: 3),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Positioned.fill(child: CustomPaint(painter: _PinPainter())),
      ],
    ),
  );
}

class _PinPainter extends CustomPainter {
  const _PinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final head = Offset(w / 2, w * 0.45);
    final r = w * 0.38;
    final pin = Path()
      ..moveTo(w / 2, h - 2)
      ..quadraticBezierTo(
        head.dx - r * 0.9,
        head.dy + r * 0.9,
        head.dx - r,
        head.dy,
      )
      ..arcToPoint(Offset(head.dx + r, head.dy), radius: Radius.circular(r))
      ..quadraticBezierTo(head.dx + r * 0.9, head.dy + r * 0.9, w / 2, h - 2)
      ..close();
    canvas
      ..drawPath(pin, Paint()..color = AppColors.progress)
      ..drawPath(
        pin,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawCircle(head, r * 0.4, Paint()..color = AppColors.surface)
      ..drawCircle(
        head,
        r * 0.4,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
  }

  @override
  bool shouldRepaint(_PinPainter oldDelegate) => false;
}
