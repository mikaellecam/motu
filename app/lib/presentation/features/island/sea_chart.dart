import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/content.dart';
import '../../../application/learning/sea_chart.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chunky.dart';

/// The chart is drawn on a sheet of this size, scaled to the screen.
const chartSize = Size(358, 400);

/// Where each island lies on the chart: its centre and its half axes.
const chartPlaces = <String, (Offset, double, double)>{
  actionsEtfIsland: (Offset(190, 212), 40, 26),
  tradingIsland: (Offset(104, 92), 30, 20),
  realEstateIsland: (Offset(286, 122), 32, 22),
  cryptoIsland: (Offset(124, 334), 28, 18),
};

/// The port's anchor on the mainland's coast.
const chartPort = Offset(46, 238);

/// The line from the port to each island.
Path chartLine(String island) => switch (island) {
  actionsEtfIsland =>
    Path()
      ..moveTo(56, 238)
      ..cubicTo(90, 252, 118, 240, 146, 228),
  realEstateIsland =>
    Path()
      ..moveTo(54, 228)
      ..cubicTo(110, 150, 200, 84, 256, 116),
  tradingIsland =>
    Path()
      ..moveTo(50, 222)
      ..cubicTo(62, 170, 72, 130, 82, 106),
  _ =>
    Path()
      ..moveTo(54, 248)
      ..cubicTo(70, 290, 84, 316, 96, 326),
};

/// Opens the sea chart over the island [here] is (BRIEF §4.2, M13-5);
/// [onBoard] is called with the island boarded, once the crossing is over.
Future<void> showSeaChart(
  BuildContext context, {
  required String here,
  required ValueChanged<String> onBoard,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.page,
  builder: (_) => SeaChartSheet(here: here, onBoard: onBoard),
);

/// The sea chart in its sheet: the chart, the selected island's card.
class SeaChartSheet extends ConsumerStatefulWidget {
  const SeaChartSheet({super.key, required this.here, required this.onBoard});

  final String here;
  final ValueChanged<String> onBoard;

  @override
  ConsumerState<SeaChartSheet> createState() => _SeaChartSheetState();
}

class _SeaChartSheetState extends ConsumerState<SeaChartSheet>
    with SingleTickerProviderStateMixin {
  /// The island selected: from the port, Actions & ETF; elsewhere, the port.
  late String _selected = widget.here == lesBasesIsland
      ? actionsEtfIsland
      : lesBasesIsland;

  late final _crossing = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _sailing = false;

  @override
  void dispose() {
    _crossing.dispose();
    super.dispose();
  }

  void _board() {
    final to = _selected;
    void land() {
      Navigator.of(context).pop();
      widget.onBoard(to);
    }

    if (MediaQuery.disableAnimationsOf(context)) {
      land();
      return;
    }
    setState(() => _sailing = true);
    _crossing.forward(from: 0).whenComplete(() {
      if (mounted) land();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final islands = ref.watch(seaChartProvider).value ?? const [];
    final byId = {for (final i in islands) i.id: i};
    return PopScope(
      canPop: !_sailing,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenPadding,
          AppSpace.x2,
          AppSpace.screenPadding,
          AppSpace.screenPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.chart_title, style: AppText.title),
                      Text(
                        _sailing ? l10n.chart_sailing : l10n.chart_hint,
                        style: AppText.label.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.chart_close,
                  icon: const Icon(Icons.close),
                  onPressed: _sailing
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.x2),
            Flexible(
              child: AspectRatio(
                aspectRatio: chartSize.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final k = box.maxWidth / chartSize.width;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: ExcludeSemantics(
                            child: CustomPaint(
                              painter: SeaChartPainter(
                                islands: byId,
                                selected: _selected,
                                here: _sailing ? null : widget.here,
                                names: _names(l10n),
                                labels: (
                                  here: l10n.chart_here,
                                  cartouche: l10n.chart_cartouche,
                                  scale: l10n.chart_scale,
                                ),
                              ),
                            ),
                          ),
                        ),
                        for (final id in chartIslands)
                          _target(id, byId[id], k, l10n),
                        if (_sailing)
                          AnimatedBuilder(
                            animation: _crossing,
                            builder: (context, _) => _boat(k),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpace.x3),
            if (byId[_selected] case final island?)
              _Destination(
                island: island,
                here: widget.here == _selected,
                sailing: _sailing,
                onBoard: _board,
              ),
          ],
        ),
      ),
    );
  }

  Map<String, String> _names(AppLocalizations l10n) => {
    lesBasesIsland: l10n.chart_port,
    actionsEtfIsland: l10n.island_actionsEtf,
    tradingIsland: l10n.island_trading,
    realEstateIsland: l10n.island_realEstate,
    cryptoIsland: l10n.island_crypto,
  };

  /// An island's touch target, over it and its label.
  Widget _target(
    String id,
    ChartIsland? island,
    double k,
    AppLocalizations l10n,
  ) {
    final (centre, w, h) = id == lesBasesIsland
        ? (chartPort + const Offset(4, 18), 52.0, 76.0)
        : switch (chartPlaces[id]!) {
            (final c, final a, final b) => (
              c + Offset(0, b * 0.8),
              a * 2.6,
              b * 2.6 + 44,
            ),
          };
    final name = _names(l10n)[id]!;
    final label = switch (island) {
      ChartIsland(state: ChartState.open, :final done, :final total)
          when total > 0 =>
        l10n.map_island_open(name, done, total),
      ChartIsland(state: ChartState.closed, :final waits)
          when waits.isNotEmpty =>
        l10n.map_island_closed(name, waits.first.of(_language)),
      ChartIsland(state: ChartState.open) => name,
      _ => l10n.map_island_locked(name),
    };
    return Positioned(
      left: (centre.dx - w / 2) * k,
      top: (centre.dy - h / 2) * k,
      width: math.max(w * k, AppSpace.minTarget),
      height: math.max(h * k, AppSpace.minTarget),
      child: Semantics(
        button: true,
        selected: _selected == id,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _sailing ? null : () => setState(() => _selected = id),
        ),
      ),
    );
  }

  String get _language => Localizations.localeOf(context).languageCode;

  /// The boat on its crossing: along Actions & ETF's line, out or home.
  Widget _boat(double k) {
    final metric = chartLine(actionsEtfIsland).computeMetrics().first;
    final t = Curves.easeInOut.transform(_crossing.value);
    final along = _selected == lesBasesIsland ? 1 - t : t;
    final at = metric.getTangentForOffset(metric.length * along)!.position;
    return Positioned(
      left: at.dx * k - 15,
      top: at.dy * k - 15,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.ink, width: 2),
        ),
        child: const Icon(Icons.sailing, size: 18, color: AppColors.ink),
      ),
    );
  }
}

