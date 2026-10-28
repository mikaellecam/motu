import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/companion/companion.dart';
import 'package:finance_companion/data/companion/companion_codec.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/next_step_card.dart';
import 'package:finance_companion/application/learning/ui_level.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/learning/next_step.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart' show WallClock;

Profile profile({
  Knowledge knowledge = Knowledge.nothing,
  Savings savings = Savings.currentAccount,
  WeeklyTime weeklyTime = WeeklyTime.five,
}) => Profile(
  goal: Goal.longTerm,
  dropReaction: DropReaction.wait,
  knowledge: knowledge,
  savings: savings,
  weeklyTime: weeklyTime,
);

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  // Sunday 11 October 2026, late morning in Paris.
  final now = DateTime.utc(2026, 10, 11, 9);
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );
  // The way starts on Les bases (M12-7).
  final bases = decodePack(
    File('assets/packs/les-bases.json').readAsStringSync(),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(WallClock(now)),
        contentPackProvider(actionsEtfIsland).overrideWith((ref) async => pack),
        contentPackProvider(lesBasesIsland).overrideWith((ref) async => bases),
      ],
    );
    c.listen(nextStepViewProvider, (_, _) {});
    c.listen(currentUiLevelProvider, (_, _) {});
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<NextStepView?> view() async {
    await pumpEventQueue();
    return c.read(nextStepViewProvider.future);
  }

  Future<void> complete(String nodeId, DateTime at) =>
      c.read(profileRepositoryProvider).completeNode(nodeId, at: at);

  test('before the questionnaire: no card', () async {
    expect(await view(), isNull);
  });

  test('a beginner starts on Les bases, no savings or not: no sheet first '
      '(M12-7)', () async {
    await c
        .read(profileRepositoryProvider)
        .save(profile(savings: Savings.none));
    c.invalidate(nextStepViewProvider);
    final v = (await view())!;
    expect(v.step, const PlayNode('lb.safety-cushion'));
    expect(v.title!.of('fr'), 'Ton matelas de sécurité');
  });

  test('Les bases to its end, Actions & ETF opening after its fifth lesson '
      '(M12-7)', () async {
    await c
        .read(profileRepositoryProvider)
        .save(profile(weeklyTime: WeeklyTime.thirtyPlus));
    c.invalidate(nextStepViewProvider);
    final yesterday = now.subtract(const Duration(days: 1));
    for (final n in bases.path.take(5)) {
      await complete(n.id, yesterday);
    }
    expect((await view())!.step, const PlayNode('lb.loan-cost'));
    for (final n in bases.path.skip(5)) {
      await complete(n.id, yesterday);
    }
    final v = (await view())!;
    expect(v.step, const PlayNode('ae.livret-vs-etf'));
    expect(v.title!.of('fr'), 'Livret ou ETF\u202f?');
  });

  test('knowing ETFs starts on the first-ETF mission', () async {
    await c
        .read(profileRepositoryProvider)
        .save(profile(knowledge: Knowledge.etfs));
    c.invalidate(nextStepViewProvider);
    final v = (await view())!;
    expect(v.step, const DoMission('ae.mission-first-etf'));
    expect(v.title!.of('fr'), 'Ton premier ETF');
  });

  test('a lesson a day: done for today, the wallet; a trip once one runs, '
      'the newest', () async {
    await c.read(profileRepositoryProvider).save(profile());
    c.invalidate(nextStepViewProvider);
    await complete('ae.livret-vs-etf', now.subtract(const Duration(hours: 1)));
    expect((await view())!.step, const OpenLiveWallet());

    final wallets = c.read(walletRepositoryProvider);
    for (final (id, name, minutes) in [
      ('t1', 'Krach 2008', 0),
      ('t2', 'Covid', 5),
    ]) {
      await wallets.createWallet(
        id: id,
        kind: WalletKind.trip,
        name: name,
        startDate: DateTime.utc(2020, 2, 18),
        startingCash: const Money(1000000, Currency.eur),
        params: WalletParams(
          rules: TradingRules(
            fxFeeRate: Decimal.zero,
            fixedFee: const Money.zero(Currency.eur),
            fractionalShares: true,
          ),
          monthlyContribution: const Money.zero(Currency.eur),
          stops: const StopConditions(),
        ),
        createdAt: now.add(Duration(minutes: minutes)),
      );
    }
    final v = (await view())!;
    expect(v.step, const ContinueTrip('t2'));
    expect(v.tripName, 'Covid');
  });

  test('yesterday\'s lessons leave today\'s free', () async {
    await c.read(profileRepositoryProvider).save(profile());
    c.invalidate(nextStepViewProvider);
    await complete('lb.safety-cushion', now.subtract(const Duration(days: 1)));
    expect((await view())!.step, const PlayNode('lb.cash-inflation'));
  });

  test('the level follows the lessons as they are completed', () async {
    await c.read(profileRepositoryProvider).save(profile());
    c.invalidate(currentUiLevelProvider);
    await pumpEventQueue();
    expect(await c.read(currentUiLevelProvider.future), 1);
    await complete(pack.path[3].id, now);
    await pumpEventQueue();
    expect(await c.read(currentUiLevelProvider.future), 2);
  });

  test(
    'an unread companion moment comes first; read, the lesson is back',
    () async {
      await c.read(profileRepositoryProvider).save(profile());
      await c.read(walletRepositoryProvider).ensureLiveWallet(now);
      await db.learningDao.logMoment(
        CompanionLogCompanion.insert(
          walletId: 'live',
          rule: CompanionRule.idleCash,
          key: '',
          firedAt: now,
          params: encodeParams({'cashWeight': Decimal.parse('0.6')}),
        ),
      );
      c.invalidate(nextStepViewProvider);
      final v = (await view())!;
      expect(v.step, isA<ReadMoment>());
      expect(v.moment!.rule, CompanionRule.idleCash);

      await c.read(companionActionsProvider.notifier).dismiss(v.moment!);
      expect((await view())!.step, const PlayNode('lb.safety-cushion'));
    },
  );
}
