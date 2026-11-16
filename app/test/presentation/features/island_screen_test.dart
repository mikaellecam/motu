import 'dart:async';
import 'dart:io';

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/repositories/profile_repository.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/path.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/island/island_scene.dart';
import 'package:finance_companion/presentation/features/island/island_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';

/// No profile; completions come from [complete], Les bases' fifth lesson
/// always among them: Actions & ETF's lessons are open (M12-7).
class StreamedProfiles extends Fake implements ProfileRepository {
  StreamedProfiles(Set<String> done) : last = {...done, 'lb.cushion-2020'};

  final completions = StreamController<Set<String>>.broadcast();
  Set<String> last;

  @override
  Stream<Set<String>> watchCompletedNodes() async* {
    yield last;
    yield* completions.stream;
  }

  void complete(Set<String> ids) {
    last = {...last, ...ids};
    completions.add(last);
  }

  @override
  Future<Profile?> load() async => null;
  @override
  Future<bool> showAll() async => false;
  @override
  Future<Set<String>> completedNodes() async => last;
  @override
  Stream<Map<String, DateTime>> watchCompletions() => watchCompletedNodes().map(
    (ids) => {for (final id in ids) id: DateTime.utc(2026, 10, 1)},
  );
}

final actionsEtf = decodePack(
  File('assets/packs/actions-etf.json').readAsStringSync(),
);
final lesBases = decodePack(
  File('assets/packs/les-bases.json').readAsStringSync(),
);

late StreamedProfiles profiles;

/// Actions & ETF up close (or [islandId]), its first [done] lessons done.
Future<void> show(
  WidgetTester tester, {
  int done = 6,
  String islandId = actionsEtfIsland,
  bool still = false,
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
  final pack = islandId == actionsEtfIsland ? actionsEtf : lesBases;
  profiles = StreamedProfiles({for (final n in pack.nodes.take(done)) n.id});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => actionsEtf),
        contentPackProvider(lesBasesIsland)
            .overrideWith((ref) async => lesBases),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
      child: MainApp(
        router: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => IslandScreen(islandId: islandId),
            ),
            GoRoute(
              path: '/node/:id',
              builder: (_, s) => Text('node ${s.pathParameters['id']}'),
            ),
            GoRoute(
              path: '/settings',
              builder: (_, _) => const Text('settings'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The gold pin pulses for ever: frames enough for the rest to end.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 1));
}

IslandWorld world(WidgetTester tester) =>
    tester.widget<IslandScene>(find.byType(IslandScene)).world;

/// The markers on screen, by their screen reader's label.
Finder markers() => find.bySemanticsLabel(RegExp(r'^\d+\. '));

Rect sceneRect(WidgetTester tester) => tester.getRect(find.byType(IslandScene));

