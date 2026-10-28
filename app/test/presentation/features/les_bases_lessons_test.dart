import 'dart:io';

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/node/node_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/recording_profiles.dart';

// Les bases' lessons from the bundled pack (M12-5), beside Actions & ETF's,
// whose terms they link.

void main() {
  final bundled = [
    for (final island in ['actions-etf', 'les-bases'])
      decodePack(File('assets/packs/$island.json').readAsStringSync()),
  ];

  testWidgets('what notes buy: the curves credit INSEE\'s prices', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1170, 5400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentPacksProvider.overrideWith((ref) async => bundled),
          cacheStatusProvider.overrideWith(
            (ref) => Stream.value(const Fresh()),
          ),
          profileRepositoryProvider.overrideWithValue(RecordingProfiles()),
        ],
        child: MainApp.screen(const NodeScreen(nodeId: 'lb.cash-inflation')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moins'));
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Source : Insee, prix à la consommation mensuels, 2015–2025, '
        'en euros de décembre 2015.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ce qu\'ils achètent'), findsOneWidget);
  });
}
