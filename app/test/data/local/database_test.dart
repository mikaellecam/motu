import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/local/tables.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/order_matcher.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int m, int dd) => DateTime.utc(2026, m, dd);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  PriceBarsCompanion bar(String asset, DateTime date, String close) =>
      PriceBarsCompanion.insert(
        assetId: asset,
        date: date,
        open: d(close),
        high: d(close),
        low: d(close),
        close: d(close),
        volume: 0,
      );

  Future<void> addWallet(String id) => db.walletDao.createWallet(
    WalletsCompanion.insert(
      id: id,
      kind: WalletKind.trip,
      name: 'Covid',
      startDate: day(2, 18),
      params: '{}',
      status: WalletStatus.active,
      createdAt: day(10, 7),
    ),
  );

  group('market cache', () {
    test(
      'bars: exact decimals, inclusive range, oldest first, replace',
      () async {
        final dao = db.marketDao;
        await dao.upsertBars([
          bar('cw8', day(10, 7), '522.40'),
          bar('cw8', day(10, 5), '0.1'),
          bar('cw8', day(10, 6), '520.10'),
          bar('aapl', day(10, 6), '250'),
        ]);
        final bars = await dao.bars('cw8', from: day(10, 5), to: day(10, 6));
        expect(bars.map((b) => b.date), [day(10, 5), day(10, 6)]);
        expect(bars.first.close, d('0.1'));

        await dao.upsertBars([bar('cw8', day(10, 7), '261.20')]);
        final replaced = await dao.bars(
          'cw8',
          from: day(10, 7),
          to: day(10, 7),
        );
        expect(replaced.single.close, d('261.20'));

        await dao.deleteBars('cw8');
        expect(
          await dao.bars('cw8', from: day(1, 1), to: day(12, 31)),
          isEmpty,
        );
        expect(
          await dao.bars('aapl', from: day(1, 1), to: day(12, 31)),
          hasLength(1),
        );
      },
    );

    test('the FX rate on or before a date', () async {
      final dao = db.marketDao;
      await dao.upsertRates([
        FxRatesCompanion.insert(
          base: Currency.usd,
          quote: Currency.eur,
          date: day(10, 2),
          rate: d('0.85'),
        ),
        FxRatesCompanion.insert(
          base: Currency.usd,
          quote: Currency.eur,
          date: day(10, 5),
          rate: d('0.86'),
        ),
      ]);
      // Saturday 3 October: Friday's rate.
      expect(
        (await dao.rateOnOrBefore(
          Currency.usd,
          Currency.eur,
          day(10, 3),
        ))!.rate,
        d('0.85'),
      );
      expect(
        (await dao.rateOnOrBefore(
          Currency.usd,
          Currency.eur,
          day(10, 5),
        ))!.rate,
        d('0.86'),
      );
      expect(
        await dao.rateOnOrBefore(Currency.usd, Currency.eur, day(10, 1)),
        isNull,
      );
      expect(
        await dao.rateOnOrBefore(Currency.eur, Currency.usd, day(10, 5)),
        isNull,
      );
      expect(
        await dao.rates(
          Currency.usd,
          Currency.eur,
          from: day(10, 1),
          to: day(10, 4),
        ),
        hasLength(1),
      );
    });

    test('Livret history is replaced as a whole', () async {
      final dao = db.marketDao;
      await dao.replaceLivret(
        [
          LivretRatesCompanion.insert(
            validFrom: day(8, 1),
            annualRate: d('0.017'),
          ),
        ],
        [
          LivretCeilingsCompanion.insert(
            validFrom: DateTime.utc(2013),
            amountCents: 2295000,
          ),
        ],
      );
      await dao.replaceLivret([
        LivretRatesCompanion.insert(
          validFrom: DateTime.utc(2025, 2),
          annualRate: d('0.024'),
        ),
        LivretRatesCompanion.insert(
          validFrom: day(8, 1),
          annualRate: d('0.017'),
        ),
      ], []);
      expect((await dao.allLivretRates()).map((r) => r.annualRate), [
        d('0.024'),
        d('0.017'),
      ]);
      expect(await dao.allLivretCeilings(), isEmpty);
    });

    test('holidays and the years they cover', () async {
      final dao = db.marketDao;
      await dao.saveHolidays(Exchange.euronext, 2026, [
        day(4, 3),
        day(4, 6),
      ], fetchedAt: day(1, 2));
      expect(
        (await dao.holidays(Exchange.euronext)).map((h) => h.date),
        unorderedEquals([day(4, 3), day(4, 6)]),
      );
      expect(await dao.cachedCalendarYears(Exchange.euronext), {2026});
      expect(await dao.cachedCalendarYears(Exchange.nyse), isEmpty);
    });

    test('quotes, sync state and content packs', () async {
      final dao = db.marketDao;
      await dao.saveQuote(
        QuotesCompanion.insert(
          assetId: 'aapl',
          price: d('250.10'),
          currency: Currency.usd,
          asOf: DateTime.utc(2026, 10, 7, 14),
          fetchedAt: DateTime.utc(2026, 10, 7, 14, 1),
          marketOpen: true,
        ),
      );
      expect((await dao.quote('aapl'))!.price, d('250.10'));
      await dao.saveSync(
        HistorySyncCompanion.insert(
          assetId: 'cw8',
          firstDate: DateTime.utc(2009, 4, 17),
          lastDate: day(10, 6),
          fetchedAt: day(10, 6),
        ),
      );
      expect((await dao.sync('cw8'))!.adjustedAt, isNull);
      await dao.saveContentPack(
        ContentPacksCompanion.insert(
          islandId: 'actions-etf',
          version: 3,
          json: '{}',
          checkedAt: day(10, 7),
        ),
      );
      expect((await dao.contentPack('actions-etf'))!.version, 3);
    });

    test('clearing the cache keeps every user table', () async {
      await db.marketDao.upsertAssets([
        AssetsCompanion.insert(
          id: 'cw8',
          symbol: 'CW8',
          name: 'MSCI World',
          type: AssetType.etf,
          exchange: Exchange.euronext,
          currency: Currency.eur,
          region: 'world',
          listingDate: DateTime.utc(2009, 4, 17),
        ),
      ]);
      await db.marketDao.upsertBars([bar('cw8', day(10, 6), '520')]);
      await addWallet('t1');
      await db.learningDao.toggleFavorite('cw8', day(10, 7));

      await db.marketDao.clearCache();

      expect(await db.marketDao.allAssets(), isEmpty);
      expect(
        await db.marketDao.bars('cw8', from: day(1, 1), to: day(12, 31)),
        isEmpty,
      );
      expect(await db.walletDao.wallet('t1'), isNotNull);
      expect(await db.learningDao.watchFavorites().first, {'cw8'});
    });
  });

  group('wallets', () {
    test('cash is the sum of the ledger', () async {
      await addWallet('t1');
      final dao = db.walletDao;
      await dao.addLedgerEntry(
        CashLedgerCompanion.insert(
          walletId: 't1',
          date: day(2, 18),
          amountCents: 1000000,
          kind: LedgerKind.start,
        ),
      );
      await dao.addLedgerEntry(
        CashLedgerCompanion.insert(
          walletId: 't1',
          date: day(2, 19),
          amountCents: -18027,
          kind: LedgerKind.buy,
          refId: const Value('o1'),
        ),
      );
      expect(await dao.cashCents('t1'), 981973);
      expect(await dao.cashCents('nobody'), 0);
      expect((await dao.ledger('t1')).map((l) => l.kind), [
        LedgerKind.start,
        LedgerKind.buy,
      ]);
    });

    test('an order sets exactly one of amount and quantity', () async {
      await addWallet('t1');
      OrdersCompanion order({int? cents, int? micros}) =>
          OrdersCompanion.insert(
            id: 'o1',
            walletId: 't1',
            assetId: 'cw8',
            side: Side.buy,
            type: OrderType.market,
            amountCents: Value(cents),
            quantityMicros: Value(micros),
            status: OrderStatus.pending,
            createdAt: day(2, 18),
          );
      await expectLater(
        db.walletDao.insertOrder(order()),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        db.walletDao.insertOrder(order(cents: 1, micros: 1)),
        throwsA(isA<SqliteException>()),
      );
      await db.walletDao.insertOrder(order(cents: 10000));
      expect(await db.walletDao.pendingOrders('t1'), hasLength(1));

      await db.walletDao.closeOrder(
        'o1',
        OrderStatus.cancelled,
        reason: CancelReason.insufficientCash,
      );
      expect(await db.walletDao.pendingOrders('t1'), isEmpty);
      expect(
        (await db.walletDao.order('o1'))!.cancelReason,
        CancelReason.insufficientCash,
      );
    });

    test(
      'fills come back in execution order, same-day fills included',
      () async {
        await addWallet('t1');
        for (final id in ['o1', 'o2', 'o3']) {
          await db.walletDao.insertOrder(
            OrdersCompanion.insert(
              id: id,
              walletId: 't1',
              assetId: 'cw8',
              side: Side.buy,
              type: OrderType.market,
              quantityMicros: const Value(1000000),
              status: OrderStatus.filled,
              createdAt: day(2, 18),
            ),
          );
        }
        FillsCompanion fill(String order, DateTime date) =>
            FillsCompanion.insert(
              orderId: order,
              walletId: 't1',
              assetId: 'cw8',
              side: Side.buy,
              date: date,
              price: d('100'),
              currency: Currency.eur,
              quantityMicros: 1000000,
              fxRate: Decimal.one,
              feesCents: 0,
            );
        await db.walletDao.insertFill(fill('o2', day(2, 20)));
        await db.walletDao.insertFill(fill('o3', day(2, 19)));
        await db.walletDao.insertFill(fill('o1', day(2, 20)));
        expect((await db.walletDao.fillsOf('t1')).map((f) => f.orderId), [
          'o3',
          'o2',
          'o1',
        ]);
        // One fill per order.
        await expectLater(
          db.walletDao.insertFill(fill('o1', day(2, 21))),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('deleting a wallet deletes everything it owns', () async {
      await addWallet('t1');
      await addWallet('t2');
      final dao = db.walletDao;
      await dao.addLedgerEntry(
        CashLedgerCompanion.insert(
          walletId: 't1',
          date: day(2, 18),
          amountCents: 100,
          kind: LedgerKind.start,
        ),
      );
      await dao.saveValue(
        WalletValuesCompanion.insert(
          walletId: 't1',
          date: day(2, 18),
          valueCents: 100,
          flowCents: 100,
        ),
      );
      await dao.addJournalEntry(
        JournalEntriesCompanion.insert(
          walletId: 't1',
          simDate: day(3, 12),
          decision: 'hold',
        ),
      );
      await db.learningDao.logMoment(
        CompanionLogCompanion.insert(
          walletId: 't1',
          rule: CompanionRule.firstLoss,
          key: '',
          firedAt: day(3, 1),
          params: '{}',
        ),
      );
      await dao.addLedgerEntry(
        CashLedgerCompanion.insert(
          walletId: 't2',
          date: day(2, 18),
          amountCents: 7,
          kind: LedgerKind.start,
        ),
      );

      await dao.deleteWallet('t1');

      expect(await dao.ledger('t1'), isEmpty);
      expect(await dao.valuesOf('t1'), isEmpty);
      expect(await dao.journalOf('t1'), isEmpty);
      expect(await db.learningDao.momentsOf('t1'), isEmpty);
      expect(await dao.cashCents('t2'), 7);
    });

    test('rows need an existing wallet', () async {
      await expectLater(
        db.walletDao.addLedgerEntry(
          CashLedgerCompanion.insert(
            walletId: 'ghost',
            date: day(1, 1),
            amountCents: 1,
            kind: LedgerKind.start,
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('values and DCA plans', () async {
      await addWallet('t1');
      final dao = db.walletDao;
      await dao.saveValue(
        WalletValuesCompanion.insert(
          walletId: 't1',
          date: day(2, 19),
          valueCents: 900,
          flowCents: 0,
        ),
      );
      await dao.saveValue(
        WalletValuesCompanion.insert(
          walletId: 't1',
          date: day(2, 18),
          valueCents: 1000,
          flowCents: 1000,
        ),
      );
      expect((await dao.valuesOf('t1')).map((v) => v.valueCents), [1000, 900]);

      expect(await dao.anyActivePlan(), isFalse);
      await dao.savePlan(
        DcaPlansCompanion.insert(
          id: 'p1',
          walletId: 't1',
          assetId: 'cw8',
          amountCents: 20000,
          frequency: DcaFrequency.monthly,
          startDate: day(3, 1),
        ),
      );
      expect(await dao.anyActivePlan(), isTrue);
      expect((await dao.plansOf('t1')).single.active, isTrue);
      await dao.updateWallet(
        't1',
        const WalletsCompanion(status: Value(WalletStatus.finished)),
      );
      expect((await dao.wallet('t1'))!.status, WalletStatus.finished);
    });
  });

  group('learning', () {
    test('a single profile row', () async {
      final dao = db.learningDao;
      expect(await dao.profile(), isNull);
      ProfilesCompanion answers(Knowledge k) => ProfilesCompanion.insert(
        id: const Value(1),
        goal: Goal.longTerm,
        dropReaction: DropReaction.wait,
        knowledge: k,
        savings: Savings.livret,
        weeklyTime: WeeklyTime.fifteen,
      );
      await dao.saveProfile(answers(Knowledge.nothing));
      await dao.saveProfile(answers(Knowledge.etfs));
      expect((await dao.profile())!.knowledge, Knowledge.etfs);
      await expectLater(
        db
            .into(db.profiles)
            .insert(answers(Knowledge.etfs).copyWith(id: const Value(2))),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a term keeps its first discovery date', () async {
      final dao = db.learningDao;
      await dao.discover('etf', day(10, 1));
      await dao.discover('etf', day(10, 5));
      await dao.passQuiz('etf');
      final row = (await dao.discovered()).single;
      expect(row.discoveredAt, day(10, 1));
      expect(row.quizPassed, isTrue);
    });

    test('favorites toggle', () async {
      final dao = db.learningDao;
      expect(await dao.toggleFavorite('cw8', day(10, 7)), isTrue);
      expect(await dao.toggleFavorite('cw8', day(10, 7)), isFalse);
      expect(await dao.watchFavorites().first, isEmpty);
    });

    test('unread moments, dismissal, progress and simulations', () async {
      await addWallet('t1');
      final dao = db.learningDao;
      final id = await dao.logMoment(
        CompanionLogCompanion.insert(
          walletId: 't1',
          rule: CompanionRule.concentration,
          key: '',
          firedAt: day(3, 1),
          params: '{"weight":"0.41"}',
        ),
      );
      expect(await dao.unreadMoments(), hasLength(1));
      await dao.dismissMoment(id, day(3, 2));
      expect(await dao.unreadMoments(), isEmpty);

      await dao.saveProgress(
        NodeProgressCompanion.insert(
          nodeId: 'ae.fees-toy',
          status: NodeStatus.completed,
          completedAt: Value(day(3, 2)),
        ),
      );
      expect((await dao.progress()).single.status, NodeStatus.completed);

      await dao.saveSimulation(
        DcaSimulationsCompanion.insert(
          id: 's1',
          params: '{}',
          result: '{}',
          savedAt: day(3, 1),
        ),
      );
      await dao.saveSimulation(
        DcaSimulationsCompanion.insert(
          id: 's2',
          params: '{}',
          result: '{}',
          savedAt: day(3, 2),
        ),
      );
      expect((await dao.simulations()).map((s) => s.id), ['s2', 's1']);
      await dao.deleteSimulation('s2');
      expect(await dao.simulations(), hasLength(1));
    });
  });
}
