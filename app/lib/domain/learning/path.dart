import 'node.dart';
import 'profile.dart';
import 'profile_rules.dart';

/// Where a node of an island path stands (BRIEF §1: nodes unlock in order).
enum NodeState {
  /// Completed; can be played again.
  done,

  /// The one the path points to (the next-step card's lesson).
  current,

  /// Playable now: skipped at onboarding, or after a pending mission.
  open,

  /// Waits for the lesson before it.
  locked,
}

/// The node the path points to: the first not completed in path order, the
/// forced node 1 (Livret savings) first, then from the starting node to the
/// end, then the nodes skipped before it (§4.1). Null when every node is
/// done. Before the questionnaire the path starts at node 1.
IslandNode? currentNode(
  Profile? profile,
  List<IslandNode> path,
  Set<String> completed,
) {
  final start = profile == null ? 0 : startingNode(profile) - 1;
  final forced = profile == null ? null : forcedFirstNode(profile);
  final order = <IslandNode>{
    if (forced != null && forced <= path.length) path[forced - 1],
    ...path.skip(start),
    ...path.take(start),
  };
  for (final node in order) {
    if (!completed.contains(node.id)) return node;
  }
  return null;
}

/// The state of each node of [path] (decided 2026-10-11): done, the current
/// node, then nodes open while everything from the starting node up to
/// them is done or a pending mission (missions do not block); nodes skipped
/// at onboarding stay open. The rest is locked.
List<NodeState> pathStates(
  Profile? profile,
  List<IslandNode> path,
  Set<String> completed,
) {
  final start = profile == null ? 0 : startingNode(profile) - 1;
  final forced = profile == null ? null : forcedFirstNode(profile);
  final current = currentNode(profile, path, completed);
  final states = <NodeState>[];
  var reachable = true;
  for (final (i, node) in path.indexed) {
    final pending = !completed.contains(node.id);
    states.add(switch (node) {
      _ when !pending => NodeState.done,
      _ when node == current => NodeState.current,
      _ when i < start || i == (forced ?? 0) - 1 || reachable => NodeState.open,
      _ => NodeState.locked,
    });
    // From the starting node on, a lesson not done closes the way.
    if (i >= start && pending && node.type != NodeType.mission) {
      reachable = false;
    }
  }
  return states;
}
