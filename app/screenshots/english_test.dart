import 'dart:io';

import 'package:finance_companion/application/companion/companion.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/next_step_card.dart';
import 'package:finance_companion/application/learning/ui_level.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/next_step.dart';
import 'package:finance_companion/presentation/features/node/node_screen.dart';
import 'package:finance_companion/presentation/features/wallet/wallet_screen.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'companion_test.dart' as companion;
import 'map_test.dart' as map;
import 'screenshot.dart';
import 'wallet_test.dart' as wallet;

// The English pass (M9-2): the same screens, in English.

void main() {
  screenshot(
    'm9-2-wallet-en',
    const WalletScreen(walletId: 'live'),
    locale: 'en',
    size: const Size(390, 1100),
    overrides: [
      ...wallet.overrides,
      companion.names,
      walletMomentProvider.overrideWith((ref, args) async => companion.moment),
    ],
    act: (tester) => tester.pump(),
  );

  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );
  screenshot(
    'm9-2-lesson-en',
    const NodeScreen(nodeId: 'ae.dollar-trap'),
    locale: 'en',
    size: const Size(390, 1250),
    overrides: [
      contentPackProvider(actionsEtfIsland).overrideWith((ref) async => pack),
      lesBasesPack,
      cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
    ],
    act: (tester) async {
      await tester.tap(find.text('About 14%'));
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
    },
  );

  screenshotRoute(
    'm9-2-map-en',
    '/',
    locale: 'en',
    overrides: [
      map.island,
      currentUiLevelProvider.overrideWith((ref) async => 2),
      nextStepViewProvider.overrideWith(
        (ref) async => const NextStepView(
          PlayNode('ae.fees-toy'),
          title: Localized('Le jouet des frais', 'The fees toy'),
        ),
      ),
    ],
  );
}
