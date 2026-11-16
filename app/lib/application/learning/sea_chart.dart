import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/learning/content.dart';
import '../../domain/learning/path.dart';
import 'content.dart';
import 'island_path.dart';

part 'sea_chart.g.dart';

/// Where an island stands on the sea chart (BRIEF §4.2, M13-5).
enum ChartState {
  /// Its lessons are open: it can be boarded.
  open,

  /// Its line from the port is open, but it has no lessons yet (« Bientôt »).
  soon,

  /// Its line waits for lessons not done yet.
  closed,
}

/// The islands on the chart, the port first, in the order of [chartIslands].
const chartIslands = [
  lesBasesIsland,
  actionsEtfIsland,
  tradingIsland,
  realEstateIsland,
  cryptoIsland,
];

/// Each island's state on the chart, and the lessons a closed one waits for
/// (by id, in the order of its gate): the port is always open; a playable
/// island as its path says ([open]); an island to come is « soon » once its
/// line is open (its gates, `portLines`), closed before.
Map<String, (ChartState, List<String>)> chartStates(
  Set<String> completed, {
  required Map<String, bool> open,
}) => {for (final id in chartIslands) id: _state(id, completed, open)};

(ChartState, List<String>) _state(
  String id,
  Set<String> completed,
  Map<String, bool> open,
) {
  if (id == lesBasesIsland || open[id] == true) {
    return (ChartState.open, const []);
  }
  final waits = [
    for (final lesson in islandRequires[id] ?? const <String>[])
      if (!completed.contains(lesson)) lesson,
  ];
  // An island to come with its line open has no lessons to board yet.
  return waits.isEmpty && !open.containsKey(id)
      ? (ChartState.soon, const [])
      : (ChartState.closed, waits);
}

/// An island as the chart shows it: its state, its progress and next lesson
/// once open, what it waits for when closed.
final class ChartIsland {
  const ChartIsland(
    this.id,
    this.state, {
    this.done = 0,
    this.total = 0,
    this.next,
    this.waits = const [],
  });

  final String id;
  final ChartState state;
  final int done, total;

  /// Its next lesson: its number in the island, its title.
  final (int, Localized)? next;

  /// The titles of the lessons it waits for.
  final List<Localized> waits;
}

/// The sea chart: every island, as of the latest completion.
@riverpod
Future<List<ChartIsland>> seaChart(Ref ref) async {
  final completed = ref.watch(completedNodesProvider.future);
  final paths = {
    for (final id in playableIslands)
      id: ref.watch(islandPathProvider(id).future),
  };
  final packs = ref.watch(contentPacksProvider.future);
  final views = {for (final e in paths.entries) e.key: await e.value};
  final titles = {
    for (final pack in await packs)
      for (final n in pack.nodes) n.id: n.title,
  };
  final states = chartStates(
    await completed,
    open: {for (final e in views.entries) e.key: e.value.open},
  );
  return [
    for (final id in chartIslands)
      if (states[id] case (final state, final waits))
        switch (views[id]) {
          final view? => ChartIsland(
            id,
            state,
            done: view.done,
            total: view.nodes.length,
            next: [
              for (final (i, n) in view.nodes.indexed)
                if (n.state == NodeState.current) (i + 1, n.node.title),
            ].firstOrNull,
            waits: [for (final w in waits) ?titles[w]],
          ),
          null => ChartIsland(
            id,
            state,
            waits: [for (final w in waits) ?titles[w]],
          ),
        },
  ];
}
