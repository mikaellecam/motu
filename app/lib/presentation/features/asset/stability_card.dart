import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/analytics/drawdown.dart';
import '../../../domain/analytics/stability.dart';
import '../../../domain/market/asset.dart';
import '../../widgets/section_title.dart';

/// « Stabilité passée » (BRIEF §4.8): the score, its four parts with the fact
/// behind each, and what it is not. Neutral colours: it is neither a gain nor
/// a loss. Screen readers hear it as one sentence.
class StabilityCard extends StatelessWidget {
  const StabilityCard({super.key, required this.score, required this.uiLevel});

  /// Null under a year of closes.
  final PastStability? score;
  final int uiLevel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.muted);
    final s = score;

    return TitledSection(
      title: l10n.asset_score_title,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x3),
          child: s == null
              ? Text(l10n.asset_score_none, style: muted)
              : _Score(s, uiLevel: uiLevel, muted: muted),
        ),
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score(this.s, {required this.uiLevel, required this.muted});
  final PastStability s;
  final int uiLevel;
  final TextStyle? muted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final band = switch (s.band) {
      1 => l10n.asset_band_1,
      2 => l10n.asset_band_2,
      3 => l10n.asset_band_3,
      4 => l10n.asset_band_4,
      _ => l10n.asset_band_5,
    };
    final parts = [
      (
        l10n.asset_score_movements,
        l10n.asset_score_movements_fact(
          // Level 1 shows bands, not volatility figures (§4.15).
          uiLevel < 2 ? band : formats.percent(s.volatility, decimals: 0),
        ),
        s.movementPoints,
        40,
      ),
      (
        l10n.asset_score_fall,
        _fall(l10n, formats, s.worstFall),
        s.fallPoints,
        30,
      ),
      (
        l10n.asset_score_basket,
        s.type == AssetType.etf
            ? l10n.asset_score_basket_etf
            : l10n.asset_score_basket_stock,
        s.basketPoints,
        15,
      ),
      (
        l10n.asset_score_history,
        l10n.asset_score_history_fact(s.historyYears, '${s.since.year}'),
        s.historyPoints,
        15,
      ),
    ];
    final sentence = [
      l10n.asset_score_semantics(s.total),
      l10n.asset_score_meaning,
      for (final (label, fact, points, max) in parts)
        l10n.asset_score_part_semantics(label, points, max, fact),
      l10n.asset_score_disclaimer,
    ].join(' ');

    return Semantics(
      label: sentence,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.asset_score_out_of(s.total, 100),
            style: AppText.figureLarge.copyWith(color: AppColors.ink),
          ),
          Text(l10n.asset_score_meaning, style: muted),
          const SizedBox(height: AppSpace.x2),
          for (final (label, fact, points, max) in parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.x1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: text.bodyMedium),
                        Text(fact, style: muted),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.x2),
                  Text(
                    l10n.asset_score_out_of(points, max),
                    style: AppText.figure.copyWith(color: AppColors.ink),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpace.x2),
          Text(
            l10n.asset_score_disclaimer,
            style: AppText.caption.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  /// « −34 % entre février et mars 2020 », « −8 % en mars 2020 ».
  static String _fall(AppLocalizations l10n, Formats formats, Drawdown fall) {
    final (peak, trough) = (fall.peakDate, fall.troughDate);
    if (peak == null || trough == null) return l10n.asset_score_fall_none;
    final depth = formats.percent(fall.depth, decimals: 0);
    if (peak.year == trough.year && peak.month == trough.month) {
      return l10n.asset_score_fall_month(depth, formats.month(trough));
    }
    return l10n.asset_score_fall_dates(
      depth,
      peak.year == trough.year ? formats.monthName(peak) : formats.month(peak),
      formats.month(trough),
    );
  }
}
