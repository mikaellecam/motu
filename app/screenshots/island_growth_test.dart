import 'package:finance_companion/core/theme/app_theme.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:flutter/material.dart';

import 'screenshot.dart';

// Actions & ETF as the lessons green it (M9-19): 0, 2, 5, 9 and 12 lessons
// of 12, no wallet on it.

void main() {
  final island = archipelago.firstWhere((i) => i.id == IslandId.actionsEtf);
  screenshot(
    'm9-19-island-growth',
    Material(
      color: AppColors.sea,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final done in [0, 2, 5, 9, 12])
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    '$done / 12',
                    textAlign: TextAlign.center,
                    style: AppText.titleSmall,
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 165,
                    child: CustomPaint(
                      painter: ArchipelagoPainter(
                        only: island,
                        grown: done / 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
    size: const Size(390, 860),
  );
}
