import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/content/pack_codec.dart';
import '../../domain/learning/content.dart';
import '../../domain/learning/missions.dart';
import '../../domain/learning/node.dart';
import '../../core/failure.dart';
import '../../data/repositories/market_repository.dart';
import '../providers.dart';
import 'island_path.dart';
import 'node_player.dart';

part 'missions.g.dart';

/// The mission nodes the sandbox satisfies now (BRIEF §4.3), then every
/// change of the live wallet's holdings or of the DCA plans.
@Riverpod(keepAlive: true)
Stream<Set<String>> satisfiedMissions(Ref ref) {
  final wallets = ref.watch(walletRepositoryProvider);
  final market = ref.watch(marketRepositoryProvider);
  final clock = ref.watch(liveClockProvider);
  return wallets.watchMissionFacts().asyncMap(
    (facts) => missionsSatisfiedBy(facts, market, asOf: clock.now()),
  );
}

/// The mission nodes [facts] satisfy: the assets of the live wallet's open
/// positions, whether a DCA plan runs, and the live wallet's Livret A.
Future<Set<String>> missionsSatisfiedBy(
  ({Set<String> liveAssets, bool activePlan, bool livret}) facts,
  MarketRepository market, {
  required DateTime asOf,
}) async {
  final assets = {for (final a in await market.assets(asOf: asOf)) a.id: a};
  return completedMissions(
    MissionContext(
      liveHoldings: [for (final id in facts.liveAssets) ?assets[id]],
      hasActiveDcaPlan: facts.activePlan,
      hasLivretSavings: facts.livret,
    ),
  );
}

/// Saves each mission as done as soon as the sandbox satisfies it, never
/// by a button (BRIEF §4.3). Kept alive from launch (`main`).
@Riverpod(keepAlive: true)
void missionTracker(Ref ref) {
  final profiles = ref.watch(profileRepositoryProvider);
  final clock = ref.watch(liveClockProvider);
  ref.listen(satisfiedMissionsProvider, (_, next) async {
    final satisfied = next.value;
    if (satisfied == null || satisfied.isEmpty) return;
    try {
      final done = await profiles.completedNodes();
      for (final id in satisfied.difference(done)) {
        await profiles.completeNode(id, at: clock.now());
      }
    } on Failure {
      // The next change tries again.
    }
  }, fireImmediately: true);
}

/// A mission node and whether it is done.
final class MissionView {
  const MissionView({
    required this.node,
    required this.mission,
    required this.done,
    this.terms = const {},
  });

  final NodeContent node;
  final MissionNode mission;
  final bool done;
  final Map<String, Localized> terms;
}

@riverpod
Future<MissionView> missionView(Ref ref, String nodeId) async {
  final completed = ref.watch(completedNodesProvider.future);
  final (:node, :pack, :terms) = await lessonOf(ref, nodeId);
  if (node.type != NodeType.mission) throw const NotFoundFailure();
  return MissionView(
    node: node,
    mission: playable(() => decodeMission(node, pack)),
    done: (await completed).contains(nodeId),
    terms: terms,
  );
}
