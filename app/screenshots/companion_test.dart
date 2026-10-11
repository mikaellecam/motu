import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/companion/companion.dart';
import 'package:finance_companion/application/learning/next_step_card.dart';
import 'package:finance_companion/application/learning/ui_level.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/data/repositories/companion_repository.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/next_step.dart';
import 'package:finance_companion/presentation/features/wallet/wallet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';
import 'wallet_test.dart' as wallet;

// The live wallet of the wallet screenshots: the world ETF weighs 32,6 %;
// a concentration moment on a profile with a low comfort (30 %).

final moment = ActiveMoment(
  id: 1,
  walletId: 'live',
  rule: CompanionRule.concentration,
  key: '',
  firedAt: DateTime.utc(2026, 10, 7),
  params: {'assetId': 'world', 'weight': Decimal.parse('0.326')},
);

final names = companionNamesProvider.overrideWith(
  (ref) async => const CompanionNames(
    assets: {'world': 'ETF Monde'},
    terms: {
      'concentration': Localized('Concentration', 'Concentration'),
      'diversification': Localized('Diversification', 'Diversification'),
    },
    lessons: {
      'ae.apple-vs-world-2022': Localized(
        'Apple ou ETF Monde : lequel a le plus chuté en 2022 ?',
        'Apple or a world ETF: which fell more in 2022?',
      ),
    },
  ),
);

void main() {
  screenshot(
    'm8-3-wallet-companion',
    const WalletScreen(walletId: 'live'),
    size: const Size(390, 1100),
    overrides: [
      ...wallet.overrides,
      names,
      walletMomentProvider.overrideWith((ref, args) async => moment),
    ],
    // The card's names arrive a frame after the card.
    act: (tester) => tester.pump(),
  );

  final map = [
    names,
    livingIslandProvider.overrideWith((ref) async => const []),
    currentUiLevelProvider.overrideWith((ref) async => 1),
    nextStepViewProvider.overrideWith(
      (ref) async => NextStepView(const ReadMoment('1'), moment: moment),
    ),
  ];

  screenshotRoute('m8-3-map-moment', '/', overrides: map);

  screenshotRoute(
    'm8-3-moment-sheet',
    '/',
    overrides: map,
    act: (tester) async {
      await tester.tap(find.text('Lire'));
    },
  );
}
