import 'package:decimal/decimal.dart';

import '../analytics/drawdown.dart';
import '../analytics/returns.dart';
import '../analytics/volatility.dart';
import '../companion/rules.dart';
import 'checkpoint.dart';
import 'content.dart';

/// Where a glossary term stands for the user (BRIEF §4.4, decided
/// 2026-10-11).
enum TermStatus {
  /// Its sheet was opened.
  discovered,

  /// It came up in a completed lesson or a companion moment, not opened yet
  /// (« Nouvelle »).
  met,

  /// Not met yet.
  toDiscover,
}

TermStatus termStatus(
  String id, {
  required Set<String> discovered,
  required Set<String> met,
}) => discovered.contains(id)
    ? TermStatus.discovered
    : met.contains(id)
    ? TermStatus.met
    : TermStatus.toDiscover;

/// The terms the user met: those of the lessons they completed and of the
/// companion moments they were shown.
Set<String> termsMet({
  required Iterable<NodeContent> completed,
  required Iterable<CompanionRule> moments,
}) => {
  for (final node in completed) ...node.glossary,
  for (final rule in moments) ...rule.glossary,
};

/// The glossary index's filters: « Toutes », « Découvertes », « À
/// découvrir ».
enum GlossaryFilter {
  all,
  discovered,
  toDiscover;

  bool keeps(TermStatus status) => switch (this) {
    all => true,
    discovered => status == TermStatus.discovered,
    toDiscover => status != TermStatus.discovered,
  };
}

/// A term's « Tester en 30 secondes » is passed with every answer right.
bool quizPassed(List<QuizQuestion> quiz, List<String?> answers) =>
    quiz.isNotEmpty &&
    answers.length == quiz.length &&
    quizScore(quiz, answers) == quiz.length;

/// The live examples of term sheets (decided 2026-10-11): the essentials of
/// the asset page, over the last year.
enum LiveExample { performance, volatility, drawdown, currency }

/// A live example's figure over a year of [closes]: the change, the
/// annualised volatility, the worst drop, or how the euro value of one unit
/// of the asset's currency moved ([rates]: EUR per unit; none for an asset
/// in euros). Null when the history cannot tell.
Decimal? liveFigure(
  LiveExample kind,
  List<(DateTime, Decimal)> closes, {
  List<(DateTime, Decimal)>? rates,
}) {
  if (closes.isEmpty) return null;
  return switch (kind) {
    LiveExample.performance => simpleReturn(closes.first.$2, closes.last.$2),
    LiveExample.volatility => annualisedVolatility([
      for (final (_, c) in closes) c,
    ]),
    LiveExample.drawdown => maxDrawdown(closes).depth,
    LiveExample.currency =>
      rates == null || rates.length < 2
          ? null
          : simpleReturn(rates.first.$2, rates.last.$2),
  };
}
