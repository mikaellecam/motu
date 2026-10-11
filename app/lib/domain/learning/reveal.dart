import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import 'content.dart';

/// A `predict_reveal` node (BRIEF §4.3): a question, then frozen curves
/// animate in, then the explanation.
final class PredictReveal {
  const PredictReveal({
    required this.question,
    required this.choices,
    required this.answer,
    required this.series,
    required this.explanation,
    this.invested,
    this.liveVariant,
  });

  final Localized question;
  final List<RevealChoice> choices;

  /// The id of the right choice.
  final String answer;

  /// The curves, in drawing order.
  final List<RevealSeries> series;
  final Localized explanation;

  /// What each curve starts from, in its own currency (decided 2026-10-11);
  /// null draws base 100.
  final Decimal? invested;
  final LiveVariant? liveVariant;
}

final class RevealChoice {
  const RevealChoice(this.id, this.label);
  final String id;
  final Localized label;
}

/// One curve: a dataset of the pack and what to call it.
final class RevealSeries {
  const RevealSeries(this.dataset, this.label);
  final String dataset;
  final Localized label;
}

/// « Et aujourd'hui ? »: the same curves over the [period] up to the latest
/// close ("1y", "6m"…), for nodes whose datasets name their asset.
final class LiveVariant {
  const LiveVariant(this.period);
  final String period;
}

/// What [amount] put in at the first point became at each point: amount ×
/// value / first value.
List<(DateTime, Decimal)> investedCurve(
  List<(DateTime, Decimal)> points,
  Decimal amount,
) {
  if (points.isEmpty) return const [];
  final first = points.first.$2;
  if (first <= Decimal.zero) {
    throw ArgumentError('A curve cannot start from $first');
  }
  return [
    for (final (date, value) in points) (date, ratio(amount * value, first)),
  ];
}

/// Last over first, minus one; null with fewer than two points.
Decimal? curveChange(List<(DateTime, Decimal)> points) {
  if (points.length < 2 || points.first.$2 == Decimal.zero) return null;
  return ratio(points.last.$2, points.first.$2) - Decimal.one;
}

final _period = RegExp(r'^([1-9]\d?)([my])$');

/// The first day of [period] ("6m", "1y"…) ending on [latest]; a month end
/// stays in its month. Null when [period] cannot be read.
DateTime? liveStart(DateTime latest, String period) {
  final match = _period.firstMatch(period);
  if (match == null) return null;
  final n = int.parse(match.group(1)!);
  final months = match.group(2) == 'y' ? 12 * n : n;
  final month = latest.month - months;
  final lastDay = DateTime.utc(latest.year, month + 1, 0).day;
  return DateTime.utc(
    latest.year,
    month,
    latest.day <= lastDay ? latest.day : lastDay,
  );
}
