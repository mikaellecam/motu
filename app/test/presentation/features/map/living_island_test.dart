import 'package:decimal/decimal.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';
import 'package:finance_companion/presentation/features/map/living_island.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  const tall = DrawnBuilding(height: 2.5, built: 1, ghost: 0);
  const site = DrawnBuilding(height: 1.5, built: 0, ghost: 1);
  const done = DrawnBuilding(height: 1.5, built: 1, ghost: 0);

  test('the largest at full height, the smallest above the ground, a buy '
      'under construction inside its ghost', () {
    expect(
      drawnBuildings([
        IslandBuilding('world', height: Decimal.one, built: Decimal.one),
        IslandBuilding('apple', height: Decimal.zero, built: d('0.5')),
      ]),
      const [
        DrawnBuilding(height: maxBuildingHeight, built: 1, ghost: 0),
        DrawnBuilding(height: minBuildingHeight, built: 0.5, ghost: 1),
      ],
    );
    expect(drawnBuildings(const []), isEmpty);
  });

  test('ends where it starts: the first state, then the last', () {
    expect(islandFrame(const [tall], const [site], 0), const [tall]);
    expect(islandFrame(const [tall], const [site], 1), const [site]);
  });

  test('stage 1: heights move first, the built part not yet', () {
    final [b] = islandFrame(
      const [DrawnBuilding(height: 1, built: 0, ghost: 1)],
      const [DrawnBuilding(height: 2, built: 1, ghost: 0)],
      0.25,
    );
    expect(b.height, inExclusiveRange(1, 2));
    expect(b.built, 0);
    expect(b.ghost, 1);
  });

  test('a filled buy: it rises into its ghost, then the ghost fades', () {
    final [rising] = islandFrame(const [site], const [done], 0.6);
    expect(rising.built, inExclusiveRange(0, 1));
    expect(rising.ghost, 1, reason: 'still standing while it rises');
    final [finishing] = islandFrame(const [site], const [done], 0.95);
    expect(finishing.built, 1);
    expect(finishing.ghost, inExclusiveRange(0, 1));
  });

  test('a new buy shows its ghost at once and grows from the ground', () {
    final [b] = islandFrame(const [], const [site], 0.2);
    expect(b.ghost, 1);
    expect(b.height, inExclusiveRange(0, 1.5));
    expect(b.built, 0);
  });

  test('a building sold sinks to the ground', () {
    final frames = [
      for (final t in [0.0, 0.3, 0.6, 1.0])
        islandFrame(const [tall], const [], t),
    ];
    expect([for (final [b] in frames) b.height], [2.5, greaterThan(0), 0, 0]);
  });
}
