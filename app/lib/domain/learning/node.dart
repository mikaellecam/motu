/// Node types of an island path (BRIEF §4.3), with their content-pack names.
enum NodeType {
  predictReveal('predict_reveal'),
  toy('toy'),
  decision('decision'),
  sort('sort'),
  buildPuzzle('build_puzzle'),
  mission('mission'),
  checkpoint('checkpoint'),

  /// A checkpoint's questions under a name of their own, inside an island
  /// (Les bases' « Repère l'arnaque », M12-4): it counts as no checkpoint for
  /// the levels.
  quiz('quiz');

  const NodeType(this.json);
  final String json;
}

/// A node's place in an island path.
final class IslandNode {
  const IslandNode(this.id, this.type);
  final String id;
  final NodeType type;
}
