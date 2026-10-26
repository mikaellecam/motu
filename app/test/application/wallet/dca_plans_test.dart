import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/missions.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_runner.dart';
import 'package:finance_companion/application/wallet/dca_plans.dart';
import 'package:finance_companion/application/wallet/live_catch_up.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/order_matcher.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/fake_frankfurter.dart';

DateTime day(int m, int d) => DateTime.utc(2026, m, d);
Decimal d(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(d(s), Currency.eur);

/// Plans set up from the sheet (M9-41), run by the live catch-up and the
/// trip runner. Nasdaq, October 2026 (New York on summer time): 13:30 to
/// 20:00 UTC. Apple and the world ETF close at 100/101/102 and 50/51/52 from
/// Monday 5 to Wednesday 7; the fake's bars open where they close.
void main() {
  late AppDatabase db;
  late WallClock wall;
  late FakeBackend backend;
  late ProviderContainer container;
  late WalletRepository wallets;
  const live = WalletRepository.liveWalletId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    wall = WallClock(DateTime.utc(2026, 10, 6, 15));
    backend = FakeBackend()
      ..assets.add({
        'id': 'world',
        'symbol': 'ACWI',
        'name': 'iShares MSCI ACWI ETF',
        'type': 'etf',
        'exchange': 'nasdaq',
        'currency': 'USD',
        'region': 'world',
        'listingDate': '2008-03-28',
      })
      ..closes['world'] = {
        '2026-10-05': '50',
        '2026-10-06': '51',
        '2026-10-07': '52',
      };
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(wall),
        marketRepositoryProvider.overrideWithValue(
          MarketRepository(
            db,
            BackendApi('http://t', adapter: backend),
            wallClock: wall,
          ),
        ),
        fxServiceProvider.overrideWithValue(
          FxService(
            db,
            FrankfurterApi(adapter: FakeFrankfurter()),
            wallClock: wall,
          ),
        ),
      ],
    );
    wallets = WalletRepository(db);
    // Created on Monday 5 during the session: Monday is its first day.
    await wallets.ensureLiveWallet(DateTime.utc(2026, 10, 5, 15));
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> trip(
    String id, {
    String cash = '10000',
    String contribution = '0',
    TradingRules? rules,
  }) => wallets.createWallet(
    id: id,
    kind: WalletKind.trip,
    name: id,
    startDate: day(10, 5),
    startingCash: eur(cash),
    params: WalletParams(
      rules:
          rules ??
          TradingRules(
            fxFeeRate: Decimal.zero,
            fixedFee: const Money.zero(Currency.eur),
            fractionalShares: true,
          ),
      monthlyContribution: eur(contribution),
      stops: const StopConditions(),
    ),
    createdAt: wall.now(),
  );

  PlanSetupProvider sheet(
    String walletId, {
    String asset = 'apple',
    Money? amount,
    DcaFrequency frequency = DcaFrequency.monthly,
  }) =>
      planSetupProvider(asset, walletId, amount: amount, frequency: frequency);

  /// The sheet opened at the wall clock, [amount] typed, saved.
  Future<DcaPlan?> setUpPlan(
    String walletId, {
    String asset = 'apple',
    String amount = '100',
    DcaFrequency frequency = DcaFrequency.monthly,
  }) async {
    final provider = sheet(walletId, asset: asset);
    container.listen(provider, (_, _) {});
    await container.read(provider.future);
    container.read(provider.notifier)
      ..setAmount(amount)
      ..setFrequency(frequency);
    return container.read(provider.notifier).submit();
  }

  Future<void> catchUp() => container.read(liveCatchUpProvider.notifier).run();

  Future<void> advanceTrip(String id) async {
    container.listen(tripRunnerProvider(id), (_, _) {});
    await container.read(tripRunnerProvider(id).notifier).advance(TripStep.day);
    expect(container.read(tripRunnerProvider(id)).hasError, isFalse);
  }

  List<Fill> fills(WalletState w) => w.fills;

  group('the first purchase: a session that opens after the plan', () {
    test(
      'live, set up mid-session: not at that session\'s open, known',
      () async {
        // Tuesday 15:00 UTC: Tuesday's session opened at 101 $.
        final provider = sheet(live);
        container.listen(provider, (_, _) {});
        expect(
          (await container.read(provider.future)).context.firstPurchase,
          day(10, 7),
        );
        final plan = (await setUpPlan(live))!;
        expect(plan.start, day(10, 7));

        // Thursday morning, the catch-up books Tuesday and Wednesday.
        wall.t = DateTime.utc(2026, 10, 8, 12);
        await catchUp();
        final wallet = await wallets.load(live);
        final fill = fills(wallet).single;
        expect(fill.date, day(10, 7));
        expect(fill.price, Price(d('102'), Currency.usd));
        expect(fill.orderId, 'dca-${plan.id}-2026-10-07');
        expect(
          (await wallets.orderDetail(fill.orderId!))!.order.planId,
          plan.id,
        );
        expect(wallet.pendingOrders, isEmpty);
      },
    );

    test('live, set up before the open: that session', () async {
      wall.t = DateTime.utc(2026, 10, 6, 12);
      final plan = (await setUpPlan(live))!;
      expect(plan.start, day(10, 6));
      wall.t = DateTime.utc(2026, 10, 8, 12);
      await catchUp();
      final fill = fills(await wallets.load(live)).single;
      expect(fill.date, day(10, 6));
      expect(fill.price, Price(d('101'), Currency.usd));
    });

    test('a session that opened while the sheet was open moves it', () async {
      wall.t = DateTime.utc(2026, 10, 6, 13);
      final provider = sheet(live);
      container.listen(provider, (_, _) {});
      expect(
        (await container.read(provider.future)).context.firstPurchase,
        day(10, 6),
      );
      container.read(provider.notifier).setAmount('100');
      // The Nasdaq opens at 13:30: saved at 13:45, Tuesday's open is known.
      wall.t = DateTime.utc(2026, 10, 6, 13, 45);
      final plan = await container.read(provider.notifier).submit();
      expect(plan!.start, day(10, 7));
    });

    test('a trip: the session after its day', () async {
      await trip('trip');
      final plan = (await setUpPlan('trip'))!;
      // The trip is on Monday 5 after the close: Tuesday's open.
      expect(plan.start, day(10, 6));
      await advanceTrip('trip');
      final fill = fills(await wallets.load('trip')).single;
      expect(fill.date, day(10, 6));
      expect(fill.price, Price(d('101'), Currency.usd));
    });

    test('a trip at today goes by the real time', () async {
      await trip('today');
      await db.walletDao.updateWallet(
        'today',
        WalletsCompanion(
          simDate: Value(day(10, 7)),
          reachedToday: const Value(true),
        ),
      );
      // Thursday 15:00 UTC, the Nasdaq open: Friday.
      wall.t = DateTime.utc(2026, 10, 8, 15);
      expect((await setUpPlan('today'))!.start, day(10, 9));
    });

    test('a wallet whose first day is today', () async {
      // Reset on Tuesday before the open: Tuesday is its first, booked day.
      await wallets.resetLiveWallet(
        DateTime.utc(2026, 10, 6, 12),
        startingCash: eur('50000'),
      );
      wall.t = DateTime.utc(2026, 10, 6, 12, 30);
      expect((await setUpPlan(live))!.start, day(10, 7));
    });
  });

  test('then the schedule: the wallet shows the next purchase', () async {
    await trip('trip');
    final plan = (await setUpPlan('trip', frequency: DcaFrequency.weekly))!;
    container.listen(walletOverviewProvider('trip'), (_, _) {});
    var rows = (await container.read(walletOverviewProvider('trip').future))
        .plans;
    expect(rows.single.plan.id, plan.id);
    expect(rows.single.asset.id, 'apple');
    expect(rows.single.next, day(10, 6));

    await advanceTrip('trip');
    rows = (await container.read(walletOverviewProvider('trip').future)).plans;
    expect(rows.single.next, day(10, 13));
  });

  test('too little cash on a due day: that purchase is cancelled, '
      'the plan goes on', () async {
    await trip('poor', cash: '50');
    final plan = (await setUpPlan('poor'))!;
    await advanceTrip('poor');

    final orderId = 'dca-${plan.id}-2026-10-06';
    final detail = (await wallets.orderDetail(orderId))!;
    expect(detail.status, OrderStatus.cancelled);
    expect(detail.cancelReason, CancelReason.insufficientCash);
    final wallet = await wallets.load('poor');
    expect(wallet.fills, isEmpty);
    expect(wallet.pendingOrders, isEmpty);
    expect(wallet.cash, eur('50'));
    // Nothing on screen says it bought: no position, no order waiting, the
    // plan's next purchase is the next one due.
    final o = await container.read(walletOverviewProvider('poor').future);
    expect(o.positions, isEmpty);
    expect(o.pendingOrders, isEmpty);
    expect(o.plans.single.next, day(11, 6));
  });

  test('stopped: no more purchases; one still pending stays an order the '
      'user can cancel', () async {
    // Meta has no bar on Tuesday 6: its purchase that day waits.
    backend.closes['meta'] = {'2026-10-05': '200', '2026-10-07': '210'};
    await trip('trip');
    final plan = (await setUpPlan(
      'trip',
      asset: 'meta',
      frequency: DcaFrequency.weekly,
    ))!;
    await advanceTrip('trip');
    final pending = (await wallets.load('trip')).pendingOrders.single;
    expect(pending.planId, plan.id);

    container.listen(planActionsProvider('trip'), (_, _) {});
    await container.read(planActionsProvider('trip').notifier).stop(plan.id);
    var wallet = await wallets.load('trip');
    expect(wallet.plans.single.active, isFalse);
    expect(wallet.pendingOrders.single.id, pending.id);
    expect(
      (await container.read(walletOverviewProvider('trip').future)).plans,
      isEmpty,
    );

    // The order it placed fills on Wednesday; the plan places none.
    await advanceTrip('trip');
    wallet = await wallets.load('trip');
    expect([for (final f in wallet.fills) f.orderId], [pending.id]);
    expect(wallet.fills.single.date, day(10, 7));
    expect(wallet.pendingOrders, isEmpty);
  });

  test('the mission completes once a plan is active', () async {
    container.listen(missionTrackerProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await db.learningDao.progress(), isEmpty);

    await setUpPlan(live);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      [for (final r in await db.learningDao.progress()) r.nodeId],
      ['ae.mission-dca'],
    );
  });

  test(
    '« Avancer jusqu\'à… » no longer says a contribution stays as cash',
    () async {
      await trip('saver', contribution: '200');
      container.listen(idleContributionProvider('saver'), (_, _) {});
      // Sunday 1 November: Monday 2.
      expect(
        await container.read(idleContributionProvider('saver').future),
        day(11, 2),
      );
      await setUpPlan('saver', asset: 'world');
      expect(
        await container.read(idleContributionProvider('saver').future),
        isNull,
      );
    },
  );

  group('the sheet', () {
    test('checks the amount like the simulator', () async {
      await trip(
        'tight',
        rules: TradingRules(
          fxFeeRate: d('0.0015'),
          fixedFee: eur('1'),
          fractionalShares: false,
        ),
      );
      final provider = sheet('tight');
      container.listen(provider, (_, _) {});
      final opened = await container.read(provider.future);
      // Nothing typed yet: nothing to say until « Investir ».
      expect(opened.showErrors, isFalse);
      expect(opened.canSubmit, isFalse);

      final notifier = container.read(provider.notifier);
      List<String> codes(String text) {
        notifier.setAmount(text);
        return [for (final e in container.read(provider).value!.errors) e.code];
      }

      expect(codes('0'), ['amount_not_positive']);
      expect(codes('-5'), ['amount_not_positive']);
      expect(codes('abc'), ['amount_not_positive']);
      expect(codes('1'), ['amount_below_fees']);
      expect(codes('100 000,01'), ['amount_too_large']);
      expect(codes('100 000'), isEmpty);
      // Whole shares only, as an order: an amount that buys none at the
      // latest price is refused (a share of Apple is about 100 $).
      expect(codes('1,01'), ['amount_below_one_share']);
      expect(codes('50'), ['amount_below_one_share']);
      expect(codes('200'), isEmpty);

      notifier.setAmount('');
      expect(await notifier.submit(), isNull);
      expect(container.read(provider).value!.showErrors, isTrue);
      expect((await wallets.load('tight')).plans, isEmpty);
    });

    test('quick chips and the simulator\'s prefill', () async {
      final provider = sheet(
        live,
        amount: eur('125.50'),
        frequency: DcaFrequency.weekly,
      );
      container.listen(provider, (_, _) {});
      final opened = await container.read(provider.future);
      expect(opened.form.amount, '125,5');
      expect(opened.form.frequency, DcaFrequency.weekly);
      expect(opened.amount, eur('125.50'));

      container.read(provider.notifier).quick(200);
      expect(container.read(provider).value!.amount, eur('200'));
    });

    test('a finished trip takes no plan', () async {
      await trip('ended');
      await wallets.finish('ended');
      final plan = await setUpPlan('ended');
      expect(plan, isNull);
      expect((await wallets.load('ended')).plans, isEmpty);
    });

    test('two plans in one wallet get two ids', () async {
      final first = (await setUpPlan(live))!;
      final second = (await setUpPlan(live, asset: 'world'))!;
      expect(first.id, isNot(second.id));
      final rows = (await container.read(walletOverviewProvider(live).future))
          .plans;
      expect([for (final r in rows) r.asset.id], ['apple', 'world']);
    });
  });
}
