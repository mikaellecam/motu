import 'package:decimal/decimal.dart';

import 'node.dart';
import 'profile.dart';

/// What the onboarding answers change (BRIEF §4.1). Node numbers are 1-based
/// positions in the Actions & ETF path.

/// Q1: horizon used by projections, DCA defaults and companion wording.
int defaultHorizonYears(Profile p) => switch (p.goal) {
  Goal.under3Years => 2,
  Goal.from3To8Years => 5,
  Goal.longTerm => 15,
  Goal.discovering => 10,
};

enum RiskComfort { low, medium, high }

/// Q2, with "don't know" read as medium.
RiskComfort riskComfort(Profile p) => switch (p.dropReaction) {
  DropReaction.sellAll => RiskComfort.low,
  DropReaction.wait || DropReaction.dontKnow => RiskComfort.medium,
  DropReaction.buyMore => RiskComfort.high,
};

/// Q3: where the path starts.
int startingNode(Profile p) => switch (p.knowledge) {
  Knowledge.nothing || Knowledge.stocks => 1,
  Knowledge.etfs => 3,
  Knowledge.alreadyInvesting => 4,
};

/// Q3 (M12-7): someone who knows ETFs or invests already skips Les bases:
/// Actions & ETF's lessons open at once, and the way starts there.
bool skipsTheBasics(Profile p) =>
    p.knowledge == Knowledge.etfs || p.knowledge == Knowledge.alreadyInvesting;

/// Q3: level of detail shown from the start (§4.15).
int initialUiLevel(Profile p) =>
    p.knowledge == Knowledge.alreadyInvesting ? 2 : 1;

/// Q4: savings on a Livret put node 1, « Livret ou ETF ? », before the
/// starting node of Actions & ETF, flagged as chosen for that answer.
int? forcedFirstNode(Profile p) => p.savings == Savings.livret ? 1 : null;

/// Which answer decided the start, for « On commence par X parce que tu as
/// répondu Y »: on Actions & ETF, Livret savings or what one knows; on Les
/// bases (M12-7), no savings or what one knows.
enum StartReason { knowledge, livretSavings, noSavings }

StartReason startReason(Profile p) => switch (p.savings) {
  Savings.livret when skipsTheBasics(p) => StartReason.livretSavings,
  Savings.none when !skipsTheBasics(p) => StartReason.noSavings,
  _ => StartReason.knowledge,
};

/// Q5: new lesson nodes suggested per day.
int pacing(Profile p) => switch (p.weeklyTime) {
  WeeklyTime.five => 1,
  WeeklyTime.fifteen => 2,
  WeeklyTime.thirtyPlus => 3,
};

/// Companion and pre-trade coach thresholds (BRIEF §4.12). Only
/// concentration follows risk comfort (decided 2026-10-07); the rest are the
/// §4.12 defaults.
final class MomentThresholds {
  MomentThresholds({required this.concentration});

  /// A non-cash position above this share of the wallet.
  final Decimal concentration;

  /// A position below this P&L ratio for the first time.
  final firstLoss = Decimal.parse('-0.05');

  /// A position this far below its peak since purchase.
  final positionDrop = Decimal.parse('-0.15');

  /// The wallet this far below its peak.
  final portfolioDrawdown = Decimal.parse('-0.10');

  /// Cash above this share of the wallet…
  final idleCash = Decimal.parse('0.25');

  /// …for more than this many days.
  final idleCashDays = 30;

  /// A sell within [panicSellWindow] trading days after the position fell
  /// this far.
  final panicSellDrop = Decimal.parse('-0.15');
  final panicSellWindow = 10;

  /// EUR/USD moving more than this in a month…
  final fxSwingMove = Decimal.parse('0.03');

  /// …with more than this share of the wallet in USD.
  final fxSwingExposure = Decimal.parse('0.20');
}

MomentThresholds momentThresholds(Profile p) => MomentThresholds(
  concentration: Decimal.parse(
    riskComfort(p) == RiskComfort.low ? '0.30' : '0.40',
  ),
);

/// UI level (§4.15): 2 after node 4 or for experienced investors, 3 after
/// the checkpoint.
int uiLevel(
  Profile p,
  List<IslandNode> path, {
  required Set<String> completed,
}) {
  if (path.any(
    (n) => n.type == NodeType.checkpoint && completed.contains(n.id),
  )) {
    return 3;
  }
  final afterNode4 = path.length >= 4 && completed.contains(path[3].id);
  return afterNode4 ? 2 : initialUiLevel(p);
}
