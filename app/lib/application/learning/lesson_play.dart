import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../data/content/pack_codec.dart';
import '../../domain/learning/checkpoint.dart';
import '../../domain/learning/content.dart';
import '../../domain/learning/decision.dart';
import '../../domain/learning/node.dart';
import '../../domain/learning/puzzle.dart';
import '../../domain/learning/sort.dart';
import '../providers.dart';
import 'node_player.dart';

part 'lesson_play.g.dart';

/// The players of `decision`, `sort`, `build_puzzle` and `checkpoint`
/// nodes (BRIEF §4.3). Each saves the node as done in `node_progress` the
/// way its type completes.

/// The lesson [nodeId] of any island ([lessonOf]), when it is of [type].
Future<({NodeContent node, ContentPack pack, Map<String, Localized> terms})>
_node(Ref ref, String nodeId, NodeType type) async {
  final lesson = await lessonOf(ref, nodeId);
  if (lesson.node.type != type) throw const NotFoundFailure();
  return lesson;
}

/// Saves [nodeId] as done; null when saved, else the failure.
Future<Failure?> _complete(Ref ref, String nodeId, {String? answer}) async {
  try {
    await ref
        .read(profileRepositoryProvider)
        .completeNode(
          nodeId,
          answer: answer,
          at: ref.read(liveClockProvider).now(),
        );
    return null;
  } on Failure catch (failure) {
    return failure;
  }
}

// ---------------------------------------------------------------- decision

/// A `decision` node ready to play: the curve before and after the moment,
/// and what the amount at stake became under each choice.
final class DecisionView {
  const DecisionView({
    required this.node,
    required this.decision,
    required this.before,
    required this.after,
    required this.currency,
    required this.change,
    required this.outcomes,
    this.terms = const {},
  });

  final NodeContent node;
  final DecisionNode decision;
  final List<(DateTime, Decimal)> before;
  final List<(DateTime, Decimal)> after;
  final String currency;

  /// How the market moved after the moment.
  final Decimal change;

  /// Choice id → what the amount became by the end.
  final Map<String, Decimal> outcomes;
  final Map<String, Localized> terms;
}

@riverpod
Future<DecisionView> decisionView(Ref ref, String nodeId) async {
  final (:node, :pack, :terms) = await _node(ref, nodeId, NodeType.decision);
  final decision = playable(() => decodeDecision(node, pack));
  final dataset = pack.datasets[decision.dataset]!;
  final (before, after) = splitAt(dataset.points, decision.moment);
  final change = changeAfter(dataset.points, decision.moment)!;
  return DecisionView(
    node: node,
    decision: decision,
    before: before,
    after: after,
    currency: dataset.currency,
    change: change,
    outcomes: {
      for (final c in decision.choices)
        c.id: choiceOutcome(decision.invested, kept: c.kept, change: change),
    },
    terms: terms,
  );
}

/// A choice being made; once submitted, what happened next is shown.
final class ChoiceState {
  const ChoiceState({this.chosen, this.submitted = false, this.failure});
  final String? chosen;
  final bool submitted;
  final Failure? failure;
}

@riverpod
class DecisionPlay extends _$DecisionPlay {
  @override
  ChoiceState build(String nodeId) => const ChoiceState();

  void choose(String choice) {
    if (!state.submitted) state = ChoiceState(chosen: choice);
  }

  /// Completes the node with the choice made (BRIEF §4.3).
  Future<void> submit() async {
    final chosen = state.chosen;
    if (chosen == null || state.submitted) return;
    final failure = await _complete(ref, nodeId, answer: chosen);
    state = ChoiceState(
      chosen: chosen,
      submitted: failure == null,
      failure: failure,
    );
  }
}

// -------------------------------------------------------------------- sort

/// A `sort` node ready to play: each item's real value and the true order.
final class SortView {
  const SortView({
    required this.node,
    required this.sort,
    required this.values,
    required this.truth,
    this.terms = const {},
  });

  final NodeContent node;
  final SortNode sort;
  final Map<String, Decimal> values;

