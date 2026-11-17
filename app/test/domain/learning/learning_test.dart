import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/learning/missions.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:finance_companion/domain/learning/path.dart';
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
}) => Profile(
  goal: goal,
  dropReaction: drop,
  knowledge: knowledge,
  savings: savings,
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

    test('Q4: Livret savings force node 1 first; the answer the start '
        'follows (M12-7)', () {
      for (final (knowledge, savings, forced, reason) in [
        // Starting on Actions & ETF: Livret savings bring node 1 first.
        (Knowledge.etfs, Savings.livret, 1, StartReason.livretSavings),
        (Knowledge.etfs, Savings.currentAccount, null, StartReason.knowledge),
        (Knowledge.etfs, Savings.invested, null, StartReason.knowledge),
        (Knowledge.etfs, Savings.none, null, StartReason.knowledge),
        // Starting on Les bases: no savings is why, else what one knows.
        (Knowledge.nothing, Savings.none, null, StartReason.noSavings),
        (Knowledge.nothing, Savings.livret, 1, StartReason.knowledge),
        (Knowledge.stocks, Savings.currentAccount, null, StartReason.knowledge),
      ]) {
        final p = profile(savings: savings, knowledge: knowledge);
        expect(forcedFirstNode(p), forced, reason: '$knowledge $savings');
        expect(startReason(p), reason, reason: '$knowledge $savings');
      }
    });

    test('Q3: knowing ETFs or investing already skips Les bases (M12-7)', () {
      for (final (knowledge, skips) in [
        (Knowledge.nothing, false),
        (Knowledge.stocks, false),
        (Knowledge.etfs, true),
        (Knowledge.alreadyInvesting, true),
      ]) {
        expect(
          skipsTheBasics(profile(knowledge: knowledge)),
          skips,
          reason: '$knowledge',
        );
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

  group('an island\'s lessons open (M12-7)', () {
    const lessons = ['ae.one', 'ae.two'];
    for (final (name, requires, completed, opened, open) in [
      ('nothing required', const <String>[], const <String>{}, false, true),
      ('its lesson to wait for done', ['lb.five'], {'lb.five'}, false, true),
      ('waiting for it', ['lb.five'], {'lb.four'}, false, false),
      ('one of two required', ['lb.five', 'lb.six'], {'lb.five'}, false, false),
      (
        'its own progress kept (an install from v1.0.0)',
        ['lb.five'],
        {'ae.two'},
        false,
        true,
      ),
      (
        'opened by the questionnaire',
        ['lb.five'],
        const <String>{},
        true,
        true,
      ),
    ]) {
      test(name, () {
        expect(
          islandOpen(
            requires: requires,
            lessons: lessons,
            completed: completed,
            opened: opened,
          ),
          open,
        );
      });
    }
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

    test('money on the live wallet\'s Livret A (Les bases, M12-4)', () {
      expect(
        completedMissions(
          const MissionContext(
            liveHoldings: [],
            hasActiveDcaPlan: false,
            hasLivretSavings: true,
          ),
        ),
        {'lb.mission-livret'},
      );
    });

    test('detectors exist for the mission nodes', () {
      expect(missionDetectors.keys, [
        ...island.where((n) => n.type == NodeType.mission).map((n) => n.id),
        // Les bases' (M12-4), until its pack is bundled (M12-5).
        'lb.mission-livret',
      ]);
    });
  });
}
