import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_runner.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/wallet/wallet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the steps asked for instead of moving time.
class FakeRunner extends TripRunner {
  final steps = <TripStep>[];

  @override
  FutureOr<TripAdvance?> build(String walletId) => null;

  @override
  Future<void> advance(TripStep step) async => steps.add(step);
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

Future<FakeRunner> show(WidgetTester tester, WalletOverview o) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final runner = FakeRunner();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
        walletOverviewProvider.overrideWith((ref, id) async => o),
        walletChartProvider.overrideWith(
          (ref, args) async => chartFor(o.series, args.$2),
        ),
        tripRunnerProvider.overrideWith2((_) => runner),
      ],
      child: MainApp.screen(const WalletScreen(walletId: 'trip')),
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
}
