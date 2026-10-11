import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/wallets_list.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/local/tables.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:decimal/decimal.dart';

final bundled = decodePack(
  File('assets/packs/actions-etf.json').readAsStringSync(),
);

void main() {
  test('suggestions: the bridges of completed lessons, in path order', () {
    expect(bridgeSuggestions(bundled, completed: const {}), isEmpty);
    expect(
      bridgeSuggestions(bundled, completed: {'ae.livret-vs-etf'}),
      isEmpty,
      reason: 'no bridge on node 1',
    );
    final s = bridgeSuggestions(
      bundled,
      completed: {'ae.livret-vs-etf', 'ae.march-2020'},
    ).single;
    expect(s.nodeId, 'ae.march-2020');
    expect(s.bridge.date, DateTime.utc(2020, 2, 18));
  });

  test(
    'the list: live, trips newest first, suggestions as lessons complete',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          contentPackProvider(actionsEtfIsland)
              .overrideWith((ref) async => bundled),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final wallets = WalletRepository(db);
      await wallets.ensureLiveWallet(DateTime.utc(2026, 10, 1));
      Future<void> trip(String id, DateTime created) => wallets.createWallet(
        id: id,
        kind: WalletKind.trip,
        name: id,
        startDate: DateTime.utc(2008, 9, 15),
        startingCash: const Money(1000000, Currency.eur),
        params: WalletParams(
          rules: TradingRules(
            fxFeeRate: Decimal.zero,
            fixedFee: const Money.zero(Currency.eur),
            fractionalShares: true,
          ),
          monthlyContribution: const Money.zero(Currency.eur),
          stops: const StopConditions(),
          difficulty: 'realiste',
        ),
        createdAt: created,
      );
      await trip('older', DateTime.utc(2026, 10, 2));
      await trip('newer', DateTime.utc(2026, 10, 5));

      container.listen(walletsListProvider, (_, _) {});
      var list = await container.read(walletsListProvider.future);
      expect(list.live!.id, 'live');
      expect([for (final t in list.trips) t.id], ['newer', 'older']);
      expect(list.trips.first.difficulty, 'realiste');
      expect(list.suggestions, isEmpty);

      await db.learningDao.saveProgress(
        NodeProgressCompanion.insert(
          nodeId: 'ae.march-2020',
          status: NodeStatus.completed,
          completedAt: Value(DateTime.utc(2026, 10, 6)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      list = await container.read(walletsListProvider.future);
      expect([for (final s in list.suggestions) s.nodeId], ['ae.march-2020']);
    },
  );
}
