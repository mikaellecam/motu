import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/learning/content.dart';
import '../providers.dart';

part 'content.g.dart';

/// The playable island of V1 (BRIEF §4.3).
const actionsEtfIsland = 'actions-etf';

/// The islands the app plays, each with a bundled pack (BRIEF §4.2). The
/// map draws each one open (`IslandLayout.pack`).
const playableIslands = [actionsEtfIsland];

/// The content of [islandId]: bundled, or a newer version once downloaded
/// (ADR-006). Kept for the session; the repository checks once a day.
@Riverpod(keepAlive: true)
Future<ContentPack> contentPack(Ref ref, String islandId) =>
    ref.watch(contentRepositoryProvider).pack(islandId);

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
