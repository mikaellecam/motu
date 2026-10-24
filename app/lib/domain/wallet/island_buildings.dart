import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';

/// A building of the living island (BRIEF §4.2, §10.5): an asset of the live
/// wallet, as tall as its value against the largest.
final class IslandBuilding {
  const IslandBuilding(
    this.assetId, {
    required this.height,
    required this.built,
  });

  final String assetId;

  /// Its value, with what pending buys add, over the largest's: 0 < h ≤ 1.
  final Decimal height;

  /// The part standing: what is held over that total. Below 1 while a buy is
  /// under construction; 0 for an asset not held yet.
  final Decimal built;

  @override
  bool operator ==(Object other) =>
      other is IslandBuilding &&
      other.assetId == assetId &&
      other.height == height &&
      other.built == built;

  @override
  int get hashCode => Object.hash(assetId, height, built);
}

/// The [slots] largest assets of [held] (market values) and [pending] (what
/// pending buys add, in the same currency), largest first, ties by id.
/// Amounts that are not positive build nothing. [keep], when on the island
/// but not among them, takes the last place (the building an order raises).
List<IslandBuilding> islandBuildings({
  required Map<String, Decimal> held,
  Map<String, Decimal> pending = const {},
  int slots = 5,
  String? keep,
}) {
  final standing = {
    for (final MapEntry(:key, :value) in held.entries)
      if (value > Decimal.zero) key: value,
  };
  final totals = {...standing};
  for (final MapEntry(:key, :value) in pending.entries) {
    if (value > Decimal.zero) {
      totals[key] = (totals[key] ?? Decimal.zero) + value;
    }
  }
  if (totals.isEmpty) return const [];
  final ranked = totals.entries.toList()
    ..sort((a, b) {
      final bySize = b.value.compareTo(a.value);
      return bySize != 0 ? bySize : a.key.compareTo(b.key);
    });
  final largest = ranked.first.value;
  var shown = ranked.take(slots).toList();
  final kept = ranked.where((e) => e.key == keep);
  if (kept.isNotEmpty && !shown.contains(kept.first)) {
    shown = [...shown.take(slots - 1), kept.first];
  }
  return [
    for (final MapEntry(:key, :value) in shown)
      IslandBuilding(
        key,
        height: ratio(value, largest),
        built: ratio(standing[key] ?? Decimal.zero, value),
      ),
  ];
}
