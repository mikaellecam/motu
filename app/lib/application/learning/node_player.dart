import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../data/content/pack_codec.dart';
import '../../domain/learning/content.dart';
import '../../domain/learning/node.dart';
import '../../domain/learning/reveal.dart';
import '../../domain/learning/toys.dart';
import '../providers.dart';
import 'content.dart';

part 'node_player.g.dart';

/// A node of the Actions & ETF island (BRIEF §4.3).
@riverpod
Future<NodeContent> islandNode(Ref ref, String nodeId) async => findNode(
  await ref.watch(contentPackProvider(actionsEtfIsland).future),
  nodeId,
);

/// The node [nodeId] of [pack], or a [NotFoundFailure].
NodeContent findNode(ContentPack pack, String nodeId) {
  for (final node in pack.nodes) {
    if (node.id == nodeId) return node;
  }
  throw const NotFoundFailure();
}

/// One curve as drawn: what an amount became (decided 2026-10-11), or base
/// 100 without one.
final class LessonCurve {
  const LessonCurve({
    required this.label,
    required this.currency,
    required this.points,
  });

  final Localized label;

  /// The currency of the prices; null for base 100.
  final String? currency;
  final List<(DateTime, Decimal)> points;

  Decimal? get change => curveChange(points);
}

/// Where frozen curves come from (BRIEF §4.3: « Cours réels, clôtures hebdo,
/// 2022, en dollars »).
final class Provenance {
  const Provenance(this.interval, this.from, this.to, this.currency);
  final String interval;
  final DateTime from;
  final DateTime to;
  final String currency;
}

/// A `predict_reveal` node ready to play.
final class RevealView {
  const RevealView({
    required this.node,
    required this.reveal,
    required this.curves,
    required this.provenance,
    required this.assets,
    this.terms = const {},
  });

  final NodeContent node;
  final PredictReveal reveal;
  final List<LessonCurve> curves;

  /// From the first curve's dataset.
  final Provenance provenance;

  /// The catalogue asset of each curve; null for one that is not an asset.
  final List<String?> assets;

  /// The title of each glossary term of the pack, for `{{term}}` links.
  final Map<String, Localized> terms;

  /// « Et aujourd'hui ? » can be offered: the node has a live variant and
  /// every curve is of a catalogue asset.
  bool get hasLiveVariant =>
      reveal.liveVariant != null && assets.every((a) => a != null);
}

/// The curves of [series] drawn from [points] of each, from [invested] or
/// base 100.
List<LessonCurve> _curves(
  PredictReveal reveal,
  List<(String?, List<(DateTime, Decimal)>)> points,
) => [
  for (final (i, s) in reveal.series.indexed)
    LessonCurve(
      label: s.label,
      currency: reveal.invested == null ? null : points[i].$1,
      points: investedCurve(
        points[i].$2,
        reveal.invested ?? Decimal.fromInt(100),
      ),
    ),
];

@riverpod
Future<RevealView> revealView(Ref ref, String nodeId) async {
  final pack = await ref.watch(contentPackProvider(actionsEtfIsland).future);
  final node = findNode(pack, nodeId);
  if (node.type != NodeType.predictReveal) throw const NotFoundFailure();
  final reveal = playable(() => decodePredictReveal(node, pack));
  final datasets = [for (final s in reveal.series) pack.datasets[s.dataset]!];
  final first = datasets.first;
  return RevealView(
    node: node,
    reveal: reveal,
    curves: _curves(reveal, [for (final d in datasets) (d.currency, d.points)]),
    provenance: Provenance(
      first.interval,
      first.points.first.$1,
      first.points.last.$1,
      first.currency,
    ),
    assets: [for (final d in datasets) d.asset],
    terms: termTitles(pack),
  );
}

/// « Et aujourd'hui ? » (BRIEF §4.3): the same curves over the live
/// variant's period up to the latest close, from current market data.
final class LiveCurves {
  const LiveCurves(this.from, this.to, this.curves);
  final DateTime from;
  final DateTime to;
  final List<LessonCurve> curves;
}

@riverpod
Future<LiveCurves> liveReveal(Ref ref, String nodeId) async {
  final market = ref.watch(marketRepositoryProvider);
  final now = ref.watch(liveClockProvider).now();
  final view = await ref.watch(revealViewProvider(nodeId).future);
  final period = view.reveal.liveVariant?.period;
  final today = DateTime.utc(now.year, now.month, now.day);
  final from = period == null ? null : liveStart(today, period);
  if (!view.hasLiveVariant || from == null) throw const NotFoundFailure();

  final points = <(String?, List<(DateTime, Decimal)>)>[];
  for (final asset in view.assets) {
    final bars = await market.history(asset!, from: from, to: today, asOf: now);
    if (bars.isEmpty) throw DataUnavailableFailure(today);
    points.add((
      bars.first.currency.code,
      [for (final b in bars) (b.date, b.close)],
    ));
  }
  final curves = _curves(view.reveal, points);
  return LiveCurves(
    curves.first.points.first.$1,
    curves.first.points.last.$1,
    curves,
  );
}

/// The answer being given to a `predict_reveal` node.
final class PredictState {
  const PredictState({this.chosen, this.submitted = false, this.failure});
  final String? chosen;

  /// The answer was saved: the curves are revealed.
  final bool submitted;
  final Failure? failure;
}

@riverpod
class PredictPlay extends _$PredictPlay {
  @override
  PredictState build(String nodeId) => const PredictState();

  void choose(String choice) {
    if (!state.submitted) state = PredictState(chosen: choice);
  }

