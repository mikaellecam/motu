import 'node.dart';
import 'path.dart';
import 'profile.dart';
import 'profile_rules.dart';

/// The one action the map's next-step card recommends (BRIEF §4.2).
sealed class NextStep {
  const NextStep();
}

final class ReadMoment extends NextStep {
  const ReadMoment(this.momentId);
  final String momentId;

  @override
  bool operator ==(Object other) =>
      other is ReadMoment && other.momentId == momentId;
  @override
  int get hashCode => momentId.hashCode;
}

final class OpenGlossary extends NextStep {
  const OpenGlossary(this.termId);
  final String termId;

  @override
  bool operator ==(Object other) =>
      other is OpenGlossary && other.termId == termId;
  @override
  int get hashCode => termId.hashCode;
}

final class PlayNode extends NextStep {
  const PlayNode(this.nodeId);
  final String nodeId;

  @override
  bool operator ==(Object other) => other is PlayNode && other.nodeId == nodeId;
  @override
  int get hashCode => nodeId.hashCode;
}

final class DoMission extends NextStep {
  const DoMission(this.nodeId);
  final String nodeId;

  @override
  bool operator ==(Object other) =>
      other is DoMission && other.nodeId == nodeId;
  @override
  int get hashCode => nodeId.hashCode;
}

final class ContinueTrip extends NextStep {
  const ContinueTrip(this.walletId);
  final String walletId;

  @override
  bool operator ==(Object other) =>
      other is ContinueTrip && other.walletId == walletId;
  @override
  int get hashCode => walletId.hashCode;
}

final class OpenLiveWallet extends NextStep {
  const OpenLiveWallet();

  @override
  bool operator ==(Object other) => other is OpenLiveWallet;
  @override
  int get hashCode => 0;
}

final class LearningState {
  const LearningState({
    required this.profile,
    required this.path,
    required this.completedOn,
    required this.today,
    required this.discoveredTerms,
    required this.unreadMoments,
    required this.openTrips,
  });

  final Profile profile;

  /// The island's nodes, in order.
  final List<IslandNode> path;

  /// Completed node id → when; compared with [today] by calendar day.
  final Map<String, DateTime> completedOn;
  final DateTime today;
  final Set<String> discoveredTerms;

  /// Companion moment ids not read yet, oldest first.
  final List<String> unreadMoments;

  /// Trip wallet ids still running.
  final List<String> openTrips;
}

/// Picks the next step, first match wins (decided 2026-10-07):
///
/// 1. an unread companion moment;
/// 2. the safety-cushion sheet, for users without savings who haven't read it;
/// 3. the current node if it is a mission;
/// 4. the current lesson node, while fewer nodes than the pacing were
///    completed today;
/// 5. an open trip;
/// 6. the live wallet.
///
/// The current node is the first not completed in path order: the forced
/// node 1 (Livret savings), then from the starting node to the end, then the
/// nodes skipped before it.
NextStep nextStep(LearningState s) {
  if (s.unreadMoments.isNotEmpty) return ReadMoment(s.unreadMoments.first);
  if (cushionFirst(s.profile) && !s.discoveredTerms.contains(cushionTerm)) {
    return const OpenGlossary(cushionTerm);
  }
  final current = currentNode(s.profile, s.path, s.completedOn.keys.toSet());
  if (current != null) {
    if (current.type == NodeType.mission) return DoMission(current.id);
    final doneToday = s.completedOn.values
        .where(
          (d) =>
              d.year == s.today.year &&
              d.month == s.today.month &&
              d.day == s.today.day,
        )
        .length;
    if (doneToday < pacing(s.profile)) return PlayNode(current.id);
  }
  if (s.openTrips.isNotEmpty) return ContinueTrip(s.openTrips.first);
  return const OpenLiveWallet();
}
