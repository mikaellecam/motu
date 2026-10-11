import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import 'content.dart';

/// A `decision` node (BRIEF §4.3): a historical moment, choices each with an
/// upside and a downside, then what happened next.
final class DecisionNode {
  const DecisionNode({
    required this.context,
    required this.moment,
    required this.dataset,
    required this.seriesLabel,
    required this.choices,
    required this.invested,
    required this.explanation,
  });

  /// The situation at the moment, as it was known then.
  final Localized context;
  final DateTime moment;

  /// The curve: up to the moment before the choice, the rest after it.
  final String dataset;
  final Localized seriesLabel;
  final List<DecisionChoice> choices;

  /// The money at stake at the moment, in the dataset's currency.
  final Decimal invested;
  final Localized explanation;
}

/// A choice and what it keeps in the market: 1 holds everything, 0.5 sells
/// half, 0 sells everything.
final class DecisionChoice {
  const DecisionChoice({
    required this.id,
    required this.label,
    required this.upside,
    required this.downside,
    required this.kept,
  });

  final String id;
  final Localized label;
  final Localized upside;
  final Localized downside;
  final Decimal kept;
}

/// [points] up to the last one on or before [moment], and from that one on:
/// the curve as known at the moment, and what came after.
(List<(DateTime, Decimal)>, List<(DateTime, Decimal)>) splitAt(
  List<(DateTime, Decimal)> points,
  DateTime moment,
) {
  final last = points.lastIndexWhere((p) => !p.$1.isAfter(moment));
  if (last < 0) return (const [], points);
  return (points.sublist(0, last + 1), points.sublist(last));
}

/// How the market moved from [moment] to the last point; null when nothing
/// came after, or when the curve starts after the moment.
Decimal? changeAfter(List<(DateTime, Decimal)> points, DateTime moment) {
  final (before, after) = splitAt(points, moment);
  if (before.isEmpty || after.length < 2 || after.first.$2 == Decimal.zero) {
    return null;
  }
  return ratio(after.last.$2, after.first.$2) - Decimal.one;
}

/// What [invested] became by the end under a choice that [kept] that share
/// in the market (the rest stayed as cash) while it moved by [change].
Decimal choiceOutcome(
  Decimal invested, {
  required Decimal kept,
  required Decimal change,
}) => invested * (Decimal.one + kept * change);
