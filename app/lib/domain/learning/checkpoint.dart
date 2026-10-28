import 'dart:math';

import 'content.dart';
import 'reveal.dart';

/// A `checkpoint` node (BRIEF §4.3): 4 to 6 questions, one at a time.
final class Checkpoint {
  const Checkpoint(this.questions);
  final List<QuizQuestion> questions;
}

final class QuizQuestion {
  const QuizQuestion({
    required this.question,
    required this.choices,
    required this.answer,
    this.explanation,
  });

  final Localized question;
  final List<RevealChoice> choices;

  /// The id of the right choice.
  final String answer;

  /// Shown once answered.
  final Localized? explanation;
}

/// How many of [answers], in question order, are right; a question not
/// answered scores nothing.
int quizScore(List<QuizQuestion> questions, List<String?> answers) => [
  for (var i = 0; i < questions.length && i < answers.length; i++)
    if (answers[i] == questions[i].answer) i,
].length;

/// [questions] in their order, each one's choices in a new order drawn from
/// [random] (decided 2026-10-28: a pack's order would always put the right
/// answer in the same place); answers and labels unchanged.
List<QuizQuestion> shuffleChoices(
  List<QuizQuestion> questions,
  Random random,
) => [
  for (final q in questions)
    QuizQuestion(
      question: q.question,
      choices: [...q.choices]..shuffle(random),
      answer: q.answer,
      explanation: q.explanation,
    ),
];
