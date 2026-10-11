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

// The island's lessons as the app bundles them (M6-8, draft copy on
// datasets frozen by cmd/freeze).

void main() {
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
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

  // Captured a second into the reveal: the curves half drawn, the figures
  // still counting (M7-4).
  screenshot(
    'm7-4-reveal-drawing',
    const NodeScreen(nodeId: 'ae.livret-vs-etf'),
    size: const Size(390, 1150),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('À peu près pareil'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
    },
  );

  screenshot(
    'm6-8-livret-vs-etf',
    const NodeScreen(nodeId: 'ae.livret-vs-etf'),
    size: const Size(390, 1150),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('À peu près pareil'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );

  screenshot(
    'm6-8-dollar-trap',
    const NodeScreen(nodeId: 'ae.dollar-trap'),
    size: const Size(390, 1250),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('Environ 14\u202f%'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );

  screenshot(
    'm6-8-compound-toy',
    const NodeScreen(nodeId: 'ae.compound-toy'),
    size: const Size(390, 1050),
    overrides: overrides,
  );

  screenshot(
    'm6-3-toy',
    const NodeScreen(nodeId: 'ae.fees-toy'),
    size: const Size(390, 1110),
    overrides: overrides,
  );

  screenshot(
    'm6-4-decision',
    const NodeScreen(nodeId: 'ae.march-2020'),
    size: const Size(390, 1400),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('Garder'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );

  screenshot(
    'm6-4-sort',
    const NodeScreen(nodeId: 'ae.risk-ladder'),
    size: const Size(390, 760),
    overrides: overrides,
    act: (tester) async {
      // Apple from the top to the bottom, then the real order.
      final handle = find.byIcon(Icons.drag_handle).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );

  screenshot(
    'm6-4-build-puzzle',
    const NodeScreen(nodeId: 'ae.calm-portfolio'),
    size: const Size(390, 900),
    overrides: overrides,
    act: (tester) async {
      // US bonds 50 %, international bonds 30 %, European stocks 20 %.
      for (final (i, share) in [(1, 0.5), (2, 0.3), (3, 0.2)]) {
        final slider = tester.getRect(find.byType(Slider).at(i));
        // The track starts and ends 24 px inside the slider.
        await tester.tapAt(
          Offset(
            slider.left + 24 + (slider.width - 48) * share,
            slider.center.dy,
          ),
        );
        await tester.pumpAndSettle();
      }
    },
  );

  screenshot(
    'm6-4-checkpoint',
    const NodeScreen(nodeId: 'ae.checkpoint-1'),
    size: const Size(390, 760),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.textContaining("Des milliers d'entreprises"));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
    },
  );
}
