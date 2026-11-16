import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/presentation/features/map/port.dart';
import 'package:flutter/material.dart';

import 'screenshot.dart';

// Les bases' port (M13-3) zoomed in, as the island up close will show it
// (M13-4): at the start, then after 3, 5, 6 and all 9 of its lessons, the
// sea lines its lessons opened leaving the harbour.

void main() {
  for (final (done, lines) in [
    (0, <String>{}),
    (3, <String>{}),
    (5, {actionsEtfIsland}),
    (6, {actionsEtfIsland, realEstateIsland}),
    (9, {actionsEtfIsland, realEstateIsland, cryptoIsland}),
  ]) {
    screenshot(
      'm13-3-port-$done',
      ColoredBox(
        color: AppColors.sea,
        child: CustomPaint(
          painter: PortPainter(
            built: [for (var i = 0; i < 9; i++) i < done],
            lines: lines,
            tile: 64,
            centre: (1.4, 3.6),
            at: const Alignment(-0.05, 0.1),
          ),
          size: Size.infinite,
        ),
      ),
      size: const Size(640, 480),
    );
  }
}
