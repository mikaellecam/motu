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
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/core/l10n/app_localizations.dart';
import 'package:finance_companion/core/l10n/formats.dart';
import 'package:finance_companion/core/theme/app_theme.dart';
import 'package:finance_companion/presentation/features/companion/companion_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../fakes/fake_backend.dart' show WallClock;

import '../../helpers.dart';

const nnbsp = ' ';
const nbsp = ' ';

Decimal d(String s) => Decimal.parse(s);

const names = CompanionNames(
  assets: {'apple': 'Apple'},
  terms: {
    'pire-baisse': Localized('Pire baisse', 'Worst drop'),
    'volatilite': Localized('Volatilité', 'Volatility'),
  },
  lessons: {
    'ae.apple-vs-world-2022': Localized(
      'Apple ou ETF Monde',
      'Apple or a world ETF',
    ),
  },
);

late AppDatabase db;

/// [rule] logged in the live wallet, on its card; routes print where they
/// lead.
Future<void> show(
  WidgetTester tester,
  CompanionRule rule,
  Map<String, Object> params,
) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await WalletRepository(db).ensureLiveWallet(DateTime.utc(2026, 10, 1));
  await db.learningDao.logMoment(
    CompanionLogCompanion.insert(
      walletId: 'live',
      rule: rule,
      key: '',
      firedAt: DateTime.utc(2026, 10, 6),
      params: encodeParams(params),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(
          WallClock(DateTime.utc(2026, 10, 11)),
        ),
        companionNamesProvider.overrideWith((ref) async => names),
      ],
      child: MaterialApp.router(
        theme: appTheme(),
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(
                body: SingleChildScrollView(
                  child: WalletCompanionCard(walletId: 'live'),
                ),
              ),
            ),
            GoRoute(
              path: '/node/:id',
              builder: (_, state) => Text('node ${state.pathParameters['id']}'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drift closes its watch queries on a timer once the tree is gone.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('a position drop: what happened, its terms and its lesson', (
    tester,
  ) async {
    await show(tester, CompanionRule.positionDrop, {
      'assetId': 'apple',
      'drop': d('-0.16'),
    });
    expect(find.text('Ton compagnon'), findsOneWidget);
    expect(find.text('Apple a reculé'), findsOneWidget);
    // The words say which way: no sign on the figure.
    expect(
      find.text(
        'Apple a perdu 16,00$nnbsp% depuis son plus haut atteint depuis ton '
        "achat. Une seule ligne peut bouger bien plus que l'ensemble du "
        'portefeuille.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(ActionChip, 'Pire baisse'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Volatilité'), findsOneWidget);

    await tester.tap(find.text('Revoir la leçon$nnbsp: Apple ou ETF Monde'));
    await tester.pumpAndSettle();
    expect(find.text('node ae.apple-vs-world-2022'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('three months after a sale: a signed change', (tester) async {
    await show(tester, CompanionRule.panicSellFollowUp, {
      'assetId': 'apple',
      'sellPrice': Price(d('150'), Currency.usd),
      'priceNow': Price(d('168'), Currency.usd),
      'change': d('0.12'),
    });
    expect(
      find.text(
        "Tu avais vendu Apple à 150,00$nbsp\$. Il vaut aujourd'hui "
        '168,00$nbsp\$ (+12,00$nnbsp%).',
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('« J\'ai compris »: the card goes, and stays gone', (
    tester,
  ) async {
    await show(tester, CompanionRule.fxSwing, {
      'move': d('0.041'),
      'exposure': d('0.8'),
    });
    expect(find.text('Le dollar a bougé'), findsOneWidget);
    await tester.tap(find.text("J'ai compris"));
    await tester.pumpAndSettle();
    expect(find.text('Le dollar a bougé'), findsNothing);
    final rows = await db.learningDao.unreadMoments();
    expect(rows, isEmpty);
    await unmount(tester);
  });

  test('every rule has its words', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('fr'));
    for (final rule in CompanionRule.values) {
      final params = <String, Object>{
        'assetId': 'apple',
        for (final k in [
          'drop',
          'drawdown',
          'weight',
          'cashWeight',
          'move',
          'exposure',
          'change',
        ])
          k: d('0.1'),
        'sellPrice': Price(d('10'), Currency.usd),
        'priceNow': Price(d('11'), Currency.usd),
      };
      final (title, body) = companionCopy(
        l10n,
        Formats('fr'),
        ActiveMoment(
          id: 1,
          walletId: 'live',
          rule: rule,
          key: '',
          firedAt: DateTime.utc(2026, 10, 6),
          params: params,
        ),
        asset: 'Apple',
      );
      expect(title, isNotEmpty, reason: rule.id);
      expect(body, isNotEmpty, reason: rule.id);
    }
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester, CompanionRule.positionDrop, {
      'assetId': 'apple',
      'drop': d('-0.16'),
    });
    await expectAccessible(tester);
    await unmount(tester);
  });
}
