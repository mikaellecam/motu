import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import 'checkpoint.dart';
import 'content.dart';
import 'toys.dart';

/// What a lesson shows after its interaction, one card at a time (M13-13).
sealed class NodeCard {
  const NodeCard();
}

/// A worked example (`example`), or two or three lines compared on one chart
/// (`compare`): a headline, a text, and its lines (none for an example
/// without a chart).
final class StoryCard extends NodeCard {
  const StoryCard({
    required this.compare,
    required this.headline,
    required this.text,
    this.lines = const [],
  });

  final bool compare;
  final Localized headline;
  final Localized text;
  final List<CardLine> lines;
}

/// One multiple-choice question, as a checkpoint asks it (`check`): right
/// or wrong, its why shows and the lesson goes on.
final class CheckCard extends NodeCard {
  const CheckCard(this.question);
  final QuizQuestion question;
}

/// A line of a card's chart: a frozen [dataset] of the pack (scaled to
/// [amount] when given, as what that amount became), or a toy [formula] on
/// fixed [inputs], drawing its [series] (its first by default). Never
/// hand-typed points.
final class CardLine {
  const CardLine(
    this.label, {
    this.dataset,
    this.amount,
    this.formula,
    this.inputs = const {},
    this.series,
  });

  final Localized label;
  final String? dataset;
  final Decimal? amount;
  final ToyFormula? formula;
  final Map<String, Decimal> inputs;
  final String? series;
}

/// The values [line] draws, in order: the dataset's points (scaled to its
/// amount), or the formula's series. An unknown dataset or series, or an
/// empty dataset, draws nothing.
List<Decimal> cardLineValues(CardLine line, Map<String, Dataset> datasets) {
  if (line.formula case final formula?) {
    final all = formulaSeries(formula, line.inputs);
    return all[line.series ?? formula.series.first] ?? const [];
  }
  final points = datasets[line.dataset]?.points ?? const [];
  if (points.isEmpty) return const [];
  final amount = line.amount;
  final first = points.first.$2;
  if (amount == null || first == Decimal.zero) {
    return [for (final (_, v) in points) v];
  }
  return [
    for (final (_, v) in points)
      (ratio(v, first) * amount).truncate(scale: ratioScale),
  ];
}
