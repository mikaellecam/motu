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
    duration: const Duration(milliseconds: 1600),
  );
  late final _progress = Tween<double>(
    begin: 0,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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

/// One row under a chart: the line's color (none for a row that is not a
/// line), its name, where it ended and, when given, its signed change in a
/// gain or loss color.
class ChartLegendRow extends StatelessWidget {
  const ChartLegendRow({
    super.key,
    this.color,
    required this.label,
    required this.value,
    this.change,
    this.changeColor,
  });

  final Color? color;
  final String label;
  final String value;
  final String? change;
  final Color? changeColor;

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
          Text(value, style: AppText.figure.copyWith(color: AppColors.ink)),
          if (change != null) ...[
            const SizedBox(width: AppSpace.x2),
            Text(change!, style: text.bodyMedium?.copyWith(color: changeColor)),
          ],
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