  /// Completes the node with the chosen answer, right or wrong (BRIEF
  /// §4.3), then reveals.
  Future<void> submit() async {
    final chosen = state.chosen;
    if (chosen == null || state.submitted) return;
    try {
      await ref
          .read(profileRepositoryProvider)
          .completeNode(
            nodeId,
            answer: chosen,
            at: ref.read(liveClockProvider).now(),
          );
      state = PredictState(chosen: chosen, submitted: true);
    } on Failure catch (failure) {
      state = PredictState(chosen: chosen, failure: failure);
    }
  }
}

/// A `toy` node ready to play: the past average its return starts from,
/// when it has one.
final class ToyView {
  const ToyView({
    required this.node,
    required this.toy,
    this.past,
    this.terms = const {},
  });
  final NodeContent node;
  final Toy toy;
  final ({Decimal rate, DateTime from, DateTime to})? past;

  /// See [RevealView.terms].
  final Map<String, Localized> terms;
}

@riverpod
Future<ToyView> toyView(Ref ref, String nodeId) async {
  final pack = await ref.watch(contentPackProvider(actionsEtfIsland).future);
  final node = findNode(pack, nodeId);
  if (node.type != NodeType.toy) throw const NotFoundFailure();
  final toy = playable(() => decodeToy(node, pack));
  final points = switch (toy.returnFrom) {
    null => null,
    final from => pack.datasets[from.dataset]!.points,
  };
  final rate = points == null ? null : averageYearlyReturn(points);
  return ToyView(
    node: node,
    toy: toy,
    past: rate == null
        ? null
        : (rate: rate, from: points!.first.$1, to: points.last.$1),
    terms: termTitles(pack),
  );
}

/// The sliders of a toy and what they draw.
final class ToyState {
  const ToyState({
    required this.view,
    required this.values,
    this.touched = const {},
    this.completed = false,
    this.failure,
  });

  final ToyView view;
  final Map<String, Decimal> values;
  final Set<String> touched;

  /// Every slider was moved and the node is saved as done.
  final bool completed;
  final Failure? failure;

  Decimal value(String control) => values[control]!;

  /// The return is still the real past average, not a hypothesis.
  bool get returnIsPast => view.past?.rate == values['return'];

  ToyOutcome get outcome {
    final years = value('years').toBigInt().toInt();
    return switch (view.toy.formula) {
      ToyFormula.fees => FeesOutcome(
        feesToy(
          amount: value('amount'),
          years: years,
          yearlyReturn: value('return'),
          lowFee: value('fee_low'),
          highFee: value('fee_high'),
        ),
      ),
      ToyFormula.compound => CompoundOutcome(
        compoundToy(
          amount: value('amount'),
          monthly: value('monthly'),
          years: years,
          yearlyReturn: value('return'),
        ),
      ),
    };
  }

  ToyState copyWith({
    Map<String, Decimal>? values,
    Set<String>? touched,
    bool? completed,
    Failure? failure,
  }) => ToyState(
    view: view,
    values: values ?? this.values,
    touched: touched ?? this.touched,
    completed: completed ?? this.completed,
    failure: failure,
  );
}

sealed class ToyOutcome {
  const ToyOutcome();
}

final class FeesOutcome extends ToyOutcome {
  const FeesOutcome(this.result);
  final FeesResult result;
}

final class CompoundOutcome extends ToyOutcome {
  const CompoundOutcome(this.result);
  final CompoundResult result;
}

@riverpod
class ToyPlay extends _$ToyPlay {
  @override
  Future<ToyState> build(String nodeId) async {
    final view = await ref.watch(toyViewProvider(nodeId).future);
    final past = view.past?.rate;
    return ToyState(
      view: view,
      values: {
        for (final c in view.toy.controls)
          c.id: c.id == 'return' && past != null
              ? _clamp(past, c.min, c.max)
              : c.initial,
      },
    );
  }

  /// Moves a slider to its [index]-th step from the minimum.
  Future<void> setStep(String control, int index) {
    final c = state.value?.view.toy.controls.firstWhere((c) => c.id == control);
    if (c == null) return Future.value();
    return set(
      control,
      _clamp(c.min + c.step * Decimal.fromInt(index), c.min, c.max),
    );
  }

  /// Moves a slider; once every one moved, the node is saved as done
  /// (BRIEF §4.3).
  Future<void> set(String control, Decimal value) async {
    final current = state.value;
    if (current == null) return;
    var next = current.copyWith(
      values: {...current.values, control: value},
      touched: {...current.touched, control},
    );
    state = AsyncData(next);
    final ids = [for (final c in current.view.toy.controls) c.id];
    if (next.completed || !everyControlTouched(ids, next.touched)) return;
    try {
      await ref
          .read(profileRepositoryProvider)
          .completeNode(nodeId, at: ref.read(liveClockProvider).now());
      next = (state.value ?? next).copyWith(completed: true);
    } on Failure catch (failure) {
      next = (state.value ?? next).copyWith(failure: failure);
    }
    state = AsyncData(next);
  }
}

/// The title of each glossary term of [pack], for `{{term}}` links.
Map<String, Localized> termTitles(ContentPack pack) => {
  for (final t in pack.glossary.values) t.id: t.title,
};

Decimal _clamp(Decimal value, Decimal min, Decimal max) =>
    value < min ? min : (value > max ? max : value);

/// [decode] a node's payload; one the app cannot play is the pack's fault:
/// a server-side error.
T playable<T>(T Function() decode) {
  try {
    return decode();
  } on FormatException {
    throw const ServerFailure();
  }
}
