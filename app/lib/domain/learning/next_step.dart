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
    this.before = const [],
    required this.path,
    this.pathOpen = true,
    this.after = const [],
    required this.completedOn,
    required this.today,
    required this.discoveredTerms,
    required this.unreadMoments,
    required this.openTrips,
  });

  final Profile profile;

  /// Actions & ETF's nodes, in order: the questionnaire's start applies to
  /// them (§4.1).
  final List<IslandNode> path;

  /// Whether [path]'s lessons are open yet (`islandOpen`, M12-7).
  final bool pathOpen;

  /// Another island's nodes, walked from its first before [path] (Les bases
  /// for a beginner) or [after] it (for those who skip it, M12-7).
  final List<IslandNode> before;
  final List<IslandNode> after;

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
/// 2. the current node if it is a mission;
/// 3. the current lesson node, while fewer nodes than the pacing were
///    completed today;
/// 4. an open trip;
/// 5. the live wallet.
///
/// The current node is the first not completed of [LearningState.before],
/// then of the path if open (the forced node 1 for Livret savings, then from
/// the starting node to the end, then the nodes skipped before it), then of
/// [LearningState.after]. Decided 2026-10-28: no safety-cushion sheet first
/// any more, Les bases' first lesson is about it.
NextStep nextStep(LearningState s) {
  if (s.unreadMoments.isNotEmpty) return ReadMoment(s.unreadMoments.first);
  final done = s.completedOn.keys.toSet();
  final current =
      currentNode(null, s.before, done) ??
      (s.pathOpen ? currentNode(s.profile, s.path, done) : null) ??
      currentNode(null, s.after, done);
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