  /// Item ids from the lowest value to the highest.
  final List<String> truth;
  final Map<String, Localized> terms;
}

@riverpod
Future<SortView> sortView(Ref ref, String nodeId) async {
  final (:node, :pack, :terms) = await _node(ref, nodeId, NodeType.sort);
  final sort = playable(() => decodeSort(node, pack));
  final values = <String, Decimal>{};
  for (final item in sort.items) {
    final value = itemValue(item, switch (item.dataset) {
      null => null,
      final d => pack.datasets[d]!.points,
    });
    // Too short a history to rank: the pack's fault.
    if (value == null) throw const ServerFailure();
    values[item.id] = value;
  }
  return SortView(
    node: node,
    sort: sort,
    values: values,
    truth: trueOrder([for (final i in sort.items) i.id], values),
    terms: terms,
  );
}

/// The order being built; once submitted, how many sit at their rank.
final class SortState {
  const SortState({required this.order, this.placed, this.failure});

  final List<String> order;

  /// Well placed items, once submitted.
  final int? placed;
  final Failure? failure;

  bool get submitted => placed != null;
}

@riverpod
class SortPlay extends _$SortPlay {
  @override
  Future<SortState> build(String nodeId) async {
    final view = await ref.watch(sortViewProvider(nodeId).future);
    return SortState(order: [for (final i in view.sort.items) i.id]);
  }

  /// Moves the item at [from] so that it ends at [to].
  void move(int from, int to) {
    final current = state.value;
    if (current == null || current.submitted) return;
    final order = [...current.order];
    final item = order.removeAt(from);
    order.insert(to, item);
    state = AsyncData(SortState(order: order));
  }

  /// Every item is placed: completes the node and counts the well placed.
  Future<void> submit() async {
    final current = state.value;
    if (current == null || current.submitted) return;
    final view = await ref.read(sortViewProvider(nodeId).future);
    final failure = await _complete(
      ref,
      nodeId,
      answer: current.order.join(','),
    );
    state = AsyncData(
      failure == null
          ? SortState(
              order: current.order,
              placed: wellPlaced(current.order, view.truth),
            )
          : SortState(order: current.order, failure: failure),
    );
  }
}

// ------------------------------------------------------------ build_puzzle

/// A `build_puzzle` node ready to play, with each asset's daily closes.
final class PuzzleView {
  const PuzzleView({
    required this.node,
    required this.puzzle,
    required this.prices,
    this.terms = const {},
  });

  final NodeContent node;
  final PuzzleNode puzzle;
  final Map<String, List<(DateTime, Decimal)>> prices;
  final Map<String, Localized> terms;
}

@riverpod
Future<PuzzleView> puzzleView(Ref ref, String nodeId) async {
  final (:node, :pack, :terms) = await _node(ref, nodeId, NodeType.buildPuzzle);
  final puzzle = playable(() => decodePuzzle(node, pack));
  return PuzzleView(
    node: node,
    puzzle: puzzle,
    prices: {
      for (final a in puzzle.assets)
        a.dataset: pack.datasets[a.dataset]!.points,
    },
    terms: terms,
  );
}

/// The weights being given, checked against the rules as they change.
final class PuzzleState {
  const PuzzleState({
    required this.view,
    required this.weights,
    required this.volatility,
    required this.check,
    this.completed = false,
    this.failure,
  });

  final PuzzleView view;
  final Map<String, Decimal> weights;

  /// Of the portfolio; null without weight or history.
  final Decimal? volatility;
  final PuzzleCheck check;

  /// The rules were met and the node saved as done.
  final bool completed;
  final Failure? failure;

  Decimal get total => weights.values.fold(Decimal.zero, (s, w) => s + w);
}

@riverpod
class PuzzlePlay extends _$PuzzlePlay {
  @override
  Future<PuzzleState> build(String nodeId) async {
    final view = await ref.watch(puzzleViewProvider(nodeId).future);
    return _state(view, {
      for (final a in view.puzzle.assets) a.dataset: Decimal.zero,
    });
  }

