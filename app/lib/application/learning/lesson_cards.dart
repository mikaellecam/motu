import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:decimal/decimal.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../domain/learning/cards.dart';
import '../../domain/learning/content.dart';
import '../providers.dart';
import 'node_player.dart';

part 'lesson_cards.g.dart';

/// Where a lesson of cards stands (M13-13): card 0 is its interaction, then
/// its [NodeCard]s; [played] once the interaction is done, [picked] the
/// choice touched on each check card and [checks] the one checked, [done]
/// once saved after the last card.
final class CardsState {
  const CardsState({
    this.at = 0,
    this.played = false,
    this.answer,
    this.picked = const {},
    this.checks = const {},
    this.done = false,
    this.failure,
  });

  final int at;
  final bool played;

  /// The interaction's answer, saved with the lesson at the end.
  final String? answer;
  final Map<int, String> picked;
  final Map<int, String> checks;
  final bool done;
  final Failure? failure;

  CardsState copyWith({
    int? at,
    bool? played,
    String? answer,
    Map<int, String>? picked,
    Map<int, String>? checks,
    bool? done,
    Failure? failure,
  }) => CardsState(
    at: at ?? this.at,
    played: played ?? this.played,
    answer: answer ?? this.answer,
    picked: picked ?? this.picked,
    checks: checks ?? this.checks,
    done: done ?? this.done,
    failure: failure,
  );
}

@riverpod
class LessonCards extends _$LessonCards {
  @override
  CardsState build(String nodeId) => const CardsState();

  /// The interaction is done: « Continuer » leads to the first card.
  void played({String? answer}) =>
      state = state.copyWith(played: true, answer: answer);

  /// [choice] touched on the check card [at], until it is checked.
  void pick(int at, String choice) {
    if (state.checks.containsKey(at)) return;
    state = state.copyWith(picked: {...state.picked, at: choice});
  }

  /// The check card [at] answered with its pick, once: right or wrong, the
  /// lesson goes on.
  void check(int at) {
    final choice = state.picked[at];
    if (choice == null || state.checks.containsKey(at)) return;
    state = state.copyWith(checks: {...state.checks, at: choice});
  }

  /// To the next card; after the last one, the lesson is saved as done.
  Future<void> next() async {
    final cards = (await ref.read(islandNodeProvider(nodeId).future)).cards;
    if (!state.played || state.done) return;
    final card = state.at == 0 ? null : cards[state.at - 1];
    if (card is CheckCard && !state.checks.containsKey(state.at)) return;
    if (state.at < cards.length) {
      state = state.copyWith(at: state.at + 1);
      return;
    }
    try {
      await _save(ref, nodeId, state.answer);
      state = state.copyWith(done: true);
    } on Failure catch (failure) {
      state = state.copyWith(failure: failure);
    }
  }
}

/// A line of a card's chart, as drawn (M13-13).
typedef CardChartLine = ({
  Localized label,
  List<Decimal> values,
  Currency currency,
});

/// A lesson's cards ready to show: every term title for its `{{term}}`
/// links, and each card's lines (none for a check or a plain example).
final class CardsView {
  const CardsView(this.node, this.terms, this.lines);
  final NodeContent node;
  final Map<String, Localized> terms;
  final List<List<CardChartLine>> lines;
}

@riverpod
Future<CardsView> cardsView(Ref ref, String nodeId) async {
  final (:node, :pack, :terms) = await lessonOf(ref, nodeId);
  Currency currency(CardLine line) => Currency.values.firstWhere(
    (c) => c.code == pack.datasets[line.dataset]?.currency,
    orElse: () => Currency.eur,
  );
  return CardsView(node, terms, [
    for (final card in node.cards)
      switch (card) {
        StoryCard(:final lines) => [
          for (final line in lines)
            (
              label: line.label,
              values: cardLineValues(line, pack.datasets),
              currency: currency(line),
            ),
        ],
        CheckCard() => const [],
      },
  ]);
}

/// A player's interaction is done (BRIEF §4.3): a lesson without cards is
/// saved as done now; one with cards waits for its last card (M13-13).
/// Throws a [Failure] when saving fails.
Future<void> savePlayed(Ref ref, String nodeId, {String? answer}) async {
  final node = await ref.read(islandNodeProvider(nodeId).future);
  if (node.cards.isEmpty) return _save(ref, nodeId, answer);
  ref.read(lessonCardsProvider(nodeId).notifier).played(answer: answer);
}

Future<void> _save(Ref ref, String nodeId, String? answer) => ref
    .read(profileRepositoryProvider)
    .completeNode(
      nodeId,
      answer: answer,
      at: ref.read(liveClockProvider).now(),
    );