/// The island selected: its name, its progress, its next lesson and
/// « Embarquer »; or why it cannot be boarded yet.
class _Destination extends StatelessWidget {
  const _Destination({
    required this.island,
    required this.here,
    required this.sailing,
    required this.onBoard,
  });

  final ChartIsland island;
  final bool here;
  final bool sailing;
  final VoidCallback onBoard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final port = island.id == lesBasesIsland;
    final name = switch (island.id) {
      lesBasesIsland => '${l10n.chart_port} · ${l10n.island_basics}',
      actionsEtfIsland => l10n.island_actionsEtf,
      tradingIsland => l10n.island_trading,
      realEstateIsland => l10n.island_realEstate,
      _ => l10n.island_crypto,
    };
    final open = island.state == ChartState.open;
    final line = switch (island) {
      ChartIsland(state: ChartState.open, next: (final n, final title)) =>
        l10n.chart_next(n, title.of(language)),
      ChartIsland(state: ChartState.open) => l10n.chart_all_done,
      ChartIsland(state: ChartState.soon) => l10n.chart_soon_line,
      ChartIsland(waits: [final one]) => l10n.map_island_opens_after(
        one.of(language),
      ),
      ChartIsland(waits: [final a, final b, ...]) => l10n.chart_opens_after_two(
        a.of(language),
        b.of(language),
      ),
      _ => '',
    };
    final chip = switch (island.state) {
      ChartState.open => l10n.map_island_progress(island.done, island.total),
      ChartState.soon => l10n.chart_soon,
      ChartState.closed => l10n.chart_closed,
    };
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: AppText.titleSmall)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.x2,
                  vertical: AppSpace.x1 / 2,
                ),
                decoration: ShapeDecoration(
                  color: open ? AppColors.progress : AppColors.surface,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: open ? AppColors.ink : MapPalette.lockedInk,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  chip,
                  style: AppText.label.copyWith(
                    color: open ? AppColors.ink : MapPalette.lockedInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.x1),
          Text(line, style: AppText.label.copyWith(color: AppColors.muted)),
          const SizedBox(height: AppSpace.x3),
          ChunkyButton(
            label: here
                ? l10n.chart_you_are_there
                : port
                ? l10n.chart_home
                : l10n.chart_board,
            onPressed: open && !here && !sailing ? onBoard : null,
          ),
        ],
      ),
    );
  }
}

