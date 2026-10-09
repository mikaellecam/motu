import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/theme/tokens.dart';

/// Five rising bars, [band] of them filled (BRIEF §7.8); « pas assez de
/// données » when there is no band.
class RiskMeter extends StatelessWidget {
  const RiskMeter(this.band, {super.key});

  final int? band;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final band = this.band;
    if (band == null) {
      return Text(
        l10n.explorer_risk_unknown,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AppColors.muted),
      );
    }
    return Semantics(
      label: l10n.explorer_risk('$band'),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: AppSpace.x1,
              height: 6.0 + 2 * i,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i < band ? AppColors.ink : AppColors.line,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}
