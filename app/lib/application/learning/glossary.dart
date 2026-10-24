import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../data/repositories/glossary_repository.dart';
import '../../domain/learning/checkpoint.dart';
import '../../domain/learning/content.dart';
import '../../domain/learning/glossary.dart';
import '../../domain/market/asset.dart';
import '../explorer/explorer.dart' show searchKey;
import '../providers.dart';
import '../wallet/wallet_overview.dart' show worldAssetId;
import 'content.dart';
import 'island_path.dart';
import 'lesson_play.dart' show QuizState;

part 'glossary.g.dart';

/// The glossary (BRIEF §4.4): the index, the term sheet with its live
/// example, and the term quiz.

/// Term id → what the user did with it, then every change.
@riverpod
Stream<Map<String, TermProgress>> glossaryProgress(Ref ref) =>
    ref.watch(glossaryRepositoryProvider).watch();

/// The index's search and filter.
@riverpod
class GlossarySearch extends _$GlossarySearch {
  @override
  ({String query, GlossaryFilter filter}) build() =>
      (query: '', filter: GlossaryFilter.all);

  void setQuery(String query) => state = (query: query, filter: state.filter);

  void setFilter(GlossaryFilter filter) =>
      state = (query: state.query, filter: filter);
}

/// A term of the index and where it stands.
final class GlossaryRow {
  const GlossaryRow(this.term, this.status);
  final GlossaryTerm term;
  final TermStatus status;
}

/// The index: the terms kept by the search and the filter, by first letter
/// of their title in [language], accents aside; and how many of the pack's
/// terms there are, and were discovered, whatever the search.
final class GlossaryIndex {
  const GlossaryIndex(
    this.groups, {
    required this.discovered,
    required this.total,
  });
  final List<(String, List<GlossaryRow>)> groups;
  final int discovered;
  final int total;

  bool get isEmpty => groups.isEmpty;
}

@riverpod
Future<GlossaryIndex> glossaryIndex(Ref ref, String language) async {
  final search = ref.watch(glossarySearchProvider);
  final repo = ref.watch(glossaryRepositoryProvider);
  final packF = ref.watch(contentPackProvider(actionsEtfIsland).future)
    ..ignore();
  final progressF = ref.watch(glossaryProgressProvider.future)..ignore();
  final completedF = ref.watch(completedNodesProvider.future)..ignore();
  final pack = await packF;
  final discovered = (await progressF).keys.toSet();
  final completed = await completedF;
  final met = termsMet(
    completed: [
      for (final node in pack.nodes)
        if (completed.contains(node.id)) node,
    ],
    moments: await repo.momentsShown(),
  );

  final query = searchKey(search.query);
  final rows = [
    for (final term in pack.glossary.values)
      if (query.isEmpty ||
          searchKey(term.title.of(language)).contains(query) ||
          searchKey(term.short.of(language)).contains(query))
        GlossaryRow(
          term,
          termStatus(term.id, discovered: discovered, met: met),
        ),
  ]..retainWhere((row) => search.filter.keeps(row.status));
  rows.sort(
    (a, b) =>
        searchKey(a.term.title.of(language))
            .compareTo(searchKey(b.term.title.of(language))),
  );

  final groups = <(String, List<GlossaryRow>)>[];
  for (final row in rows) {
    final key = searchKey(row.term.title.of(language));
    final letter = key.isEmpty ? '#' : key[0].toUpperCase();
    if (groups.isEmpty || groups.last.$1 != letter) groups.add((letter, []));
    groups.last.$2.add(row);
  }
  return GlossaryIndex(
    groups,
    discovered: pack.glossary.keys.where(discovered.contains).length,
    total: pack.glossary.length,
  );
}

/// A term's sheet, as opened: the term, the titles of its related terms,
/// and whether this open discovered it (« Nouvelle notion »).
final class TermSheetView {
  const TermSheetView({
    required this.term,
    required this.related,
    required this.firstOpen,
    required this.terms,
  });

  final GlossaryTerm term;

  /// The related terms the pack holds, in the term's order.
  final List<GlossaryTerm> related;
  final bool firstOpen;

  /// Every term's title, for `{{term}}` links.
  final Map<String, Localized> terms;
}

