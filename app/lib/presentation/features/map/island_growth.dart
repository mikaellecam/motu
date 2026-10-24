/// Actions & ETF as far as the lessons have greened it (BRIEF §4.2): [tiles]
/// (as `IslandLayout.tiles`) with only the share [grown] (0 to 1) of their
/// grass green, the tiles nearest the island's middle first, the others
/// sand. Its shape never changes, so the wallet's buildings stand on land.
List<String> grownTiles(List<String> tiles, double grown) {
  final land = [
    for (var j = 0; j < tiles.length; j++)
      for (var i = 0; i < tiles[j].length; i++)
        if (tiles[j][i] != '.') (i, j),
  ];
  if (land.isEmpty) return tiles;
  final cx = land.fold(0.0, (sum, t) => sum + t.$1 + 0.5) / land.length;
  final cy = land.fold(0.0, (sum, t) => sum + t.$2 + 0.5) / land.length;
  double far((int, int) t) =>
      (t.$1 + 0.5 - cx) * (t.$1 + 0.5 - cx) +
      (t.$2 + 0.5 - cy) * (t.$2 + 0.5 - cy);
  final grass =
      [
        for (final t in land)
          if (_grass(tiles[t.$2][t.$1])) t,
      ]..sort(
        (a, b) => switch (far(a).compareTo(far(b))) {
          0 => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1),
          final c => c,
        },
      );
  final green = grass
      .take((grass.length * grown.clamp(0.0, 1.0)).round())
      .toSet();
  return [
    for (var j = 0; j < tiles.length; j++)
      [
        for (var i = 0; i < tiles[j].length; i++)
          _grass(tiles[j][i]) && !green.contains((i, j)) ? 'S' : tiles[j][i],
      ].join(),
  ];
}

/// How many of an island's [trees] have sprouted at [grown] (0 to 1). Nature
/// comes first: a tree with the first lesson, every one by half of them.
int grownTrees(int trees, double grown) =>
    // A hair under, so a share landing on a whole tree does not round up.
    (trees * (grown.clamp(0.0, 1.0) * 2).clamp(0.0, 1.0) - 1e-9).ceil();

/// Every lesson done: the island's landmark stands.
bool landmarkStands(double grown) => grown >= 1;

bool _grass(String tile) => tile == 'g' || tile == 'G';
