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
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';

/// No profile; completions come from [complete], Les bases' fifth lesson
/// always among them: Actions & ETF's lessons are open (M12-7).
class StreamedProfiles extends Fake implements ProfileRepository {
  StreamedProfiles(Set<String> done, {bool fifth = true, this.profile})
    : last = {...done, if (fifth) 'lb.cushion-2020'};

  /// The questionnaire's answers, none by default.
  final Profile? profile;

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

  /// Where the app opens (M13-6).
  String? saved;

  @override
  Future<String?> place() async => saved;
  @override
  Future<void> setPlace(String island) async => saved = island;

  @override
  Future<Profile?> load() async => profile;
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
  List<Override> extra = const [],
  bool fifth = true,
  Profile? profile,
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
  profiles = StreamedProfiles(
    {for (final n in pack.nodes.take(done)) n.id},
    fifth: fifth,
    profile: profile,
  );
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
  testWidgets('a marker per lesson unlocked, said by screen readers, 44 px '
      'each; none for a locked one (M13-7)', (tester) async {
    await show(tester);
    expect(find.text('Actions & ETF'), findsOneWidget);
    expect(find.text('6 sur 12 terminées'), findsOneWidget);
    expect(find.text('6/12'), findsOneWidget);
    // Six done and the one to do.
    expect(markers(), findsNWidgets(7));
    for (final (n, title, piece, state) in [
      (1, r'Livret ou ETF.\?', 'La banque', 'terminée'),
      (7, 'Les intérêts composés', 'Le square', 'à toi de jouer'),
    ]) {
      final marker = find.bySemanticsLabel(
        RegExp('^$n\\. $title, $piece, $state\$'),
      );
      expect(marker, findsOneWidget, reason: '$n');
      expect(tester.getSize(marker), const Size(44, 44));
    }
    expect(find.bySemanticsLabel(RegExp(r'^12\. ')), findsNothing);
    // The six done grown, the others plain; the seventh, unlocked, under
    // its ghost, its marker on the ghost's top.
    final w = world(tester);
    expect(w.grown, [for (var i = 0; i < 12; i++) i < 6 ? 1 : 0]);
    expect(
      w.anchors[6],
      districtWorld(List.filled(12, 1), ferry: true).anchors[6],
    );
  });

  testWidgets('no card until a marker is touched; touching the island '
      'closes it (M13-9)', (tester) async {
    await show(tester);
    expect(find.text('Commencer'), findsNothing);
    expect(find.text('Le square · à toi de jouer'), findsNothing);

    await tester.tap(find.bySemanticsLabel(RegExp(r'^7\. ')));
    await tester.pump();
    expect(find.text('Les intérêts composés'), findsOneWidget);
    expect(find.text('Le square · à toi de jouer'), findsOneWidget);

    // Touching the island, away from any marker.
    await tester.tapAt(
      tester.getRect(find.byType(IslandScene)).bottomLeft +
          const Offset(20, -300),
    );
    await tester.pump();
    expect(find.text('Commencer'), findsNothing);

    await tester.tap(find.bySemanticsLabel(RegExp(r'^7\. ')));
    await tester.pump();
    await tester.tap(find.text('Commencer'));
    await settle(tester);
    expect(find.text('node ae.compound-toy'), findsOneWidget);
  });

