import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/presentation/features/island/island_scene.dart';
import 'package:flutter/material.dart';

import 'screenshot.dart';

// A lesson just done (M13-17), half-way through the run: its building rising
// into its ghost. Actions & ETF's seventh, the port's crane.

void main() {
  screenshot(
    'm13-17-district-rising',
    _World(
      districtWorld(
        [for (var i = 0; i < 12; i++) i < 6 ? 1.0 : (i == 6 ? 0.5 : 0.0)],
        ferry: true,
        fading: const {6: 1},
      ),
    ),
    size: const Size(390, 700),
  );
  screenshot(
    'm13-17-port-rising',
    _World(
      portWorld(
        [for (var i = 0; i < 9; i++) i < 6],
        lines: const {actionsEtfIsland},
        rising: const {5: 0.5},
        fading: const {5: 1},
      ),
    ),
    size: const Size(390, 700),
  );
}

class _World extends StatelessWidget {
  const _World(this.world);

  final IslandWorld world;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.sea,
    child: CustomPaint(painter: _Paint(world), size: Size.infinite),
  );
}

class _Paint extends CustomPainter {
  const _Paint(this.world);

  final IslandWorld world;

  @override
  void paint(Canvas canvas, Size size) {
    // The world fitted to the screen's width.
    final scale = size.width / world.size.width;
    canvas
      ..save()
      ..scale(scale);
    world.paint(canvas, Size(world.size.width, size.height / scale));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Paint old) => false;
}
