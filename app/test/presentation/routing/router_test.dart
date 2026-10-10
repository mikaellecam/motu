import 'package:drift/native.dart';
import 'package:finance_companion/application/explorer/explorer.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/asset/asset_screen.dart';
import 'package:finance_companion/presentation/features/explorer/explorer_screen.dart';
import 'package:finance_companion/presentation/features/onboarding/onboarding_screen.dart';
import 'package:finance_companion/presentation/features/wallet/wallet_screen.dart';
import 'package:finance_companion/presentation/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> open(WidgetTester tester, String location) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // Navigation only: no catalogue behind the Explorer tab.
        explorerRowsProvider.overrideWith((ref, walletId) async => const []),
        favoritesProvider.overrideWithBuild(
          (ref, notifier) => Stream.value({}),
        ),
      ],
      child: MainApp(router: buildRouter(initialLocation: location)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the app opens on the map, under four tabs', (tester) async {
    await open(tester, '/');
    expect(find.byType(MapTab), findsOneWidget);
    expect(find.text('Ton archipel'), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(4));
    expect(bar.selectedIndex, 0);
    expect(tester.getSize(find.byType(NavigationBar)).height, 80);
  });

  testWidgets('each tab is one tap away', (tester) async {
    await open(tester, '/');
    for (final (label, screen) in [
      ('Portefeuille', WalletsTab),
      ('Explorer', ExplorerScreen),
      ('Glossaire', GlossaryTab),
      ('Carte', MapTab),
    ]) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: label);
    }
  });

  testWidgets('settings open from the map header', (tester) async {
    await open(tester, '/');
    final settings = find.byTooltip('Paramètres');
    expect(settings, findsOneWidget);
    expect(
      tester.getSize(find.byType(IconButton)).width,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.byType(PendingScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  for (final location in [
    '/settings',
    '/tools/dca',
    '/island/actions-etf',
    '/node/ae.fees-toy',
    '/wallets/new',
    '/wallet/t1/stop/e1',
    '/wallet/t1/summary',
    '/wallet/t1/order/o1',
  ]) {
    testWidgets('$location opens full screen', (tester) async {
      await open(tester, location);
      expect(find.byType(PendingScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  }

  testWidgets('/asset/:id opens the asset full screen, in its wallet', (
    tester,
  ) async {
    await open(tester, '/asset/cw8?wallet=t1');
    final screen = tester.widget<AssetScreen>(find.byType(AssetScreen));
    expect((screen.assetId, screen.walletId), ('cw8', 't1'));
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('/wallet/:id opens the wallet full screen', (tester) async {
    await open(tester, '/wallet/live');
    expect(find.byType(WalletScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('/onboarding opens the questionnaire', (tester) async {
    await open(tester, '/onboarding');
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('an unknown location goes back to the map', (tester) async {
    await open(tester, '/nowhere');
    expect(find.byType(MapTab), findsOneWidget);
  });

  testWidgets('a lesson bridge deep-links into the prefilled wizard', (
    tester,
  ) async {
    await open(
      tester,
      '/wallets/new?step=1&date=2020-02-18&difficulty=realiste&from=ae.march-2020',
    );
    final args =
        tester.widget<PendingScreen>(find.byType(PendingScreen)).args!
            as TripWizardArgs;
    expect(args.step, 1);
    expect(args.date, DateTime.utc(2020, 2, 18));
    expect(args.difficulty, 'realiste');
    expect(args.fromNode, 'ae.march-2020');
  });

  group('TripWizardArgs.fromQuery', () {
    final cases = <(Map<String, String>, int, DateTime?)>[
      ({}, 1, null),
      ({'step': '3'}, 3, null),
      ({'step': '0'}, 1, null),
      ({'step': '4'}, 1, null),
      ({'step': 'two'}, 1, null),
      ({'date': '2008-09-15'}, 1, DateTime.utc(2008, 9, 15)),
      ({'date': '15/09/2008'}, 1, null),
    ];
    for (final (query, step, date) in cases) {
      test('$query', () {
        final args = TripWizardArgs.fromQuery(query);
        expect(args.step, step);
        expect(args.date, date);
      });
    }
  });
}
