import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/companion_repository.dart';
import '../../domain/learning/content.dart';
import '../learning/content.dart';
import '../learning/node_player.dart' show termTitles;
import '../providers.dart';

part 'companion.g.dart';

/// Companion moments not read yet (BRIEF §4.12), oldest first, across
/// wallets; then every change.
@riverpod
Stream<List<ActiveMoment>> activeMoments(Ref ref) =>
    ref.watch(companionRepositoryProvider).watchActive();

/// The card a wallet shows: its oldest moment not read yet; with [assetId],
/// the oldest about that asset (the asset page). Null when there is none.
@riverpod
Future<ActiveMoment?> walletMoment(
  Ref ref,
  String walletId,
  String? assetId,
) async => (await ref.watch(activeMomentsProvider.future))
    .where(
      (m) =>
          m.walletId == walletId && (assetId == null || m.assetId == assetId),
    )
    .firstOrNull;

/// What a card names besides its moment: assets, glossary terms, lessons.
final class CompanionNames {
  const CompanionNames({
    required this.assets,
    required this.terms,
    required this.lessons,
  });

  final Map<String, String> assets;
  final Map<String, Localized> terms;
  final Map<String, Localized> lessons;
}

@riverpod
Future<CompanionNames> companionNames(Ref ref) async {
  final market = ref.watch(marketRepositoryProvider);
  final now = ref.watch(liveClockProvider).now();
  final packF = ref.watch(contentPackProvider(actionsEtfIsland).future)
    ..ignore();
  final assets = await market.assets(asOf: now);
  final pack = await packF;
  return CompanionNames(
    assets: {for (final a in assets) a.id: a.name},
    terms: termTitles(pack),
    lessons: {for (final n in pack.nodes) n.id: n.title},
  );
}

/// « J'ai compris »: the moment is read; the card goes everywhere at once.
@riverpod
class CompanionActions extends _$CompanionActions {
  @override
  void build() {}

  Future<void> dismiss(ActiveMoment moment) => ref
      .read(companionRepositoryProvider)
      .dismiss(moment.id, ref.read(liveClockProvider).now().toUtc());
}
