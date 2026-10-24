import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_runner.dart';
import 'package:finance_companion/application/trip/trip_stop.dart';
import 'package:finance_companion/application/trip/trip_summary.dart';
import 'package:finance_companion/core/clock/simulation_clock.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/application/companion/companion.dart';
import 'package:finance_companion/application/wallet/livret_line.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/wallet/wallet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';

/// Records the steps asked for instead of moving time; lands on [result]
/// when one is set.
class FakeRunner extends TripRunner {
  final steps = <TripStep>[];
  TripAdvance? result;

  @override
  FutureOr<TripAdvance?> build(String walletId) => null;

  final targets = <DateTime>[];

  @override
  Future<void> advance(TripStep step) async {
    steps.add(step);
    if (result case final r?) {
      state = const AsyncLoading();
      state = AsyncData(r);
    }
  }

  @override
  Future<void> advanceTo(DateTime target) async => targets.add(target);
}

/// Records the stops saved.
class FakeStopActions extends StopActions {
  final saved = <StopConditions>[];

  @override
  FutureOr<void> build(String walletId) {}

  @override
  Future<void> updateStops(StopConditions stops) async => saved.add(stops);
}

DateTime day(int m, int d) => DateTime.utc(2008, m, d);
Money eur(String s) => Money.book(Decimal.parse(s), Currency.eur);

WalletOverview trip({WalletStatus status = WalletStatus.active}) =>
    buildOverview(
      wallet: WalletState(
        id: 'trip',
        kind: WalletKind.trip,
        name: 'Lehman',
        startDate: day(9, 15),
        simDate: day(10, 1),
        status: status,
        params: WalletParams(
          rules: TradingRules(
            fxFeeRate: Decimal.parse('0.0015'),
            fixedFee: eur('0'),
            fractionalShares: true,
          ),
          monthlyContribution: eur('200'),
          stops: const StopConditions(),
          difficulty: 'realiste',
        ),
        cash: eur('10000'),
        fills: const [],
        positions: const {},
        pendingOrders: const [],
        values: [
          DailyValue(date: day(9, 15), value: eur('10000'), flow: eur('10000')),
        ],
        livretMovements: const [],
        plans: const [],
      ),
      asOf: day(10, 1),
      assets: const {},
      prices: const {},
      fxRates: const {},
      livret: Decimal.zero,
    );

/// Records the trips ended by hand.
class FakeFinish extends TripFinish {
  var finished = 0;

  @override
  FutureOr<void> build(String walletId) {}

  @override
  Future<void> finish() async => finished++;
}

late FakeStopActions stopActions;
late FakeFinish finish;

class _Fixed implements SimulationClock {
  const _Fixed();
  @override
  DateTime now() => DateTime.utc(2026, 10, 11, 10);
}

