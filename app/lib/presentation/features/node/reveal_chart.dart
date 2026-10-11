import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';

/// A line to draw. x and y are plot positions only: the figures shown next
/// to the chart come from the decimals, never from these doubles.
class ChartLine {
  const ChartLine(this.points, this.color);
  final List<(double, double)> points;
  final Color color;
}

/// The colors of a lesson's curves, in drawing order (BRIEF §10.2: the main
/// line in primary, the one it is compared with in ink).
const lineColors = [AppColors.primary, AppColors.ink, AppColors.muted];

/// How long a lesson's curves take to draw, and its figures to count.
const revealDuration = Duration(milliseconds: 1600);
const revealCurve = Curves.easeInOut;

/// Lines that draw themselves from left to right when [animate] (BRIEF
/// §10.5, hand-coded animation 3: a `Tween<double>` over each path's
/// `PathMetric`). With reduced motion, or [animate] off, they show whole.
class RevealChart extends StatefulWidget {
  const RevealChart({
    super.key,
    required this.lines,
    required this.semanticsLabel,
    this.animate = true,
    this.height = 200,
  });

  final List<ChartLine> lines;
  final String semanticsLabel;
  final bool animate;
  final double height;

  @override
  State<RevealChart> createState() => _RevealChartState();
}

class _RevealChartState extends State<RevealChart>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: revealDuration,
  );
  late final _progress = Tween<double>(
    begin: 0,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: revealCurve));
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: widget.semanticsLabel,
    child: SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, _) =>
            CustomPaint(painter: LinesPainter(widget.lines, _progress.value)),
      ),
    ),
  );
}

/// Draws [lines] on a shared scale, each cut to [progress] of its length,
/// with a dot where it has got to, over the level the first line starts
/// from.
class LinesPainter extends CustomPainter {
  LinesPainter(this.lines, this.progress);

  final List<ChartLine> lines;
  final double progress;

  static const _inset = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [for (final l in lines) ...l.points];
    if (points.isEmpty) return;
    var (minX, maxX) = (points.first.$1, points.first.$1);
    var (minY, maxY) = (points.first.$2, points.first.$2);
    for (final (x, y) in points) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final spanX = maxX - minX == 0 ? 1.0 : maxX - minX;
    final spanY = maxY - minY == 0 ? 1.0 : maxY - minY;
    final width = size.width - 2 * _inset;
    final height = size.height - 2 * _inset;
    Offset at((double, double) p) => Offset(
      _inset + (p.$1 - minX) / spanX * width,
      _inset + (1 - (p.$2 - minY) / spanY) * height,
    );

    // Where the money started.
    if (lines.first.points.isNotEmpty) {
      final start = at(lines.first.points.first).dy;
      canvas.drawLine(
        Offset(0, start),
        Offset(size.width, start),
        Paint()
          ..color = AppColors.line
          ..strokeWidth = 1,
      );
    }

    for (final line in lines.reversed) {
      if (line.points.isEmpty) continue;
      final path = Path()
        ..moveTo(at(line.points.first).dx, at(line.points.first).dy);
      for (final p in line.points.skip(1)) {
        path.lineTo(at(p).dx, at(p).dy);
      }
      final paint = Paint()
        ..color = line.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      for (final metric in path.computeMetrics()) {
        final length = metric.length * progress;
        canvas.drawPath(metric.extractPath(0, length), paint);
        final tip = metric.getTangentForOffset(length)?.position;
        if (tip != null && progress > 0) {
          canvas.drawCircle(tip, 4, Paint()..color = line.color);
        }
      }
      if (line.points.length == 1) {
        canvas.drawCircle(
          at(line.points.first),
          4,
          Paint()..color = line.color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(LinesPainter old) =>
      old.progress != progress || old.lines != lines;
}

/// Figures counting from [from] to [to] as a curve draws (BRIEF §10.5:
/// value counters): [builder] gets the value of each frame, [to] itself on
/// the last; [to] at once with reduced motion. Screen readers hear
/// [semanticsLabel], the end figures, all along.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.from,
    required this.to,
    required this.semanticsLabel,
    required this.builder,
  });

  final Decimal from;
  final Decimal to;
  final String semanticsLabel;
  final Widget Function(BuildContext context, Decimal value, bool done) builder;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: still ? 1 : 0, end: 1),
        duration: still ? Duration.zero : revealDuration,
        curve: revealCurve,
        builder: (context, t, _) => t >= 1
            ? builder(context, to, true)
            // Display only: the figures shown are the decimal ones at the end.
            : builder(
                context,
                from +
                    (to - from) *
                        Decimal.parse(t.clamp(0, 1).toStringAsFixed(4)),
                false,
              ),
      ),
    );
  }
}

/// One row under a chart: the line's color (none for a row that is not a
/// line), its name, where it ended and, when given, its signed change in a
/// gain or loss color. With [count], the end value counts up from where the
/// line started.
class ChartLegendRow extends StatelessWidget {
  const ChartLegendRow({
    super.key,
    this.color,
    required this.label,
    required this.value,
    this.change,
    this.changeColor,
    this.count,
  });

  final Color? color;
  final String label;
  final String value;
  final String? change;
  final Color? changeColor;

  /// Counts the value up from where the line started, and the change with
  /// it (the value over that start, less one), [percent] formatting it.
  final ({
    Decimal from,
    Decimal to,
    String Function(Decimal value) format,
    String Function(Decimal ratio) percent,
  })?
  count;

  /// The end value, then the change in its gain or loss colour.
  Widget figures(String value, String? change, TextTheme text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: AppText.figure.copyWith(color: AppColors.ink)),
      if (change != null) ...[
        const SizedBox(width: AppSpace.x2),
        Text(change, style: text.bodyMedium?.copyWith(color: changeColor)),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.x1),
      child: Row(
        children: [
          if (color != null) ...[
            ExcludeSemantics(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.x2),
          ],
          Expanded(child: Text(label, style: text.bodyMedium)),
          if (count case (
            :final from,
            :final to,
            :final format,
            :final percent,
          ))
            CountUp(
              from: from,
              to: to,
              semanticsLabel: [value, ?change].join(' '),
              builder: (context, v, done) => figures(
                done ? value : format(v),
                change == null
                    ? null
                    : done || from == Decimal.zero
                    ? change
                    : percent(ratio(v, from) - Decimal.one),
                text,
              ),
            )
          else
            figures(value, change, text),
        ],
      ),
    );
  }
}

/// A lesson value in [currency] (an ISO code), or a plain index (base 100)
/// without one.
String formatValue(Formats formats, Decimal value, String? currency) =>
    switch (Currency.values.where((c) => c.code == currency).firstOrNull) {
      final c? => formats.amount(value, c),
      null when currency != null => '${formats.number(value)} $currency',
      null => formats.number(value, decimals: 1),
    };
