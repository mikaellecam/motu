import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A money chart's legend entry: a short stroke of the line's [color],
/// dashed for a [dashed] line, then its [label].
class ChartLegend extends StatelessWidget {
  const ChartLegend(
    this.label, {
    super.key,
    required this.color,
    this.dashed = false,
  });
  final String label;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < (dashed ? 3 : 1); i++)
            Container(
              width: dashed ? 5 : 16,
              height: 2,
              margin: const EdgeInsets.only(right: 2),
              color: color,
            ),
        ],
      ),
      const SizedBox(width: AppSpace.x1),
      // Large text wraps instead of overflowing.
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.muted),
        ),
      ),
    ],
  );
}