void main() {
  testWidgets('a marker per lesson, said by screen readers, 44 px each', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Actions & ETF'), findsOneWidget);
    expect(find.text('6 sur 12 terminées'), findsOneWidget);
    expect(find.text('6/12'), findsOneWidget);
    expect(markers(), findsNWidgets(12));
    for (final (n, title, piece, state) in [
      (1, r'Livret ou ETF.\?', 'La banque', 'terminée'),
      (7, 'Les intérêts composés', 'Le square', 'à toi de jouer'),
      (12, "Point d'étape", "La flèche d'or", 'verrouillée'),
    ]) {
      final marker = find.bySemanticsLabel(
        RegExp('^$n\\. $title, $piece, $state\$'),
      );
      expect(marker, findsOneWidget, reason: '$n');
      expect(tester.getSize(marker), const Size(44, 44));
    }
    // The six done grown, the others plain.
    expect(world(tester).grown, [for (var i = 0; i < 12; i++) i < 6 ? 1 : 0]);
  });

  testWidgets('the card follows the marker touched', (tester) async {
    await show(tester);
    // The lesson to do first.
    expect(find.text('Les intérêts composés'), findsOneWidget);
    expect(find.text('Le square · à toi de jouer'), findsOneWidget);
    await tester.tap(find.text('Commencer'));
    await settle(tester);
    expect(find.text('node ae.compound-toy'), findsOneWidget);
  });

  testWidgets('a lesson done replays; a later one waits for the one before', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^1\. ')));
    await tester.pump();
    expect(find.text('La banque · terminée'), findsOneWidget);
    await tester.tap(find.text('Revoir'));
    await settle(tester);
    expect(find.text('node ae.livret-vs-etf'), findsOneWidget);

    await show(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^12\. ')));
    await tester.pump();
    expect(find.text("La flèche d'or · verrouillée"), findsOneWidget);
    final wait = find.textContaining('Mets en place un DCA');
    expect(wait, findsOneWidget);
    await tester.tap(wait, warnIfMissed: false);
    await settle(tester);
    expect(find.textContaining('node '), findsNothing);
  });

  testWidgets('pan and zoom stay within bounds', (tester) async {
    await show(tester);
    final scene = sceneRect(tester);
    bool anyOnScreen() => markers().evaluate().any(
      (e) => scene.contains(tester.getCenter(find.byWidget(e.widget))),
    );
    for (final drag in const [
      Offset(3000, 0),
      Offset(-6000, 0),
      Offset(0, 3000),
      Offset(0, -6000),
    ]) {
      await tester.drag(find.byType(IslandScene), drag);
      await settle(tester);
      expect(anyOnScreen(), isTrue, reason: '$drag');
    }
    // Pinched all the way out, the island fits whole: every marker shows.
    final centre = scene.center;
    for (var i = 0; i < 4; i++) {
      final a = await tester.startGesture(centre - const Offset(150, 0));
      final b = await tester.startGesture(centre + const Offset(150, 0));
      await a.moveTo(centre - const Offset(10, 0));
      await b.moveTo(centre + const Offset(10, 0));
      await a.up();
      await b.up();
      await settle(tester);
    }
    for (final e in markers().evaluate()) {
      expect(scene.contains(tester.getCenter(find.byWidget(e.widget))), isTrue);
    }
  });

  testWidgets('a lesson done grows its building, then the gold pin moves on', (
    tester,
  ) async {
    await show(tester);
    profiles.complete({'ae.compound-toy'});
    await tester.pump();
    // The ticker starts on the frame after.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(world(tester).grown[6], inExclusiveRange(0, 1));
    await settle(tester);
    expect(world(tester).grown[6], 1);
    expect(
      find.bySemanticsLabel(RegExp(r'^8\. .*, Le port, à toi de jouer$')),
      findsOneWidget,
    );
    expect(find.text('Trois zones géographiques'), findsOneWidget);
  });

  testWidgets('with animations off, the building stands grown at once', (
    tester,
  ) async {
    await show(tester, still: true);
    profiles.complete({'ae.compound-toy'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(world(tester).grown[6], 1);
  });

  testWidgets('settings open from the bar', (tester) async {
    await show(tester);
    await tester.tap(find.byTooltip('Paramètres'));
    await settle(tester);
    expect(find.text('settings'), findsOneWidget);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester);
    await expectAccessible(tester);
  });

  testWidgets('closed: every lesson later, the gate named (M12-7)', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          islandPathProvider(actionsEtfIsland).overrideWith(
            (ref) async => IslandPathView(
              actionsEtf.title,
              [for (final n in actionsEtf.nodes) PathNode(n, NodeState.locked)],
              open: false,
              opensAfter: const Localized(
                'Février 2020 : et ton matelas ?',
                'February 2020: and your cushion?',
              ),
            ),
          ),
        ],
        child: MainApp.screen(const IslandScreen(islandId: actionsEtfIsland)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // In the bar, and on the card's button.
    expect(find.textContaining('Février 2020'), findsNWidgets(2));
    expect(
      find.bySemanticsLabel(RegExp(r'^\d+\. .*verrouillée$')),
      findsNWidgets(12),
    );
  });

  testWidgets('Les bases up close: its port, a marker per part (M13-3)', (
    tester,
  ) async {
    await show(tester, islandId: lesBasesIsland, done: 5);
    expect(find.text('Les bases'), findsOneWidget);
    expect(markers(), findsNWidgets(9));
    expect(world(tester).grown, [for (var i = 0; i < 9; i++) i < 5 ? 1 : 0]);
    expect(find.text('La grue · à toi de jouer'), findsOneWidget);
  });
}
