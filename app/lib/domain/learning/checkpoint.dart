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