  PuzzleState _state(
    PuzzleView view,
    Map<String, Decimal> weights, {
    bool completed = false,
    Failure? failure,
  }) {
    final volatility = portfolioVolatility(view.prices, weights);
    return PuzzleState(
      view: view,
      weights: weights,
      volatility: volatility,
      check: checkPuzzle(
        view.puzzle.rules,
        view.puzzle.assets,
        weights: weights,
        volatility: volatility,
      ),
      completed: completed,
      failure: failure,
    );
  }

  /// Gives [asset] [steps] weight steps (0 to 100 %).
  void setSteps(String asset, int steps) {
    final current = state.value;
    if (current == null || current.completed) return;
    final weight = current.view.puzzle.step * Decimal.fromInt(steps);
    state = AsyncData(
      _state(current.view, {
        ...current.weights,
        asset: weight < Decimal.zero
            ? Decimal.zero
            : (weight > Decimal.one ? Decimal.one : weight),
      }),
    );
  }

  /// Completes the node once the rules are met (BRIEF §4.3: validated by
  /// domain calculations).
  Future<void> submit() async {
    final current = state.value;
    if (current == null || current.completed || !current.check.solved) return;
    final failure = await _complete(
      ref,
      nodeId,
      answer: [
        for (final MapEntry(key: id, value: w) in current.weights.entries)
          if (w > Decimal.zero) '$id=$w',
      ].join(','),
    );
    state = AsyncData(
      _state(
        current.view,
        current.weights,
        completed: failure == null,
        failure: failure,
      ),
    );
  }
}

// -------------------------------------------------------------- checkpoint

final class CheckpointView {
  const CheckpointView({
    required this.node,
    required this.checkpoint,
    this.terms = const {},
  });

  final NodeContent node;
  final Checkpoint checkpoint;
  final Map<String, Localized> terms;
}

@riverpod
Future<CheckpointView> checkpointView(Ref ref, String nodeId) async {
  final (:node, :pack, :terms) = await _node(ref, nodeId, NodeType.checkpoint);
  return CheckpointView(
    node: node,
    checkpoint: playable(() => decodeCheckpoint(node, pack)),
    terms: terms,
  );
}

/// Where the quiz stands: the question shown, the answers given, and
/// whether the current one is checked.
final class QuizState {
  const QuizState({
    this.index = 0,
    this.answers = const [],
    this.chosen,
    this.checked = false,
    this.score,
    this.failure,
  });

  final int index;

  /// One per question checked so far.
  final List<String> answers;

  /// The choice picked for the current question.
  final String? chosen;
  final bool checked;

  /// Right answers, once every question was checked and the node saved.
  final int? score;
  final Failure? failure;

  bool get finished => score != null;
}

@riverpod
class CheckpointPlay extends _$CheckpointPlay {
  @override
  QuizState build(String nodeId) => const QuizState();

  void choose(String choice) {
    if (state.checked || state.finished) return;
    state = QuizState(
      index: state.index,
      answers: state.answers,
      chosen: choice,
    );
  }

  /// Checks the current answer.
  void check() {
    final chosen = state.chosen;
    if (chosen == null || state.checked) return;
    state = QuizState(
      index: state.index,
      answers: [...state.answers, chosen],
      chosen: chosen,
      checked: true,
    );
  }

  /// The next question; after the last one, the score, and the node saved
  /// as done whatever it is (BRIEF §4.3: one attempt finished).
  Future<void> next() async {
    if (!state.checked || state.finished) return;
    final view = await ref.read(checkpointViewProvider(nodeId).future);
    final questions = view.checkpoint.questions;
    if (state.index + 1 < questions.length) {
      state = QuizState(index: state.index + 1, answers: state.answers);
      return;
    }
    final score = quizScore(questions, state.answers);
    final failure = await _complete(
      ref,
      nodeId,
      answer: '$score/${questions.length}',
    );
    state = QuizState(
      index: state.index,
      answers: state.answers,
      chosen: state.chosen,
      checked: true,
      score: failure == null ? score : null,
      failure: failure,
    );
  }
}