  testWidgets('a lesson done replays', (tester) async {
    await show(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^1\. ')));
    await tester.pump();
    expect(find.text('La banque · terminée'), findsOneWidget);
    await tester.tap(find.text('Revoir'));
    await settle(tester);
    expect(find.text('node ae.livret-vs-etf'), findsOneWidget);
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
    // Rising into its ghost, whole until it has risen (M13-17).
    expect(world(tester).fading, {6: 1});
    await settle(tester);
    expect(world(tester).grown[6], 1);
    expect(world(tester).fading, isEmpty);
    expect(
      find.bySemanticsLabel(RegExp(r'^8\. .*, Le port, à toi de jouer$')),
      findsOneWidget,
    );
    // No card: none was touched.
    expect(find.text('Commencer'), findsNothing);
  });

  testWidgets('with animations off, the building stands grown at once', (
    tester,
  ) async {
    await show(tester, still: true);
    profiles.complete({'ae.compound-toy'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(world(tester).grown[6], 1);
    expect(world(tester).fading, isEmpty);
  });

  testWidgets('the port: a part done rises into its ghost, which fades '
      '(M13-17)', (tester) async {
    await show(tester, islandId: lesBasesIsland, done: 5);
    profiles.complete({'lb.loan-cost'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(world(tester).grown[5], inExclusiveRange(0, 1));
    expect(world(tester).fading, {5: 1});
    // Near the end, the ghost fading.
    await tester.pump(const Duration(milliseconds: 600));
    expect(world(tester).fading[5], inExclusiveRange(0, 1));
    await settle(tester);
    expect(world(tester).grown[5], 1);
    expect(world(tester).fading, isEmpty);
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

  testWidgets('closed: no marker, the gate named (M12-7, M13-7)', (
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
    // In the bar; no card, no marker to touch (M13-9).
    expect(find.textContaining('Février 2020'), findsOneWidget);
    // Every lesson locked: no marker at all (M13-7).
    expect(markers(), findsNothing);
  });

  testWidgets('Les bases up close: its port, a marker per part (M13-3)', (
    tester,
  ) async {
    await show(tester, islandId: lesBasesIsland, done: 5);
    expect(find.text('Les bases'), findsOneWidget);
    // Five done and the one to do (M13-7).
    expect(markers(), findsNWidgets(6));
    expect(world(tester).grown, [for (var i = 0; i < 9; i++) i < 5 ? 1 : 0]);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^6\. ')));
    await tester.pump();
    expect(find.text('La grue · à toi de jouer'), findsOneWidget);
  });

  testWidgets("a skipper's port: its five parts stand, the gold pin on the "
      'crane (M13-12)', (tester) async {
    await show(
      tester,
      islandId: lesBasesIsland,
      done: 0,
      fifth: false,
      profile: const Profile(
        goal: Goal.longTerm,
        dropReaction: DropReaction.buyMore,
        knowledge: Knowledge.alreadyInvesting,
        savings: Savings.invested,
      ),
    );
    await settle(tester);
    // The five standing open to replay, the crane to play, the rest locked.
    expect(markers(), findsNWidgets(6));
    expect(
      find.bySemanticsLabel(RegExp(r'^1\. .*, La digue, ouverte$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^6\. .*, La grue, à toi de jouer$')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'^7\. ')), findsNothing);
    expect(tester.widget<IslandScene>(find.byType(IslandScene)).focus, 5);
  });

  testWidgets('no sea before the ferry quay: no « Naviguer », no line, no '
      'ferry; the first line opens them (M13-7)', (tester) async {
    await show(tester, islandId: lesBasesIsland, done: 3, fifth: false);
    expect(find.text('Naviguer'), findsNothing);
    expect(find.byKey(const ValueKey('ferry')), findsNothing);
    expect(
      tester.widget<IslandScene>(find.byType(IslandScene)).onFerry,
      isNull,
    );

    await show(tester, islandId: lesBasesIsland, done: 5);
    expect(find.text('Naviguer'), findsOneWidget);
    expect(
      tester.widget<IslandScene>(find.byType(IslandScene)).onFerry,
      isNotNull,
    );
  });

  group('bounds and zoom (M13-8)', () {
    Future<void> pinch(WidgetTester tester, {required bool inwards}) async {
      final centre = tester.getCenter(find.byType(IslandScene));
      for (var i = 0; i < 4; i++) {
        final (from, to) = inwards ? (20.0, 160.0) : (160.0, 20.0);
        final a = await tester.startGesture(centre - Offset(from, 0));
        final b = await tester.startGesture(centre + Offset(from, 0));
        // In small steps, as fingers move.
        for (var k = 1; k <= 10; k++) {
          final at = from + (to - from) * k / 10;
          await a.moveTo(centre - Offset(at, 0));
          await b.moveTo(centre + Offset(at, 0));
          await tester.pump();
        }
        await a.up();
        await b.up();
        await settle(tester);
      }
    }

    IslandSceneState scene(WidgetTester tester) =>
        tester.state<IslandSceneState>(find.byType(IslandScene));

    testWidgets('the port never shows beyond its harbour', (tester) async {
      await show(tester, islandId: lesBasesIsland, done: 5);
      final bounds = Offset.zero & scene(tester).canvas;
      expect(scene(tester).canvas, world(tester).size);
      bool inside() {
        final shown = scene(tester).shown.deflate(0.5);
        return bounds.contains(shown.topLeft) &&
            bounds.contains(shown.bottomRight);
      }

      expect(inside(), isTrue);
      for (final drag in const [
        Offset(0, 4000),
        Offset(4000, 0),
        Offset(0, -8000),
        Offset(-8000, 0),
      ]) {
        await tester.drag(find.byType(IslandScene), drag);
        await settle(tester);
        expect(
          inside(),
          isTrue,
          reason: '$drag: ${scene(tester).shown} in $bounds',
        );
      }
      await pinch(tester, inwards: false);
      expect(inside(), isTrue, reason: 'pinched: ${scene(tester).shown}');
    });

    for (final island in [actionsEtfIsland, lesBasesIsland]) {
      testWidgets('$island zooms in to 2.5×', (tester) async {
        await show(tester, islandId: island, done: 5);
        await pinch(tester, inwards: true);
        expect(scene(tester).scale, closeTo(IslandScene.maxZoom, 1e-6));
      });
    }
  });
}
