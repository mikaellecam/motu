import 'dart:io';

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/presentation/features/node/node_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// fixtures/actions-etf.json: two lessons drafted for the screenshots, on
// datasets frozen by cmd/freeze (Apple and the world ETF, weekly 2022; the
// world ETF, monthly 2008–2025). The island's real lessons come with M6-8.

void main() {
  final pack = decodePack(
    File('screenshots/fixtures/actions-etf.json').readAsStringSync(),
  );
  final overrides = <Override>[
    contentPackProvider(actionsEtfIsland).overrideWith((ref) async => pack),
    cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
  ];

  screenshot(
    'm6-3-predict-reveal',
    const NodeScreen(nodeId: 'ae.apple-vs-world-2022'),
    size: const Size(390, 1050),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('Apple'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );

  screenshot(
    'm6-3-toy',
    const NodeScreen(nodeId: 'ae.fees-toy'),
    size: const Size(390, 1110),
    overrides: overrides,
  );
}
