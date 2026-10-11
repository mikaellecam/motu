import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/companion/companion.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/companion/companion_codec.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/repositories/companion_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart' show WallClock;

DateTime day(int m, int d) => DateTime.utc(2026, m, d);

void main() {
  late AppDatabase db;
  late ProviderContainer c;

  Future<void> log(
    String walletId,
    CompanionRule rule,
    DateTime at, {
    String key = '',
    Map<String, Object> params = const {},
  }) => db.learningDao.logMoment(
    CompanionLogCompanion.insert(
      walletId: walletId,
      rule: rule,
      key: key,
      firedAt: at,
      params: encodeParams(params),
    ),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(WallClock(day(10, 11))),
      ],
    );
    final wallets = WalletRepository(db);
    await wallets.ensureLiveWallet(day(10, 1));
    await wallets.createWallet(
      id: 'trip',
      kind: WalletKind.trip,
      name: 'Octobre',
      startDate: day(10, 1),
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
      createdAt: day(10, 1),
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('moments not read, oldest first, their params as they were', () async {
    await log(
      'live',
      CompanionRule.concentration,
      day(10, 6),
      params: {'assetId': 'apple', 'weight': Decimal.parse('0.45')},
    );
    await log(
      'live',
      CompanionRule.idleCash,
      day(10, 3),
      params: {'cashWeight': Decimal.parse('0.6')},
    );
    final repo = CompanionRepository(db);
    final active = await repo.watchActive().first;
    expect(
      [for (final m in active) m.rule],
      [CompanionRule.idleCash, CompanionRule.concentration],
    );
    expect(active.last.assetId, 'apple');
    expect(active.last.params['weight'], Decimal.parse('0.45'));

    await repo.dismiss(active.first.id, day(10, 11));
    expect(
      [for (final m in await repo.watchActive().first) m.rule],
      [CompanionRule.concentration],
    );
  });

  test(
    'a wallet shows its oldest; an asset page, the oldest about it',
    () async {
      await log(
        'trip',
        CompanionRule.firstLoss,
        day(10, 2),
        params: {'assetId': 'meta'},
      );
      await log(
        'live',
        CompanionRule.fxSwing,
        day(10, 4),
        params: {
          'move': Decimal.parse('0.04'),
          'exposure': Decimal.parse('0.8'),
        },
      );
      await log(
        'live',
        CompanionRule.positionDrop,
        day(10, 5),
        key: 'apple',
        params: {'assetId': 'apple', 'drop': Decimal.parse('-0.16')},
      );
      Future<ActiveMoment?> moment(String wallet, String? asset) {
        c.listen(walletMomentProvider(wallet, asset), (_, _) {});
        return c.read(walletMomentProvider(wallet, asset).future);
      }

      expect((await moment('live', null))!.rule, CompanionRule.fxSwing);
      expect((await moment('live', 'apple'))!.rule, CompanionRule.positionDrop);
      expect(await moment('live', 'meta'), isNull);
      expect((await moment('trip', null))!.rule, CompanionRule.firstLoss);

      // Read, it goes, and the next one shows.
      final first = (await moment('live', null))!;
      await c.read(companionActionsProvider.notifier).dismiss(first);
      await pumpEventQueue();
      expect((await moment('live', null))!.rule, CompanionRule.positionDrop);
    },
  );
}