Future<FakeRunner> show(WidgetTester tester, WalletOverview o) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final runner = FakeRunner();
  stopActions = FakeStopActions();
  finish = FakeFinish();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The Livret and companion cards have their own tests.
        livretLineProvider.overrideWith(
          (ref, id) async => throw const NotFoundFailure(),
        ),
        walletMomentProvider.overrideWith((ref, args) async => null),
        cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
        walletOverviewProvider.overrideWith((ref, id) async => o),
        walletChartProvider.overrideWith(
          (ref, args) async => chartFor(o.series, args.$2),
        ),
        tripRunnerProvider.overrideWith2((_) => runner),
        stopActionsProvider.overrideWith2((_) => stopActions),
        tripFinishProvider.overrideWith2((_) => finish),
        liveClockProvider.overrideWithValue(const _Fixed()),
      ],
      child: MainApp(
        router: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const WalletScreen(walletId: 'trip'),
            ),
            GoRoute(
              path: '/wallet/:id/summary',
              builder: (_, s) => Text('summary ${s.pathParameters['id']}'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return runner;
}

void main() {
  testWidgets('a trip: its header, its day, and time to move', (tester) async {
    final runner = await show(tester, trip());
    expect(find.text('Lehman'), findsNWidgets(2), reason: 'app bar and header');
    expect(find.widgetWithText(Chip, 'Réaliste'), findsOneWidget);
    expect(find.text('1er octobre 2008'), findsOneWidget);
    expect(find.byTooltip('Quitter le voyage'), findsOneWidget);

    await tester.tap(find.text('+1 semaine'));
    await tester.pump();
    await tester.tap(find.text('+1 jour'));
    await tester.pump();
    expect(runner.steps, [TripStep.week, TripStep.day]);
  });

  testWidgets('stopped by itself: no moving until the user decides', (
    tester,
  ) async {
    final runner = await show(tester, trip(status: WalletStatus.stopped));
    expect(find.text('Arrêt automatique : à toi de décider'), findsOneWidget);
    await tester.tap(find.text('+1 mois'));
    await tester.pump();
    expect(runner.steps, isEmpty);
  });

  testWidgets("« Avancer jusqu'à… »: a span or a day, then time moves", (
    tester,
  ) async {
    final runner = await show(tester, trip());
    await tester.tap(find.text('Avancer jusqu\'à…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+3 mois'));
    await tester.pumpAndSettle();
    expect(find.text('Avancer jusqu\'au 1er janvier 2009'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '15/09/2008');
    await tester.pumpAndSettle();
    expect(
      find.text('Choisis une date après le 1er octobre 2008.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '11/10/2026');
    await tester.pumpAndSettle();
    expect(
      find.text('Au plus tard le 10 octobre 2026, le dernier jour de cours.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '09/03/2009');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avancer jusqu\'au 9 mars 2009'));
    await tester.pumpAndSettle();
    expect(runner.targets, [DateTime.utc(2009, 3, 9)]);
  });

  testWidgets('the automatic stops, from the header', (tester) async {
    await show(tester, trip());
    await tester.tap(find.byTooltip('Arrêts automatiques'));
    await tester.pumpAndSettle();
    expect(
      find.text('Un versement mensuel arrive'),
      findsOneWidget,
      reason: '200 € a month',
    );
    await tester.tap(find.text('Un de tes ordres est exécuté'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    final saved = stopActions.saved.single;
    expect(
      saved.orderFilled,
      isTrue,
      reason: 'off in the fixture, switched on',
    );
  });

  testWidgets('« Terminer le voyage »: once confirmed, then the summary', (
    tester,
  ) async {
    await show(tester, trip());
    await tester.tap(find.text('Terminer le voyage'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Le voyage s'arrête au 1er octobre 2008 et ton bilan s'affiche. "
        'Le temps ne pourra plus avancer.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(finish.finished, 0);

    await tester.tap(find.text('Terminer le voyage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();
    expect(finish.finished, 1);
    expect(find.text('summary trip'), findsOneWidget);
  });

  testWidgets('the end of the data opens the summary', (tester) async {
    final runner = await show(tester, trip());
    runner.result = TripAdvance(
      state: TripState.start(day(10, 2), eur('10000')),
      events: const [],
      stop: const [],
      endOfData: true,
    );
    await tester.tap(find.text('+1 jour'));
    await tester.pumpAndSettle();
    expect(find.text('summary trip'), findsOneWidget);
  });

  testWidgets('finished: the summary, no more time or trading', (tester) async {
    final runner = await show(tester, trip(status: WalletStatus.finished));
    expect(find.text('Voyage terminé le 1er octobre 2008.'), findsOneWidget);
    expect(find.text('+1 jour'), findsNothing);
    expect(find.text('Investir'), findsNothing);
    expect(find.byTooltip('Arrêts automatiques'), findsNothing);
    expect(runner.steps, isEmpty);

    await tester.tap(find.text('Voir le bilan'));
    await tester.pumpAndSettle();
    expect(find.text('summary trip'), findsOneWidget);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester, trip());
    await expectAccessible(tester);
  });
}
