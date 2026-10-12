import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/missions.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/live_catch_up.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/core/widgets/async_states.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fakes/fake_backend.dart';
import 'fakes/fake_frankfurter.dart';

/// The offline QA script (docs/qa/offline.md) as far as a test can run it:
/// a session online fills the cache, the app is killed, the device goes into
/// airplane mode, and after a relaunch every tab and screen of the script
/// shows its data, with the offline banner where prices show (BRIEF §6.4).
void main() {
  // Thursday 2026-10-08 12:00 UTC: Nasdaq closed, the last close Wednesday's.
  final wall = WallClock(DateTime.utc(2026, 10, 8, 12));
  late AppDatabase db;
  late FakeBackend backend;
  late FakeFrankfurter frankfurter;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend()
      ..assets.add({
        ...FakeBackend().assets.first,
        'id': 'world',
        'type': 'etf',
      })
      // As the real backend: calendars from 2000 to next year.
      ..holidays.addAll({
        for (var year = 2000; year < 2025; year++) year: <String>[],
      })
      ..closes['world'] = {
        '2026-10-05': '100',
        '2026-10-06': '101',
        '2026-10-07': '102',
      };
    frankfurter = FakeFrankfurter();
  });
  tearDown(() => db.close());

  /// What main() does, on the test's database, backend and connection.
  Future<(ProviderContainer, GoRouter)> launch({required bool online}) async {
    backend.offline = !online;
    frankfurter.offline = !online;
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(wall),
        backendApiProvider.overrideWithValue(
          BackendApi('http://t', adapter: backend),
        ),
        marketRepositoryProvider.overrideWith((ref) {
          final repository = MarketRepository(
            db,
            ref.watch(backendApiProvider),
            wallClock: wall,
            online: Stream.value(online),
          );
          ref.onDispose(repository.dispose);
          return repository;
        }),
        fxServiceProvider.overrideWithValue(
          FxService(db, FrankfurterApi(adapter: frankfurter), wallClock: wall),
        ),
      ],
    );
    await c.read(walletRepositoryProvider).ensureLiveWallet(wall.now());
    c.read(liveCatchUpProvider.notifier).run().ignore();
    c.read(missionTrackerProvider);
    return (c, buildRouter());
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Opens [location] and checks it renders: no error, no endless spinner.
  Future<void> visit(
    WidgetTester tester,
    GoRouter router,
    String location, {
    bool prices = false,
  }) async {
    router.go(location);
    await settle(tester);
    final error = find.byType(ErrorView);
    final said = tester
        .widgetList<Text>(
          find.descendant(of: error, matching: find.byType(Text)),
        )
        .map((t) => t.data);
    expect(error, findsNothing, reason: '$location: ${said.join(' | ')}');
    expect(find.byType(AsyncSkeleton), findsNothing, reason: location);
    if (prices) {
      expect(find.byType(StaleBanner), findsOneWidget, reason: location);
    }
  }

  testWidgets('killed, then relaunched offline: every tab still works', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // A first session, online: the questionnaire answered, a share bought,
    // the screens of the script opened once.
    var (c, router) = await launch(online: true);
    await c
        .read(profileRepositoryProvider)
        .save(
          const Profile(
            goal: Goal.longTerm,
            dropReaction: DropReaction.wait,
            knowledge: Knowledge.nothing,
            savings: Savings.livret,
            weeklyTime: WeeklyTime.fifteen,
          ),
        );
    final buy = Order(
      id: 'o1',
      assetId: 'apple',
      side: Side.buy,
      type: OrderType.market,
      size: QuantitySize(Quantity.whole(2)),
      createdAt: DateTime.utc(2026, 10, 7, 15),
    );
    await c
        .read(walletRepositoryProvider)
        .executeOrder(
          'live',
          buy,
          Fill(
            orderId: 'o1',
            assetId: 'apple',
            side: Side.buy,
            date: DateTime.utc(2026, 10, 7, 15),
            quantity: Quantity.whole(2),
            price: Price(Decimal.parse('102'), Currency.usd),
            fxRate: Decimal.parse('0.8547'),
            fees: const Money(0, Currency.eur),
          ),
        );
    await c
        .read(walletRepositoryProvider)
        .createWallet(
          id: 'trip',
          kind: WalletKind.trip,
          name: 'Octobre',
          startDate: DateTime.utc(2026, 10, 5),
          startingCash: Money.book(Decimal.fromInt(10000), Currency.eur),
          params: WalletParams(
            rules: TradingRules(
              fxFeeRate: Decimal.zero,
              fixedFee: const Money.zero(Currency.eur),
              fractionalShares: true,
            ),
            monthlyContribution: const Money.zero(Currency.eur),
            stops: const StopConditions(),
          ),
          createdAt: wall.now(),
        );
    const script = [
      ('/', false),
      ('/island/actions-etf', false),
      ('/node/ae.livret-vs-etf', false),
      ('/wallets', false),
      ('/wallet/live', true),
      ('/wallet/trip', false),
      ('/asset/apple?wallet=live', true),
      ('/explore', true),
      ('/glossary', false),
      ('/tools/dca', false),
      ('/settings', false),
    ];
    Future<void> walk() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MainApp(router: router),
        ),
      );
      for (final (location, _) in script) {
        await visit(tester, router, location);
      }
    }

    await walk();

    // Killed; airplane mode; relaunched.
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    (c, router) = await launch(online: false);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MainApp(router: router),
      ),
    );
    for (final (location, prices) in script) {
      await visit(tester, router, location, prices: prices);
    }
    expect(backend.requests, isNotEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
