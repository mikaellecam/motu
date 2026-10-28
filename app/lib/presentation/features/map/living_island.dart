import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/wallet/island_buildings.dart';

/// A building as one frame of the living island draws it (BRIEF §10.5).
@immutable
final class DrawnBuilding {
  const DrawnBuilding({
    required this.height,
    required this.built,
    required this.ghost,
  });

  /// Its full height, in height units; 0 draws nothing.
  final double height;

  /// The share standing, 0 to 1; the rest shows as its ghost.
  final double built;

  /// How visible the ghost of its finished volume is, 0 to 1: shown while a
  /// buy raises it (M9-45).
  final double ghost;

  @override
  bool operator ==(Object other) =>
      other is DrawnBuilding &&
      other.height == height &&
      other.built == built &&
      other.ghost == ghost;

  @override
  int get hashCode => Object.hash(height, built, ghost);

  @override
  String toString() => 'DrawnBuilding($height, $built, $ghost)';
}

/// The smallest and the tallest building, in height units: one block to
/// four, as in the art direction's skyline.
const minBuildingHeight = 1.0;
const maxBuildingHeight = 4.0;

/// [buildings] as they stand: the largest at full height, every one at least
/// [minBuildingHeight], the ghost of those a buy is still raising.
List<DrawnBuilding> drawnBuildings(List<IslandBuilding> buildings) => [
  for (final b in buildings)
    DrawnBuilding(
      height:
          minBuildingHeight +
          (maxBuildingHeight - minBuildingHeight) * b.height.toDouble(),
      built: b.built.toDouble(),
      ghost: b.built < Decimal.one ? 1 : 0,
    ),
];

const _heights = Interval(0, 0.6, curve: Curves.easeInOut);
const _rising = Interval(0.3, 0.9, curve: Curves.easeOut);
const _ghostIn = Interval(0, 0.15);
const _ghostOut = Interval(0.85, 1);

/// The island between [from] and [to] at [t] (0 to 1), in three stages
/// (BRIEF §10.5): heights grow or shrink, then what a filled buy built
/// rises into its ghost, then a completed building's ghost fades. A new
/// construction shows its ghost at once.
List<DrawnBuilding> islandFrame(
  List<DrawnBuilding> from,
  List<DrawnBuilding> to,
  double t,
) => [
  for (var i = 0; i < math.max(from.length, to.length); i++)
    _between(i < from.length ? from[i] : null, i < to.length ? to[i] : null, t),
];

DrawnBuilding _between(DrawnBuilding? start, DrawnBuilding? end, double t) {
  // A spot that was empty grows from the ground as it will stand; one that
  // empties sinks as it stood.
  final a = start ?? _flat(end!);
  final b = end ?? _flat(start!);
  double lerp(double x, double y, Interval stage) =>
      x + (y - x) * stage.transform(t);
  return DrawnBuilding(
    height: lerp(a.height, b.height, _heights),
    built: lerp(a.built, b.built, _rising),
    ghost: lerp(a.ghost, b.ghost, b.ghost < a.ghost ? _ghostOut : _ghostIn),
  );
}

DrawnBuilding _flat(DrawnBuilding b) =>
    DrawnBuilding(height: 0, built: b.built, ghost: b.ghost);
