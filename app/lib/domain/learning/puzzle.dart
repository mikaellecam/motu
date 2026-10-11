import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../analytics/volatility.dart';
import 'content.dart';

/// A `build_puzzle` node (BRIEF §4.3): weights to give assets so the
/// portfolio meets its rules, checked by domain calculations.
final class PuzzleNode {
  const PuzzleNode({
    required this.prompt,
    required this.assets,
    required this.rules,
    required this.step,
    required this.explanation,
  });

  final Localized prompt;
  final List<PuzzleAsset> assets;
  final PuzzleRules rules;

  /// The weight slider's step (0.1 = 10 %).
  final Decimal step;
  final Localized explanation;
}

/// An asset to weigh: its daily dataset, name and region.
final class PuzzleAsset {
  const PuzzleAsset(this.dataset, this.label, this.region);
  final String dataset;
  final Localized label;
  final String region;
}

/// What the portfolio must meet; a rule left null always holds.
final class PuzzleRules {
  const PuzzleRules({
    required this.maxVolatility,
    this.minAssets,
    this.minRegions,
  });

  final Decimal maxVolatility;
  final int? minAssets;
  final int? minRegions;
}

/// The annualised volatility (BRIEF §7.7) of a portfolio holding [weights]
/// of each daily series of [prices], rebalanced daily, over the days every
/// weighted asset has. Below 100 % the rest sits in cash; above, weights
/// count as shares of their total. Null without weight or with too short a
/// history.
Decimal? portfolioVolatility(
  Map<String, List<(DateTime, Decimal)>> prices,
  Map<String, Decimal> weights,
) {
  final held = {
    for (final e in weights.entries)
      if (e.value > Decimal.zero) e.key: e.value,
  };
  if (held.isEmpty) return null;
  final sum = held.values.fold(Decimal.zero, (s, w) => s + w);
  final scale = sum > Decimal.one ? sum : Decimal.one;
  final cash = Decimal.one - ratio(sum, scale);
  final byDay = {
    for (final id in held.keys) id: {for (final (d, p) in prices[id]!) d: p},
  };
  final days =
      byDay.values
          .map((m) => m.keys.toSet())
          .reduce((a, b) => a.intersection(b))
          .toList()
        ..sort();
  if (days.length < 2) return null;
  // The value of 1 put in, one close a day.
  final index = [Decimal.one];
  for (var i = 1; i < days.length; i++) {
    var growth = cash;
    for (final MapEntry(key: id, value: w) in held.entries) {
      final today = byDay[id]![days[i]]!;
      final before = byDay[id]![days[i - 1]]!;
      growth += ((w * today) / (scale * before)).toDecimal(
        scaleOnInfinitePrecision: 12,
      );
    }
    index.add((index.last * growth).truncate(scale: 12));
  }
  return annualisedVolatility(index);
}

/// Where a portfolio stands against the rules.
final class PuzzleCheck {
  const PuzzleCheck({
    required this.total,
    required this.volatility,
    required this.assets,
    required this.regions,
  });

  /// The weights add up to 100 %.
  final bool total;
  final bool volatility;
  final bool assets;
  final bool regions;

  bool get solved => total && volatility && assets && regions;
}

PuzzleCheck checkPuzzle(
  PuzzleRules rules,
  List<PuzzleAsset> assets, {
  required Map<String, Decimal> weights,
  required Decimal? volatility,
}) {
  final held = [
    for (final a in assets)
      if ((weights[a.dataset] ?? Decimal.zero) > Decimal.zero) a,
  ];
  final total = weights.values.fold(Decimal.zero, (sum, w) => sum + w);
  return PuzzleCheck(
    total: total == Decimal.one,
    volatility: volatility != null && volatility <= rules.maxVolatility,
    assets: held.length >= (rules.minAssets ?? 0),
    regions: {for (final a in held) a.region}.length >= (rules.minRegions ?? 0),
  );
}
