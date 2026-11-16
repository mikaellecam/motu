import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:finance_companion/presentation/features/map/district.dart';
import 'package:finance_companion/presentation/features/map/iso.dart';
import 'package:flutter/material.dart';

import 'screenshot.dart';

// Actions & ETF's district (M13-2) zoomed in, as the island up close will
// show it (M13-4): no lesson done, half of them, all twelve.

void main() {
  for (final done in [0, 6, 12]) {
    screenshot(
      'm13-2-district-$done',
      ColoredBox(
        color: AppColors.sea,
        child: CustomPaint(painter: _District(done), size: Size.infinite),
      ),
      size: const Size(640, 400),
    );
  }
}

class _District extends CustomPainter {
  const _District(this.done);

  final int done;

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 64.0;
    paintDistrict(
      BlockPen(canvas, AppColors.ink, 1.4),
      IsoProjection(
        tile: tile,
        unit: tile * 18 / 34,
        origin: Offset(size.width * 0.58, size.height * 0.12),
      ),
      archipelago.firstWhere((i) => i.id == IslandId.actionsEtf).tiles,
      grown: [for (var i = 0; i < 12; i++) i < done],
      ferry: true,
    );
  }

  @override
  bool shouldRepaint(_District old) => old.done != done;
}
