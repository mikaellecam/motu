import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/learning/content.dart';
import '../../domain/learning/path.dart';
import '../providers.dart';
import 'content.dart';

part 'island_path.g.dart';

/// The ids of the completed nodes, then every change.
@riverpod
Stream<Set<String>> completedNodes(Ref ref) =>
    ref.watch(profileRepositoryProvider).watchCompletedNodes();

/// A node of the path and where it stands.
final class PathNode {
  const PathNode(this.node, this.state);
  final NodeContent node;
  final NodeState state;
}

/// An island's path (BRIEF §3: node list, progress), as of the latest
/// completion.
final class IslandPathView {
  const IslandPathView(this.title, this.nodes);
  final Localized title;
  final List<PathNode> nodes;

  int get done => nodes.where((n) => n.state == NodeState.done).length;
}

@riverpod
Future<IslandPathView> islandPath(Ref ref, String islandId) async {
  final profiles = ref.watch(profileRepositoryProvider);
  final pack = ref.watch(contentPackProvider(islandId).future);
  final completed = ref.watch(completedNodesProvider.future);
  final (content, done, profile) = (
    await pack,
    await completed,
    await profiles.load(),
  );
  // The questionnaire's start is Actions & ETF's (BRIEF §4.1): another
  // island starts at its first lesson.
  final states = pathStates(
    islandId == actionsEtfIsland ? profile : null,
    content.path,
    done,
  );
  return IslandPathView(content.title, [
    for (final (i, node) in content.nodes.indexed) PathNode(node, states[i]),
  ]);
}
