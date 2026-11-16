import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/learning/content.dart';
import '../../domain/learning/path.dart';
import '../../domain/learning/profile.dart';
import '../../domain/learning/profile_rules.dart';
import '../providers.dart';

part 'content.g.dart';

/// The playable island of V1 (BRIEF §4.3).
const actionsEtfIsland = 'actions-etf';

/// Money before investing (M12, BRIEF §4.3).
const lesBasesIsland = 'les-bases';

/// The islands to come (BRIEF §4.2): on the map, not playable yet; their
/// gates are recorded already, and Les bases' port opens their sea lines.
const realEstateIsland = 'real-estate';
const tradingIsland = 'trading';
const cryptoIsland = 'crypto';

/// The islands the app plays, each with a bundled pack (BRIEF §4.2). The
/// map draws each one open (`IslandLayout.pack`).
const playableIslands = [lesBasesIsland, actionsEtfIsland];

/// The content of [islandId]: bundled, or a newer version once downloaded
/// (ADR-006). Kept for the session; the repository checks once a day.
@Riverpod(keepAlive: true)
Future<ContentPack> contentPack(Ref ref, String islandId) =>
    ref.watch(contentRepositoryProvider).pack(islandId);

/// The lessons each island's lessons wait for (decided 2026-10-28, M12-7): Les
/// bases comes first, and Actions & ETF opens after its fifth lesson. Here
/// rather than in `island.json`, since a published version never changes
/// (ADR-006); it moves into the pack with Actions & ETF's next version. The
/// islands to come wait as BRIEF §4.2 records.
const islandRequires = {
  actionsEtfIsland: ['lb.cushion-2020'],
  realEstateIsland: ['lb.loan-cost'],
  tradingIsland: ['lb.spot-the-scam', 'ae.checkpoint-1'],
  cryptoIsland: ['lb.spot-the-scam', 'ae.risk-ladder'],
};

/// The sea lines open out of Les bases' port (M13-3), by island: Actions &
/// ETF's once its lessons are open ([actionsEtfOpen], as [lessonsOpen] says),
/// each island to come's once every lesson it waits for is done.
Set<String> portLines(Set<String> completed, {required bool actionsEtfOpen}) =>
    {
      if (actionsEtfOpen) actionsEtfIsland,
      for (final id in const [realEstateIsland, tradingIsland, cryptoIsland])
        if (islandOpen(
          requires: islandRequires[id]!,
          lessons: const [],
          completed: completed,
        ))
          id,
    };

/// Whether [pack]'s lessons are open (`islandOpen`, M12-7): the questionnaire
/// opens Actions & ETF for those who skip Les bases.
bool lessonsOpen(ContentPack pack, Set<String> completed, Profile? profile) =>
    islandOpen(
      requires: islandRequires[pack.id] ?? const [],
      lessons: [for (final n in pack.nodes) n.id],
      completed: completed,
      opened:
          pack.id == actionsEtfIsland &&
          profile != null &&
          skipsTheBasics(profile),
    );

/// Every playable island's pack, in [playableIslands]' order: a lesson or a
/// term is looked up in all of them (M12-1).
@Riverpod(keepAlive: true)
Future<List<ContentPack>> contentPacks(Ref ref) => Future.wait([
  for (final id in playableIslands) ref.watch(contentPackProvider(id).future),
]);

/// Every island's terms as one glossary: a term lives in one pack, and a
/// lesson of any island may link it (`contentcheck` keeps ids unique).
Map<String, GlossaryTerm> glossaryOf(List<ContentPack> packs) => {
  for (final pack in packs) ...pack.glossary,
};

/// [glossaryOf] every playable island.
@riverpod
Future<Map<String, GlossaryTerm>> glossaryTerms(Ref ref) async =>
    glossaryOf(await ref.watch(contentPacksProvider.future));
