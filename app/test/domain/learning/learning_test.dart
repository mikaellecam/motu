import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/learning/missions.dart';
import 'package:finance_companion/domain/learning/next_step.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:finance_companion/domain/learning/profile_rules.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);

Profile profile({
  Goal goal = Goal.longTerm,
  DropReaction drop = DropReaction.wait,
  Knowledge knowledge = Knowledge.nothing,
  Savings savings = Savings.currentAccount,
  WeeklyTime time = WeeklyTime.fifteen,
}) => Profile(
  goal: goal,
  dropReaction: drop,
  knowledge: knowledge,
  savings: savings,
  weeklyTime: time,
);

/// The Actions & ETF island (BRIEF §4.3).
const island = [
  IslandNode('ae.livret-vs-etf', NodeType.predictReveal),
  IslandNode('ae.fees-toy', NodeType.toy),
  IslandNode('ae.mission-first-etf', NodeType.mission),
  IslandNode('ae.apple-vs-world-2022', NodeType.predictReveal),
  IslandNode('ae.march-2020', NodeType.decision),
  IslandNode('ae.risk-ladder', NodeType.sort),
  IslandNode('ae.compound-toy', NodeType.toy),
  IslandNode('ae.mission-three-regions', NodeType.mission),
  IslandNode('ae.dollar-trap', NodeType.predictReveal),
  IslandNode('ae.calm-portfolio', NodeType.buildPuzzle),
  IslandNode('ae.mission-dca', NodeType.mission),
  IslandNode('ae.checkpoint-1', NodeType.checkpoint),
];

final today = DateTime.utc(2026, 10, 7);
final yesterday = DateTime.utc(2026, 10, 6);

