import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/island/island_screen.dart';
import 'package:finance_companion/presentation/features/island/sea_chart.dart';
import 'package:finance_companion/presentation/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';
import 'island_screen_test.dart'
    show StreamedProfiles, actionsEtf, lesBases, settle;

/// The port up close after Les bases' first five lessons and six of Actions &
/// ETF's, as the « Archipel » tab shows it (no place saved: where the way
/// starts).
Future<void> showPort(
  WidgetTester tester, {
  bool still = false,
  List<Override> extra = const [],
}) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (still) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  final profiles = StreamedProfiles({
    for (final n in lesBases.nodes.take(5)) n.id,
    for (final n in actionsEtf.nodes.take(6)) n.id,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => actionsEtf),
        contentPackProvider(lesBasesIsland)
            .overrideWith((ref) async => lesBases),
        profileRepositoryProvider.overrideWithValue(profiles),
        ...extra,
      ],
      child: MainApp(
        router: GoRouter(
          routes: [
            // The « Archipel » tab: the island the user is on (M13-6).
            GoRoute(path: '/', builder: (_, _) => const HomeTab()),
          ],
        ),
      ),
    ),
  );
  await settle(tester);
}

Future<void> openChart(WidgetTester tester) async {
  await tester.tap(find.text('Naviguer'));
  await settle(tester);
}

void main() {
  testWidgets('« Naviguer » opens the chart, Actions & ETF selected', (
    tester,
  ) async {
    await showPort(tester);
    await openChart(tester);
    expect(find.byType(SeaChartSheet), findsOneWidget);
    expect(find.text('La carte marine'), findsOneWidget);
    expect(
      find.text('Ta prochaine leçon : 7 · Les intérêts composés'),
      findsOneWidget,
    );
    expect(find.text('Embarquer'), findsOneWidget);
  });

  testWidgets('touching the ferry opens it too', (tester) async {
    await showPort(tester);
    await tester.tap(find.byKey(const ValueKey('ferry')));
    await settle(tester);
    expect(find.byType(SeaChartSheet), findsOneWidget);
  });

  testWidgets('each island said by screen readers, a closed one names its '
      'gates and cannot be boarded', (tester) async {
    await showPort(tester);
    await openChart(tester);
    expect(
      find.bySemanticsLabel(RegExp(r'^Actions & ETF, 6 sur 12 terminées$')),
      findsOneWidget,
    );
    final trading = find.bySemanticsLabel(RegExp(r'^Trading, s.ouvre après'));
    expect(trading, findsOneWidget);
    await tester.tap(trading);
    await tester.pump();
    expect(find.text('Fermée'), findsOneWidget);
    expect(find.textContaining('Repère l'), findsOneWidget);
    // Its « Embarquer » does nothing.
    await tester.tap(find.text('Embarquer'), warnIfMissed: false);
    await settle(tester);
    expect(find.byType(SeaChartSheet), findsOneWidget);
    expect(
      tester.widget<IslandScreen>(find.byType(IslandScreen)).islandId,
      lesBasesIsland,
    );
  });

  testWidgets(
    'boarding sails, then lands up close on the island, from its pier',
    (tester) async {
      await showPort(tester);
      await openChart(tester);
      await tester.tap(find.text('Embarquer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Traversée…'), findsOneWidget);
      await settle(tester);
      final island = tester.widget<IslandScreen>(find.byType(IslandScreen));
      expect(island.islandId, actionsEtfIsland);
      expect(island.arriving, isTrue);
      expect(find.byType(SeaChartSheet), findsNothing);
    },
  );

  testWidgets(
    'from an island, back to the port; with animations off, at once',
    (tester) async {
      await showPort(tester, still: true);
      await openChart(tester);
      await tester.tap(find.text('Embarquer'));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<IslandScreen>(find.byType(IslandScreen)).islandId,
        actionsEtfIsland,
      );
      await settle(tester);
      await openChart(tester);
      expect(find.text('Rentrer au port'), findsOneWidget);
      await tester.tap(find.text('Rentrer au port'));
      await settle(tester);
      expect(
        tester.widget<IslandScreen>(find.byType(IslandScreen)).islandId,
        lesBasesIsland,
      );
    },
  );

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await showPort(tester);
    await openChart(tester);
    await expectAccessible(tester);
  });
}