/// A navigator's chart drawn in code: paper and its grid, a compass rose and
/// its rhumb lines, soundings, the mainland's coast and its port, the islands
/// with their depth lines (open in colour, closed hatched grey), the lines
/// from the port, « Tu es ici ».
class SeaChartPainter extends CustomPainter {
  SeaChartPainter({
    required this.islands,
    required this.selected,
    required this.here,
    required this.names,
    required this.labels,
  });

  final Map<String, ChartIsland> islands;
  final String selected;

  /// Where the user is; null while sailing.
  final String? here;
  final Map<String, String> names;
  final ({String here, String cartouche, String scale}) labels;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / chartSize.width);
    _paper(canvas);
    _coast(canvas);
    _soundings(canvas);
    _lines(canvas);
    for (final MapEntry(key: id, value: place) in chartPlaces.entries) {
      _island(canvas, id, place);
    }
    _port(canvas);
    _rose(canvas, const Offset(304, 56));
    _cartouche(canvas);
    if (here case final here?) _here(canvas, here);
    canvas.restore();
  }

  static Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w;

  void _paper(Canvas canvas) {
    final sheet = RRect.fromRectAndRadius(
      const Rect.fromLTWH(1.5, 1.5, 355, 397),
      const Radius.circular(14),
    );
    canvas
      ..drawRRect(sheet, Paint()..color = ChartPalette.paper)
      ..save()
      ..clipRRect(sheet);
    final grid = _stroke(ChartPalette.grid, 1);
    for (final x in const [80.0, 150.0, 220.0, 290.0]) {
      canvas.drawLine(Offset(x, 0), Offset(x, 400), grid);
    }
    for (final y in const [70.0, 140.0, 210.0, 280.0, 350.0]) {
      canvas.drawLine(Offset(0, y), Offset(358, y), grid);
    }
    final rhumb = _stroke(ChartPalette.rhumb, 0.8);
    for (var a = 0; a < 360; a += 45) {
      final t = a * math.pi / 180;
      _dashed(
        canvas,
        Path()
          ..moveTo(304, 56)
          ..lineTo(304 + 420 * math.cos(t), 56 + 420 * math.sin(t)),
        rhumb,
        2,
        4,
      );
    }
    canvas
      ..restore()
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(9, 9, 340, 382),
          const Radius.circular(9),
        ),
        _stroke(ChartPalette.frame, 1),
      )
      ..drawRRect(sheet, _stroke(AppColors.ink, 3));
  }

  void _coast(Canvas canvas) {
    Path coast(double dx) => Path()
      ..moveTo(9, 9)
      ..lineTo(44 + dx, 9)
      ..cubicTo(36 + dx, 60, 54 + dx, 100, 42 + dx, 150)
      ..cubicTo(30 + dx, 200, 30 + dx, 214, 46 + dx, 250)
      ..cubicTo(62 + dx, 286, 36 + dx, 330, 52 + dx, 391)
      ..lineTo(9, 391)
      ..close();
    _dashed(canvas, coast(8), _stroke(ChartPalette.depthLine, 1.2), 4, 3);
    final land = coast(0);
    canvas
      ..drawPath(land, Paint()..color = ChartPalette.land)
      ..save()
      ..clipPath(land);
    final hatch = _stroke(ChartPalette.frame, 1.2);
    for (var d = -400.0; d < 400; d += 6) {
      canvas.drawLine(Offset(d, 0), Offset(d + 400, 400), hatch);
    }
    canvas
      ..restore()
      ..drawPath(land, _stroke(AppColors.ink, 1.8));
  }

  void _soundings(Canvas canvas) {
    for (final (x, y, n) in const [
      (120.0, 160.0, 18), (240.0, 200.0, 24), (300.0, 260.0, 31), //
      (220.0, 300.0, 27), (180.0, 120.0, 12), (250.0, 360.0, 40),
      (70.0, 300.0, 9), (320.0, 190.0, 35), (150.0, 370.0, 22),
      (200.0, 40.0, 15),
    ]) {
      _text(
        canvas,
        '$n',
        Offset(x, y),
        AppText.caption.copyWith(
          fontSize: 10,
          fontStyle: FontStyle.italic,
          color: ChartPalette.sounding,
        ),
        centred: false,
      );
    }
  }

  bool _open(String id) =>
      islands[id]?.state != null && islands[id]!.state != ChartState.closed;

  void _lines(Canvas canvas) {
    for (final id in chartPlaces.keys) {
      if (_open(id)) {
        _dashed(
          canvas,
          chartLine(id),
          _stroke(AppColors.ink, 2.5)..strokeCap = StrokeCap.round,
          7,
          5,
        );
      } else {
        _dashed(
          canvas,
          chartLine(id),
          _stroke(ChartPalette.closedLine, 1.6)..strokeCap = StrokeCap.round,
          1.5,
          5,
        );
      }
    }
  }

  void _island(Canvas canvas, String id, (Offset, double, double) place) {
    final (c, a, b) = place;
    final seed = id.codeUnits.fold(0, (s, u) => s + u);
    for (final k in const [1.6, 1.3]) {
      _dashed(
        canvas,
        _blob(c, a * k, b * k, seed),
        _stroke(ChartPalette.depthLine, 1.1),
        4,
        3,
      );
    }
    final open = islands[id]?.state == ChartState.open;
    if (id == selected) {
      canvas.drawPath(
        _blob(c, a * 1.18, b * 1.18, seed),
        _stroke(AppColors.progress, 5),
      );
    }
    final shape = _blob(c, a, b, seed);
    if (open) {
      canvas.drawPath(shape, Paint()..color = ChartPalette.open);
      // Its blocks, a little street grid.
      for (var i = -2; i <= 2; i++) {
        for (var j = -1; j <= 1; j++) {
          canvas.drawRect(
            Rect.fromLTWH(c.dx + i * 11 - 4, c.dy + j * 9 - 3, 8, 6),
            Paint()..color = ChartPalette.block,
          );
        }
      }
    } else {
      canvas
        ..drawPath(shape, Paint()..color = ChartPalette.closed)
        ..save()
        ..clipPath(shape);
      final hatch = _stroke(ChartPalette.closedHatch, 1.2);
      for (var d = -400.0; d < 400; d += 5) {
        canvas.drawLine(Offset(d, 400), Offset(d + 400, 0), hatch);
      }
      canvas.restore();
    }
    canvas.drawPath(
      shape,
      _stroke(open ? AppColors.ink : ChartPalette.closedEdge, 2),
    );
    final y = c.dy + b * 1.3 + 16;
    _text(
      canvas,
      names[id]!,
      Offset(c.dx, y),
      AppText.bodyStrong.copyWith(
        color: open ? AppColors.ink : MapPalette.lockedInk,
      ),
      halo: true,
    );
    if (islands[id] case ChartIsland(
      state: ChartState.open,
      :final done,
      :final total,
    )) {
      _chip(canvas, '$done/$total', Offset(c.dx, y + 22));
    }
  }

  void _port(Canvas canvas) {
    canvas
      ..drawCircle(chartPort, 13, Paint()..color = AppColors.surface)
      ..drawCircle(chartPort, 13, _stroke(AppColors.ink, 2.5));
    final anchor = _stroke(AppColors.ink, 2)..strokeCap = StrokeCap.round;
    canvas
      ..drawCircle(chartPort + const Offset(0, -6), 2, anchor)
      ..drawLine(
        chartPort + const Offset(0, -4),
        chartPort + const Offset(0, 7),
        anchor,
      )
      ..drawLine(
        chartPort + const Offset(-3.5, -1),
        chartPort + const Offset(3.5, -1),
        anchor,
      )
      ..drawArc(
        Rect.fromCircle(center: chartPort + const Offset(0, 1), radius: 7),
        0,
        math.pi,
        false,
        anchor,
      );
    final y = chartPort.dy + 30;
    _text(
      canvas,
      names[lesBasesIsland]!,
      Offset(chartPort.dx + 18, y),
      AppText.bodyStrong,
      halo: true,
    );
    if (islands[lesBasesIsland] case ChartIsland(:final done, :final total)
        when total > 0) {
      _chip(canvas, '$done/$total', Offset(chartPort.dx + 18, y + 22));
    }
  }

  void _rose(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 17, _stroke(ChartPalette.frame, 1));
    final star = Path();
    for (var i = 0; i < 16; i++) {
      final r = i % 4 == 0 ? 24.0 : (i.isEven ? 11.0 : 7.0);
      final t = (i * 22.5 - 90) * math.pi / 180;
      final p = c + Offset(r * math.cos(t), r * math.sin(t));
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas
      ..drawPath(star, Paint()..color = AppColors.surface)
      ..drawPath(star, _stroke(AppColors.ink, 1.5))
      ..drawPath(
        Path()..addPolygon([
          c + const Offset(0, -24),
          c + const Offset(4, 0),
          c + const Offset(-4, 0),
        ], true),
        Paint()..color = AppColors.ink,
      );
    _text(canvas, 'N', c + const Offset(0, -33), AppText.bodyStrong);
  }

  void _cartouche(Canvas canvas) {
    final box = RRect.fromRectAndRadius(
      const Rect.fromLTWH(232, 352, 108, 30),
      const Radius.circular(6),
    );
    canvas
      ..drawRRect(box, Paint()..color = AppColors.surface)
      ..drawRRect(box, _stroke(AppColors.ink, 1.5));
    _text(canvas, labels.cartouche, box.center, AppText.label);
    canvas
      ..drawRect(
        const Rect.fromLTWH(232, 334, 27, 5),
        Paint()..color = AppColors.ink,
      )
      ..drawRect(
        const Rect.fromLTWH(259, 334, 27, 5),
        Paint()..color = AppColors.surface,
      )
      ..drawRect(
        const Rect.fromLTWH(259, 334, 27, 5),
        _stroke(AppColors.ink, 1),
      );
    _text(
      canvas,
      labels.scale,
      const Offset(292, 330),
      AppText.caption.copyWith(fontSize: 10, color: AppColors.muted),
      centred: false,
    );
  }

  void _here(Canvas canvas, String id) {
    final at = id == lesBasesIsland
        ? chartPort + const Offset(-20, -38)
        : switch (chartPlaces[id]) {
            (final c, _, final b)? => c + Offset(-26, -b * 1.3 - 30),
            null => null,
          };
    if (at == null) return;
    final style = AppText.caption.copyWith(
      color: AppColors.surface,
      fontWeight: FontWeight.w700,
    );
    final tp = TextPainter(
      text: TextSpan(text: labels.here, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final pill = RRect.fromRectAndRadius(
      Rect.fromLTWH(at.dx, at.dy, tp.width + 16, tp.height + 4),
      const Radius.circular(12),
    );
    canvas.drawRRect(pill, Paint()..color = AppColors.ink);
    tp.paint(canvas, at + const Offset(8, 2));
  }

  void _chip(Canvas canvas, String text, Offset centre) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppText.label.copyWith(color: AppColors.ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: centre, width: tp.width + 16, height: 22),
      const Radius.circular(11),
    );
    canvas
      ..drawRRect(pill, Paint()..color = AppColors.progress)
      ..drawRRect(pill, _stroke(AppColors.ink, 2));
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  static void _text(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle style, {
    bool centred = true,
    bool halo = false,
  }) {
    // A style with no colour of its own paints in ink.
    style = style.copyWith(color: style.color ?? AppColors.ink);
    if (halo) {
      final back = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(
            foreground: _stroke(ChartPalette.paper, 4)
              ..strokeJoin = StrokeJoin.round,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      back.paint(
        canvas,
        centred ? at - Offset(back.width / 2, back.height / 2) : at,
      );
    }
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centred ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  /// A smooth closed shape round [c], each island its own from [seed].
  static Path _blob(Offset c, double rx, double ry, int seed) {
    const n = 9;
    final rnd = math.Random(seed);
    final rs = [for (var i = 0; i < n; i++) 0.8 + 0.35 * rnd.nextDouble()];
    final pts = [
      for (var i = 0; i < n; i++)
        c +
            Offset(
              rx * rs[i] * math.cos(2 * math.pi * i / n),
              ry * rs[i] * math.sin(2 * math.pi * i / n),
            ),
    ];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = pts[(i - 1 + n) % n], p1 = pts[i];
      final p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path..close();
  }

  static void _dashed(
    Canvas canvas,
    Path path,
    Paint paint,
    double on,
    double off,
  ) {
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += on + off) {
        canvas.drawPath(m.extractPath(d, math.min(d + on, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(SeaChartPainter old) =>
      old.selected != selected ||
      old.here != here ||
      old.islands != islands ||
      old.names != names;
}