void main() {
  group('profile rules (BRIEF §4.1)', () {
    test('Q1 → default horizon', () {
      for (final (goal, years) in [
        (Goal.under3Years, 2),
        (Goal.from3To8Years, 5),
        (Goal.longTerm, 15),
        (Goal.discovering, 10),
      ]) {
        expect(
          defaultHorizonYears(profile(goal: goal)),
          years,
          reason: '$goal',
        );
      }
    });

    test('Q2 → risk comfort, "don\'t know" counts as medium', () {
      for (final (drop, comfort) in [
        (DropReaction.sellAll, RiskComfort.low),
        (DropReaction.wait, RiskComfort.medium),
        (DropReaction.buyMore, RiskComfort.high),
        (DropReaction.dontKnow, RiskComfort.medium),
      ]) {
        expect(riskComfort(profile(drop: drop)), comfort, reason: '$drop');
      }
    });

    test('Q3 → starting node and initial UI level', () {
      for (final (knowledge, node, level) in [
        (Knowledge.nothing, 1, 1),
        (Knowledge.stocks, 1, 1),
        (Knowledge.etfs, 3, 1),
        (Knowledge.alreadyInvesting, 4, 2),
      ]) {
        final p = profile(knowledge: knowledge);
        expect(startingNode(p), node, reason: '$knowledge');
        expect(initialUiLevel(p), level, reason: '$knowledge');
      }
    });

    test('Q4: Livret savings force node 1 first; no savings start with the cushion', () {
      for (final (savings, forced, cushion, reason) in [
        (Savings.livret, 1, false, StartReason.livretSavings),
        (Savings.currentAccount, null, false, StartReason.knowledge),
        (Savings.invested, null, false, StartReason.knowledge),
        (Savings.none, null, true, StartReason.noSavings),
      ]) {
        final p = profile(savings: savings, knowledge: Knowledge.etfs);
        expect(forcedFirstNode(p), forced, reason: '$savings');
        expect(cushionFirst(p), cushion, reason: '$savings');
        expect(startReason(p), reason, reason: '$savings');
      }
    });

    test('Q5 → pacing', () {
      for (final (time, perDay) in [
        (WeeklyTime.five, 1),
        (WeeklyTime.fifteen, 2),
        (WeeklyTime.thirtyPlus, 3),
      ]) {
        expect(pacing(profile(time: time)), perDay, reason: '$time');
      }
    });

    test('moment thresholds: only concentration follows risk comfort', () {
      for (final (drop, concentration) in [
        (DropReaction.sellAll, '0.30'),
        (DropReaction.wait, '0.40'),
        (DropReaction.buyMore, '0.40'),
        (DropReaction.dontKnow, '0.40'),
      ]) {
        final t = momentThresholds(profile(drop: drop));
        expect(t.concentration, d(concentration), reason: '$drop');
        expect(t.firstLoss, d('-0.05'));
        expect(t.positionDrop, d('-0.15'));
        expect(t.portfolioDrawdown, d('-0.10'));
        expect(t.idleCash, d('0.25'));
        expect(t.idleCashDays, 30);
        expect(t.panicSellDrop, d('-0.15'));
        expect(t.panicSellWindow, 10);
        expect(t.fxSwingMove, d('0.03'));
        expect(t.fxSwingExposure, d('0.20'));
      }
    });

    test('UI level rises after node 4, then after the checkpoint (§4.15)', () {
      final p = profile();
      Set<String> done(int upTo) => {for (final n in island.take(upTo)) n.id};
      expect(uiLevel(p, island, completed: const {}), 1);
      expect(uiLevel(p, island, completed: done(3)), 1);
      expect(uiLevel(p, island, completed: done(4)), 2);
      expect(uiLevel(p, island, completed: done(12)), 3);
      expect(
        uiLevel(
          profile(knowledge: Knowledge.alreadyInvesting),
          island,
          completed: const {},
        ),
        2,
      );
    });
  });

  group('nextStep (BRIEF §4.2)', () {
    LearningState state({
      Profile? p,
      Map<String, DateTime> completed = const {},
      Set<String> discovered = const {},
      List<String> moments = const [],
      List<String> trips = const [],
    }) => LearningState(
      profile: p ?? profile(),
      path: island,
      completedOn: completed,
      today: today,
      discoveredTerms: discovered,
      unreadMoments: moments,
      openTrips: trips,
    );
    Map<String, DateTime> done(Iterable<int> numbers, DateTime on) => {
      for (final n in numbers) island[n - 1].id: on,
    };

    final cases = <(String, LearningState, NextStep)>[
      ('a fresh start: node 1', state(), const PlayNode('ae.livret-vs-etf')),
      (
        'an unread companion moment comes first',
        state(moments: ['m1', 'm2'], completed: done([1, 2], yesterday)),
        const ReadMoment('m1'),
      ),
      (
        'no savings: the cushion sheet first',
        state(p: profile(savings: Savings.none)),
        const OpenGlossary('matelas-de-securite'),
      ),
      (
        'no savings, cushion read: the path',
        state(
          p: profile(savings: Savings.none),
          discovered: {'matelas-de-securite'},
        ),
        const PlayNode('ae.livret-vs-etf'),
      ),
      (
        'knows ETFs: starts at node 3, a mission',
        state(p: profile(knowledge: Knowledge.etfs)),
        const DoMission('ae.mission-first-etf'),
      ),
      (
        'already investing: starts at node 4',
        state(p: profile(knowledge: Knowledge.alreadyInvesting)),
        const PlayNode('ae.apple-vs-world-2022'),
      ),
      (
        'Livret savings: node 1 before the starting node',
        state(
          p: profile(
            knowledge: Knowledge.alreadyInvesting,
            savings: Savings.livret,
          ),
        ),
        const PlayNode('ae.livret-vs-etf'),
      ),
      (
        'Livret savings, node 1 done: on to the starting node',
        state(
          p: profile(
            knowledge: Knowledge.alreadyInvesting,
            savings: Savings.livret,
          ),
          completed: done([1], yesterday),
        ),
        const PlayNode('ae.apple-vs-world-2022'),
      ),
      (
        'a mission ignores the daily quota',
        state(completed: done([1, 2], today)),
        const DoMission('ae.mission-first-etf'),
      ),
      (
        'quota reached: an open trip',
        state(
          completed: {
            ...done([1, 2, 3], yesterday),
            ...done([4, 5], today),
          },
          trips: ['t1'],
        ),
        const ContinueTrip('t1'),
      ),
      (
        'quota reached, no trip: the live wallet',
        state(
          completed: {
            ...done([1, 2, 3], yesterday),
            ...done([4, 5], today),
          },
        ),
        const OpenLiveWallet(),
      ),
      (
        'quota not reached: the next node',
        state(
          completed: {
            ...done([1, 2, 3], yesterday),
            ...done([4], today),
          },
        ),
        const PlayNode('ae.march-2020'),
      ),
      (
        'after the main path, nodes skipped at the start',
        state(
          p: profile(knowledge: Knowledge.alreadyInvesting),
          completed: done([4, 5, 6, 7, 8, 9, 10, 11, 12], yesterday),
        ),
        const PlayNode('ae.livret-vs-etf'),
      ),
      (
        'everything done: an open trip',
        state(
          completed: done(List.generate(12, (i) => i + 1), yesterday),
          trips: ['t1'],
        ),
        const ContinueTrip('t1'),
      ),
      (
        'everything done, no trip: the live wallet',
        state(completed: done(List.generate(12, (i) => i + 1), yesterday)),
        const OpenLiveWallet(),
      ),
    ];
    for (final (name, s, expected) in cases) {
      test(name, () => expect(nextStep(s), expected));
    }

    test('next steps are values', () {
      final steps = <NextStep Function()>[
        () => ReadMoment('x'.toString()),
        () => OpenGlossary('x'.toString()),
        () => PlayNode('x'.toString()),
        () => DoMission('x'.toString()),
        () => ContinueTrip('x'.toString()),
        () => const OpenLiveWallet(),
      ];
      for (final (i, make) in steps.indexed) {
        expect(make(), make());
        expect(make().hashCode, make().hashCode);
        for (final (j, other) in steps.indexed) {
          if (i != j) expect(make(), isNot(other()));
        }
      }
    });

    test('completions count by calendar day', () {
      // Two nodes at 23:00 yesterday and one this morning: one today.
      final s = state(
        completed: {
          island[0].id: DateTime.utc(2026, 10, 6, 23),
          island[1].id: DateTime.utc(2026, 10, 6, 23),
          island[2].id: DateTime.utc(2026, 10, 7, 8),
        },
      );
      expect(nextStep(s), const PlayNode('ae.apple-vs-world-2022'));
    });
  });

  group('missions (BRIEF §4.3)', () {
    Asset asset(String id, AssetType type, String region) => Asset(
      id: id,
      symbol: id.toUpperCase(),
      name: id,
      type: type,
      exchange: Exchange.euronext,
      currency: Currency.eur,
      region: region,
      listingDate: DateTime.utc(2000),
    );
    final world = asset('cw8', AssetType.etf, 'world');
    final lvmh = asset('mc', AssetType.stock, 'europe');
    final airbus = asset('air', AssetType.stock, 'europe');
    final apple = asset('aapl', AssetType.stock, 'us');

    final cases = <(String, List<Asset>, bool, Set<String>)>[
      ('nothing held', const [], false, const {}),
      ('a stock is not an ETF', [lvmh], false, const {}),
      ('one ETF', [world], false, {'ae.mission-first-etf'}),
      (
        'two regions are not three',
        [world, lvmh, airbus],
        false,
        {'ae.mission-first-etf'},
      ),
      (
        'a world ETF counts as one region',
        [world, lvmh, apple],
        false,
        {'ae.mission-first-etf', 'ae.mission-three-regions'},
      ),
      (
        'three regions without an ETF',
        [lvmh, apple, asset('em', AssetType.stock, 'emerging')],
        false,
        {'ae.mission-three-regions'},
      ),
      ('an active DCA plan in any wallet', const [], true, {'ae.mission-dca'}),
    ];
    for (final (name, holdings, dca, expected) in cases) {
      test(name, () {
        expect(
          completedMissions(
            MissionContext(liveHoldings: holdings, hasActiveDcaPlan: dca),
          ),
          expected,
        );
      });
    }

    test('detectors exist for the three mission nodes', () {
      expect(
        missionDetectors.keys,
        island.where((n) => n.type == NodeType.mission).map((n) => n.id),
      );
    });
  });
}
