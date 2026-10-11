import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/wallet_repository.dart';
import '../../domain/learning/content.dart';
import '../../domain/wallet/wallet.dart';
import '../learning/content.dart';
import '../providers.dart';

part 'wallets_list.g.dart';

/// A lesson the user completed that opens a trip (decided 2026-10-11:
/// completed lessons only).
final class BridgeSuggestion {
  const BridgeSuggestion(this.nodeId, this.title, this.bridge);
  final String nodeId;
  final Localized title;
  final TripBridge bridge;
}

/// The Portefeuille tab (BRIEF §3): the live wallet, the trips newest first,
/// and the lessons to replay as a trip.
final class WalletsList {
  const WalletsList({
    required this.live,
    required this.trips,
    required this.suggestions,
  });

  final WalletSummary? live;
  final List<WalletSummary> trips;
  final List<BridgeSuggestion> suggestions;
}

/// The bridges of the [completed] nodes of [pack], in path order.
List<BridgeSuggestion> bridgeSuggestions(
  ContentPack pack, {
  required Set<String> completed,
}) => [
  for (final node in pack.nodes)
    if (node.bridge case final bridge? when completed.contains(node.id))
      BridgeSuggestion(node.id, node.title, bridge),
];

@riverpod
Stream<List<WalletSummary>> walletSummaries(Ref ref) =>
    ref.watch(walletRepositoryProvider).watchWallets();

@riverpod
Stream<Set<String>> completedNodes(Ref ref) =>
    ref.watch(profileRepositoryProvider).watchCompletedNodes();

/// Rebuilt whenever a wallet or a lesson's progress changes.
@riverpod
Future<WalletsList> walletsList(Ref ref) async {
  final pack = ref.watch(contentPackProvider(actionsEtfIsland).future);
  final completed = ref.watch(completedNodesProvider.future);
  final all = await ref.watch(walletSummariesProvider.future);
  return WalletsList(
    live: all.where((w) => w.kind == WalletKind.live).firstOrNull,
    trips: [
      for (final w in all.reversed)
        if (w.kind == WalletKind.trip) w,
    ],
    suggestions: bridgeSuggestions(await pack, completed: await completed),
  );
}
