import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/companion_repository.dart';
import '../../domain/learning/content.dart';
import '../../domain/learning/next_step.dart';
import '../../domain/wallet/wallet.dart';
import '../companion/companion.dart';
import '../providers.dart';
import '../wallet/wallets_list.dart' show walletSummariesProvider;
import 'content.dart';
import 'glossary.dart' show glossaryProgressProvider;

part 'next_step_card.g.dart';

/// The map's next-step card (BRIEF §4.2): the one step, and what it names.
final class NextStepView {
  const NextStepView(this.step, {this.title, this.tripName, this.moment});

  final NextStep step;

  /// The companion moment it opens.
  final ActiveMoment? moment;

  /// The lesson, mission or glossary term it opens.
  final Localized? title;

  /// The trip it resumes.
  final String? tripName;
}

/// Completed node id → first completion, then every change.
@riverpod
Stream<Map<String, DateTime>> completions(Ref ref) =>
    ref.watch(profileRepositoryProvider).watchCompletions();

/// `nextStep` over the user's state, again whenever a lesson is completed, a
/// term opened or a wallet changes. Null before the questionnaire.
@riverpod
Future<NextStepView?> nextStepView(Ref ref) async {
  // Every dependency is read before the first await.
  final profiles = ref.watch(profileRepositoryProvider);
  final now = ref.watch(liveClockProvider).now().toLocal();
  final packF = ref.watch(contentPackProvider(actionsEtfIsland).future)
    ..ignore();
  final doneF = ref.watch(completionsProvider.future)..ignore();
  final termsF = ref.watch(glossaryProgressProvider.future)..ignore();
  final walletsF = ref.watch(walletSummariesProvider.future)..ignore();
  final momentsF = ref.watch(activeMomentsProvider.future)..ignore();
  final profile = await profiles.load();
  if (profile == null) return null;
  final pack = await packF;
  final done = await doneF;
  final terms = await termsF;
  final moments = await momentsF;
  final trips = [
    for (final w in await walletsF)
      if (w.kind == WalletKind.trip && w.status != WalletStatus.finished) w,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final step = nextStep(
    LearningState(
      profile: profile,
      path: pack.path,
      // The pacing counts the lessons of the user's day.
      completedOn: {
        for (final MapEntry(:key, :value) in done.entries) key: value.toLocal(),
      },
      today: now,
      discoveredTerms: terms.keys.toSet(),
      unreadMoments: [for (final m in moments) '${m.id}'],
      openTrips: [for (final t in trips) t.id],
    ),
  );
  Localized? nodeTitle(String id) =>
      pack.nodes.where((n) => n.id == id).firstOrNull?.title;
  return switch (step) {
    PlayNode(:final nodeId) ||
    DoMission(:final nodeId) => NextStepView(step, title: nodeTitle(nodeId)),
    OpenGlossary(:final termId) => NextStepView(
      step,
      title: pack.glossary[termId]?.title,
    ),
    ContinueTrip(:final walletId) => NextStepView(
      step,
      tripName: trips.firstWhere((t) => t.id == walletId).name,
    ),
    ReadMoment(:final momentId) => NextStepView(
      step,
      moment: moments.firstWhere((m) => '${m.id}' == momentId),
    ),
    OpenLiveWallet() => NextStepView(step),
  };
}
