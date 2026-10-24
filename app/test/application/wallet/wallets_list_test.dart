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

WalletSummary tripOn(
  WalletStatus status, {
  DateTime? simDate,
  DateTime? start,
}) => WalletSummary(
  id: 't',
  kind: WalletKind.trip,
  name: 'Covid',
  status: status,
  startDate: start ?? DateTime.utc(2020, 2, 18),
  simDate: simDate,
  difficulty: 'realiste',
  createdAt: DateTime.utc(2026, 10, 1),
);

void main() {
  group('a trip row\'s status line', () {
    final day = DateTime.utc(2020, 2, 24);

    test('running: the day it is on', () {
      expect(
        tripLine(tripOn(WalletStatus.active, simDate: day)),
        isA<TripOngoing>()
            .having((l) => l.day, 'day', day)
            .having((l) => l.stopped, 'stopped', false),
      );
    });

    test('stopped by itself: still on its day, waiting for the user', () {
      expect(
        tripLine(tripOn(WalletStatus.stopped, simDate: day)),
        isA<TripOngoing>()
            .having((l) => l.day, 'day', day)
            .having((l) => l.stopped, 'stopped', true),
      );
    });

    test('over: from its first day to the day it ended', () {
      final line = tripLine(
        tripOn(
          WalletStatus.finished,
          start: DateTime.utc(2000, 3, 10),
          simDate: DateTime.utc(2003, 3, 11),
        ),
      );
      expect(
        line,
        isA<TripOver>()
            .having((l) => l.from, 'from', DateTime.utc(2000, 3, 10))
            .having((l) => l.to, 'to', DateTime.utc(2003, 3, 11))
            .having((l) => l.oneMonth, 'oneMonth', false),
      );
    });

    test('over in the month it started: one month', () {
      for (final end in [
        DateTime.utc(2020, 2, 18),
        DateTime.utc(2020, 2, 28),
      ]) {
        expect(
          tripLine(tripOn(WalletStatus.finished, simDate: end)),
          isA<TripOver>().having((l) => l.oneMonth, 'oneMonth', true),
        );
      }
      // Same month, another year.
      expect(
        tripLine(
          tripOn(WalletStatus.finished, simDate: DateTime.utc(2021, 2, 18)),
        ),
        isA<TripOver>().having((l) => l.oneMonth, 'oneMonth', false),
      );
    });

    test('no simulated day yet: its first day', () {
      expect(
        tripLine(tripOn(WalletStatus.active)),
        isA<TripOngoing>().having(
          (l) => l.day,
          'day',
          DateTime.utc(2020, 2, 18),
        ),
      );
      expect(
        tripLine(tripOn(WalletStatus.finished)),
        isA<TripOver>()
            .having((l) => l.to, 'to', DateTime.utc(2020, 2, 18))
            .having((l) => l.oneMonth, 'oneMonth', true),
      );
    });
  });

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
