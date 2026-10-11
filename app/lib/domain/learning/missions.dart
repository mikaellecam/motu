import '../market/asset.dart';
import 'content.dart';

/// What mission detectors look at: the live wallet's open positions, and
/// whether any wallet runs a DCA plan.
final class MissionContext {
  const MissionContext({
    required this.liveHoldings,
    required this.hasActiveDcaPlan,
  });

  /// Assets of the live wallet's open positions.
  final List<Asset> liveHoldings;
  final bool hasActiveDcaPlan;
}

/// Mission nodes complete by themselves when the sandbox shows the behaviour
/// (BRIEF §4.3), never by a button.
const missionDetectors = <String, bool Function(MissionContext)>{
  'ae.mission-first-etf': _ownsAnEtf,
  'ae.mission-three-regions': _threeRegions,
  'ae.mission-dca': _hasDcaPlan,
};

/// Ids of the mission nodes [context] satisfies.
Set<String> completedMissions(MissionContext context) => {
  for (final MapEntry(key: id, value: detect) in missionDetectors.entries)
    if (detect(context)) id,
};

bool _ownsAnEtf(MissionContext c) =>
    c.liveHoldings.any((a) => a.type == AssetType.etf);

/// Distinct regions among the assets held; a world ETF is one region,
/// `world` (decided 2026-10-07).
bool _threeRegions(MissionContext c) =>
    {for (final a in c.liveHoldings) a.region}.length >= 3;

bool _hasDcaPlan(MissionContext c) => c.hasActiveDcaPlan;

/// A `mission` node (BRIEF §4.3): what to do in the sandbox, and where to
/// go to do it. It completes by itself ([missionDetectors]).
final class MissionNode {
  const MissionNode(this.goal, this.place);
  final Localized goal;
  final MissionPlace place;
}

/// Where a mission is done.
enum MissionPlace {
  /// The catalogue, to buy something for the live wallet.
  explorer,

  /// The live wallet.
  wallet,
}