/// Opening a term's sheet marks it discovered (BRIEF §4.4, persisted).
@riverpod
Future<TermSheetView> termSheet(Ref ref, String termId) async {
  final repo = ref.watch(glossaryRepositoryProvider);
  final clock = ref.watch(liveClockProvider);
  final pack = await ref.watch(contentPackProvider(actionsEtfIsland).future);
  final term = pack.glossary[termId];
  if (term == null) throw const NotFoundFailure();
  return TermSheetView(
    term: term,
    related: [for (final id in term.related) ?pack.glossary[id]],
    firstOpen: await repo.discover(termId, clock.now()),
    terms: {for (final t in pack.glossary.values) t.id: t.title},
  );
}

/// A live example on real data (decided 2026-10-11): the term's figure over
/// the last year for the asset the sheet was opened from, or the world ETF;
/// next to the world ETF's, with the asset's closes for a small chart.
final class LiveExampleView {
  const LiveExampleView({
    required this.kind,
    required this.asset,
    required this.figure,
    required this.closes,
    this.world,
    this.worldFigure,
  });

  final LiveExample kind;
  final Asset asset;

  /// Null when the history cannot tell (or « Aucun » risk of an asset in
  /// euros).
  final Decimal? figure;
  final List<(DateTime, Decimal)> closes;

  /// The world ETF beside another asset, except for the currency example
  /// (same currency, nothing to compare).
  final Asset? world;
  final Decimal? worldFigure;
}

@riverpod
Future<LiveExampleView> liveExample(
  Ref ref,
  LiveExample kind,
  String? assetId,
) async {
  final market = ref.watch(marketRepositoryProvider);
  final fx = ref.watch(fxServiceProvider);
  final now = ref.watch(liveClockProvider).now();
  final today = DateTime.utc(now.year, now.month, now.day);
  final from = DateTime.utc(today.year - 1, today.month, today.day);
  final assets = {for (final a in await market.assets(asOf: now)) a.id: a};
  final asset = assets[assetId ?? worldAssetId];
  final world = assets[worldAssetId];
  if (asset == null) throw const NotFoundFailure();

  Future<List<(DateTime, Decimal)>> closesOf(Asset a) async => [
    for (final b in await market.history(
      a.id,
      from: from,
      to: today,
      asOf: now,
    ))
      (b.date, b.close),
  ];
  final closes = await closesOf(asset);
  List<(DateTime, Decimal)>? rates;
  if (kind == LiveExample.currency &&
      asset.currency != Currency.eur &&
      closes.isNotEmpty) {
    final rate = await fx.lookup(
      asset.currency,
      Currency.eur,
      start: closes.first.$1,
      asOf: now,
    );
    rates = [
      for (final d in [closes.first.$1, closes.last.$1]) (d, rate(d)),
    ];
  }
  final compare =
      kind != LiveExample.currency && world != null && world.id != asset.id;
  return LiveExampleView(
    kind: kind,
    asset: asset,
    figure: liveFigure(kind, closes, rates: rates),
    closes: closes,
    world: compare ? world : null,
    worldFigure: compare ? liveFigure(kind, await closesOf(world)) : null,
  );
}

/// « Tester en 30 secondes » (BRIEF §4.4): the term's questions one at a
/// time; all right, the quiz is passed (persisted).
@riverpod
class TermQuiz extends _$TermQuiz {
  @override
  QuizState build(String termId) => const QuizState();

  void choose(String choice) {
    if (state.checked || state.finished) return;
    state = QuizState(
      index: state.index,
      answers: state.answers,
      chosen: choice,
    );
  }

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

  /// The next question, or the result after the last one.
  Future<void> next() async {
    if (!state.checked || state.finished) return;
    final pack = await ref.read(contentPackProvider(actionsEtfIsland).future);
    final quiz = pack.glossary[termId]?.quiz ?? const [];
    if (state.index + 1 < quiz.length) {
      state = QuizState(index: state.index + 1, answers: state.answers);
      return;
    }
    final passed = quizPassed(quiz, state.answers);
    Failure? failure;
    if (passed) {
      try {
        await ref.read(glossaryRepositoryProvider).passQuiz(termId);
      } on Failure catch (f) {
        failure = f;
      }
    }
    state = QuizState(
      index: state.index,
      answers: state.answers,
      chosen: state.chosen,
      checked: true,
      score: failure == null ? quizScore(quiz, state.answers) : null,
      failure: failure,
    );
  }

  /// Back to the first question.
  void retry() => state = const QuizState();
}
