import 'node.dart';
import 'profile.dart';
import 'profile_rules.dart';

/// Where a node of an island path stands (BRIEF §1: nodes unlock in order).
enum NodeState {
  /// Completed; can be played again.
  done,

  /// The one the path points to (the next-step card's lesson).
  current,

  /// Playable now, after a pending mission (missions do not block).
  open,

  /// Skipped at onboarding (M13-19): playable, but it waits for its turn,
  /// after the rest of the path, and the island does not show it until then.
  skipped,

  /// Waits for the lesson before it.
  locked,
}

/// Whether an island's lessons are open (M12-7): every lesson it [requires]
/// (of any island) is done, or one of its own [lessons] already is, since
/// progress is never taken away, or the questionnaire [opened] it. An island
/// requiring nothing is open.
bool islandOpen({
  required List<String> requires,
  required List<String> lessons,
  required Set<String> completed,
  bool opened = false,
}) =>
    opened ||
    requires.every(completed.contains) ||
    lessons.any(completed.contains);

/// The node the path points to: the first not completed in path order, the
/// forced node 1 (Livret savings) first, then from the starting node to the
/// end, then the nodes skipped before it (§4.1). Null when every node is
/// done. Before the questionnaire the path starts at node 1. A [start] given
/// (1-based) replaces the questionnaire's starting node.
IslandNode? currentNode(
  Profile? profile,
  List<IslandNode> path,
  Set<String> completed, {
  int? start,
}) {
  final from = (start ?? (profile == null ? 1 : startingNode(profile))) - 1;
  final forced = profile == null ? null : forcedFirstNode(profile);
  final order = <IslandNode>{
    if (forced != null && forced <= path.length) path[forced - 1],
    ...path.skip(from),
    ...path.take(from),
  };
  for (final node in order) {
    if (!completed.contains(node.id)) return node;
  }
  return null;
}

/// The state of each node of [path] (decided 2026-10-11): done, the current
/// node, then nodes open while everything from the starting node up to
/// them is done or a pending mission (missions do not block); nodes skipped
/// at onboarding wait for their turn (M13-19). The rest is locked.
List<NodeState> pathStates(
  Profile? profile,
  List<IslandNode> path,
  Set<String> completed, {
  int? start,
}) {
  final from = (start ?? (profile == null ? 1 : startingNode(profile))) - 1;
  final forced = profile == null ? null : forcedFirstNode(profile);
  final current = currentNode(profile, path, completed, start: start);
  final states = <NodeState>[];
  var reachable = true;
  for (final (i, node) in path.indexed) {
    final pending = !completed.contains(node.id);
    states.add(switch (node) {
      _ when !pending => NodeState.done,
      _ when node == current => NodeState.current,
      _ when i < from && i != (forced ?? 0) - 1 => NodeState.skipped,
      _ when i == (forced ?? 0) - 1 || reachable => NodeState.open,
      _ => NodeState.locked,
    });
    // From the starting node on, a lesson not done closes the way.
    if (i >= from && pending && node.type != NodeType.mission) {
      reachable = false;
    }
  }
  return states;
}
