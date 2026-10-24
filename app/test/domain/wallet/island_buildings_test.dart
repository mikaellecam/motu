import 'package:decimal/decimal.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);

String show(List<IslandBuilding> buildings) =>
    [for (final b in buildings) '${b.assetId} ${b.height} ${b.built}']
        .join(', ');

void main() {
  test('nothing held, nothing pending: a bare island', () {
    expect(islandBuildings(held: const {}), isEmpty);
  });

  test('one position stands at full height, fully built', () {
    expect(show(islandBuildings(held: {'apple': d('1200')})), 'apple 1 1');
  });

  test('heights against the largest; the five largest, ties by id', () {
    final buildings = islandBuildings(
      held: {
        'world': d('8000'),
        'apple': d('2000'),
        'asml': d('2000'),
        'nvidia': d('4000'),
        'coca-cola': d('1000'),
        'meta': d('400'),
        'tiny': d('100'),
      },
    );
    expect(
      show(buildings),
      'world 1 1, nvidia 0.5 1, apple 0.25 1, asml 0.25 1, '
      'coca-cola 0.125 1',
    );
  });

  test('a kept asset takes the last place when it would not rank', () {
    final held = {
      'world': d('8000'),
      'nvidia': d('4000'),
      'apple': d('2000'),
      'asml': d('2000'),
      'coca-cola': d('1000'),
      'tiny': d('100'),
    };
    expect(
      show(islandBuildings(held: held, keep: 'tiny')),
      'world 1 1, nvidia 0.5 1, apple 0.25 1, asml 0.25 1, tiny 0.0125 1',
    );
    // Already among the five, or not on the island at all: no change.
    final five = show(islandBuildings(held: held));
    expect(show(islandBuildings(held: held, keep: 'apple')), five);
    expect(show(islandBuildings(held: held, keep: 'meta')), five);
  });

  test('a pending buy of a new asset: a construction site, nothing built', () {
    expect(
      show(
        islandBuildings(
          held: {'world': d('1000')},
          pending: {'apple': d('500')},
        ),
      ),
      'world 1 1, apple 0.5 0',
    );
  });

  test('a pending buy on a held asset raises it; the built part is what is '
      'held', () {
    expect(
      show(
        islandBuildings(
          held: {'world': d('1000')},
          pending: {'world': d('250')},
        ),
      ),
      'world 1 0.8',
    );
  });

  test('a pending buy can take a slot from a smaller holding', () {
    final buildings = islandBuildings(
      held: {
        for (final id in ['a', 'b', 'c', 'd', 'e']) id: d('100'),
      },
      pending: {'f': d('150')},
    );
    expect(buildings.first.assetId, 'f');
    expect(buildings, hasLength(5));
    expect([for (final b in buildings) b.assetId], isNot(contains('e')));
  });

  test('zero or negative amounts build nothing', () {
    expect(
      islandBuildings(held: {'a': Decimal.zero}, pending: {'b': d('-5')}),
      isEmpty,
    );
  });

  test('equal buildings are equal', () {
    expect(
      islandBuildings(held: {'a': d('1')}),
      islandBuildings(held: {'a': d('3')}),
    );
  });
}
