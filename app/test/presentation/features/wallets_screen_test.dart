import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/application/wallet/wallets_list.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/wallets/wallets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';

const nnbsp = ' ';
const nbsp = ' ';
Money eur(String s) => Money.book(Decimal.parse(s), Currency.eur);

WalletSummary summary(
  String id,
  WalletKind kind, {
  WalletStatus status = WalletStatus.active,
  String? difficulty,
  DateTime? start,
}) => WalletSummary(
  id: id,
  kind: kind,
  name: id == 'live' ? 'live' : 'Crise 2008',
  status: status,
  startDate: start ?? DateTime.utc(2008, 9, 15),
  simDate: kind == WalletKind.trip ? DateTime.utc(2008, 10, 1) : null,
  difficulty: difficulty,
  createdAt: DateTime.utc(2026, 10, 1),
);

/// A wallet worth [value] after [start] was put in.
WalletOverview valued(String id, String start, String value) => buildOverview(
  wallet: WalletState(
    id: id,
    kind: WalletKind.live,
    name: id,
    startDate: DateTime.utc(2026, 10, 1),
    simDate: null,
    status: WalletStatus.active,
    params: WalletParams(
      rules: TradingRules(
        fxFeeRate: Decimal.zero,
        fixedFee: const Money.zero(Currency.eur),
        fractionalShares: true,
      ),
      monthlyContribution: const Money.zero(Currency.eur),
      stops: const StopConditions(),
    ),
    cash: eur(value),
    fills: const [],
    positions: const {},
    pendingOrders: const [],
    values: [
      DailyValue(
        date: DateTime.utc(2026, 10, 1),
        value: eur(start),
        flow: eur(start),
      ),
    ],
    livretMovements: const [],
    plans: const [],
  ),
  asOf: DateTime.utc(2026, 10, 8),
  assets: const {},
  prices: const {},
  fxRates: const {},
  livret: Decimal.zero,
);

Future<GoRouter> show(WidgetTester tester, WalletsList list) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const WalletsScreen()),
      GoRoute(path: '/wallets/new', builder: (_, s) => Text('wizard ${s.uri}')),
      GoRoute(
        path: '/wallet/:id',
        builder: (_, s) => Text('wallet ${s.pathParameters['id']}'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        walletsListProvider.overrideWith((ref) async => list),
        walletOverviewProvider.overrideWith(
          (ref, id) async => id == 'live'
              ? valued(id, '50000', '51598.14')
              : valued(id, '10000', '9800'),
        ),
      ],
      child: MainApp(router: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  final march = BridgeSuggestion(
    'ae.march-2020',
    const Localized(
      'Mars 2020 : vendre ou tenir ?',
      'March 2020: sell or hold?',
    ),
    TripBridge(DateTime.utc(2020, 2, 18)),
  );

  testWidgets('the live wallet and the trips, with value and status', (
    tester,
  ) async {
    await show(
      tester,
      WalletsList(
        live: summary('live', WalletKind.live),
        trips: [
          summary(
            't1',
            WalletKind.trip,
            difficulty: 'realiste',
            status: WalletStatus.stopped,
          ),
        ],
        suggestions: const [],
      ),
    );
    expect(find.text('Mes portefeuilles'), findsOneWidget);
    expect(find.text("Aujourd'hui"), findsOneWidget);
    expect(find.text('En direct'), findsOneWidget);
    expect(find.text('Cours réels du jour'), findsOneWidget);
    expect(find.text('51${nnbsp}598,14$nbsp€'), findsOneWidget);
    expect(find.text('+3,20$nnbsp%'), findsOneWidget);

    expect(find.text('Voyages dans le temps'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'the trip count');
    expect(find.text('Crise 2008'), findsOneWidget);
    expect(find.text('Réaliste'), findsOneWidget);
    expect(find.text('En cours, tu es le 1er octobre 2008'), findsOneWidget);
    expect(find.text('9${nnbsp}800,00$nbsp€'), findsOneWidget);
    expect(find.text('−2,00$nnbsp%'), findsOneWidget);
    expect(
      find.text('Arrêt automatique$nnbsp: à toi de décider'),
      findsOneWidget,
    );
    expect(find.text('Nouveau voyage dans le temps'), findsOneWidget);
    expect(find.text('Suggéré par ta leçon'), findsNothing);

    await tester.tap(find.text('Crise 2008'));
    await tester.pumpAndSettle();
    expect(find.text('wallet t1'), findsOneWidget);
  });

  testWidgets('no trips yet: no count, the way to start one', (tester) async {
    await show(
      tester,
      WalletsList(
        live: summary('live', WalletKind.live),
        trips: const [],
        suggestions: const [],
      ),
    );
    expect(
      find.text(
        "Aucun voyage pour l'instant. Pars à une date du passé et avance dans le temps.",
      ),
      findsOneWidget,
    );
    expect(find.text('0'), findsNothing);
    await tester.tap(find.text('Nouveau voyage dans le temps'));
    await tester.pumpAndSettle();
    expect(find.text('wizard /wallets/new'), findsOneWidget);
  });

  testWidgets('a finished trip says the months it covered', (tester) async {
    await show(
      tester,
      WalletsList(
        live: summary('live', WalletKind.live),
        trips: [
          summary('t2', WalletKind.trip, status: WalletStatus.finished),
          summary(
            't3',
            WalletKind.trip,
            status: WalletStatus.finished,
            start: DateTime.utc(2008, 4, 1),
          ),
          summary(
            't4',
            WalletKind.trip,
            status: WalletStatus.finished,
            start: DateTime.utc(2008, 10, 1),
          ),
        ],
        suggestions: const [],
      ),
    );
    expect(
      find.text('Terminé, de septembre 2008 à octobre 2008'),
      findsOneWidget,
    );
    expect(find.text("Terminé, d'avril 2008 à octobre 2008"), findsOneWidget);
    expect(find.text('Terminé, en octobre 2008'), findsOneWidget);
    expect(find.textContaining('En cours'), findsNothing);
  });

  testWidgets('a completed lesson opens the wizard on its day', (tester) async {
    await show(
      tester,
      WalletsList(
        live: summary('live', WalletKind.live),
        trips: const [],
        suggestions: [march],
      ),
    );
    expect(find.text('Suggéré par ta leçon'), findsOneWidget);
    expect(
      find.text(
        'Mars 2020$nnbsp: vendre ou tenir$nnbsp? Tu as vu la réponse dans la '
        'leçon. Rejoue maintenant ce moment avec ton propre portefeuille.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Préparer ce voyage'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'wizard /wallets/new?step=1&date=2020-02-18&from=ae.march-2020',
      ),
      findsOneWidget,
    );
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(
      tester,
      WalletsList(
        live: summary('live', WalletKind.live),
        trips: [
          summary(
            't1',
            WalletKind.trip,
            difficulty: 'realiste',
            status: WalletStatus.stopped,
          ),
        ],
        suggestions: const [],
      ),
    );
    await expectAccessible(tester);
  });
}
