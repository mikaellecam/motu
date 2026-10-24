import 'package:finance_companion/presentation/features/map/island_growth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tiles = [
    '.SSS...',
    '.SgGS..',
    'SgGgGS.',
    'SGgGgGS',
    'SgGgGgS',
    'SGgGgS.',
    'SgSSSS.',
    '.S.....',
  ];
  int grass(List<String> rows) =>
      rows.join().split('').where((c) => c == 'g' || c == 'G').length;

  test('no lesson: a sand bank of the same shape; all of them: the art', () {
    final bare = grownTiles(tiles, 0);
    expect(grass(bare), 0);
    expect(
      [for (final r in bare) r.replaceAll('S', 'x')],
      [for (final r in tiles) r.replaceAll(RegExp('[SgG]'), 'x')],
    );
    expect(grownTiles(tiles, 1), tiles);
  });

  test('each step keeps what grew and adds the tiles nearest the centre', () {
    var before = grownTiles(tiles, 0);
    for (var done = 1; done <= 12; done++) {
      final now = grownTiles(tiles, done / 12);
      expect(grass(now), greaterThanOrEqualTo(grass(before)));
      for (var j = 0; j < tiles.length; j++) {
        for (var i = 0; i < tiles[j].length; i++) {
          if (before[j][i] != 'S' || tiles[j][i] == 'S') continue;
          // Not green yet before: may turn green now, as itself.
          expect(now[j][i], anyOf('S', tiles[j][i]));
        }
        for (var i = 0; i < tiles[j].length; i++) {
          if ('gG'.contains(before[j][i])) expect(now[j][i], tiles[j][i]);
        }
      }
      before = now;
    }
    // The first tile to turn green is the one nearest the island's middle.
    final first = grownTiles(tiles, 1 / 21);
    expect(grass(first), 1);
    expect(first[3][3], tiles[3][3]);
  });

  test('nature first: a tree with the first lesson, all of them by half', () {
    expect(grownTrees(5, 0), 0);
    expect(grownTrees(5, 1 / 12), 1);
    expect(grownTrees(5, 2 / 12), 2);
    expect(grownTrees(5, 3 / 12), 3);
    expect(grownTrees(5, 4 / 12), 4);
    expect(grownTrees(5, 5 / 12), 5);
    expect(grownTrees(5, 6 / 12), 5);
    expect(grownTrees(5, 1), 5);
    // Out of range counts as its bound.
    expect(grownTrees(5, -1), 0);
    expect(grownTrees(5, 2), 5);
    expect(grownTiles(tiles, 2), tiles);
  });

  test('the landmark stands once every lesson is done, not before', () {
    expect(landmarkStands(11 / 12), isFalse);
    expect(landmarkStands(0), isFalse);
    expect(landmarkStands(12 / 12), isTrue);
    expect(landmarkStands(2), isTrue);
  });
}
