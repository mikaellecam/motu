import 'dart:async';

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/repositories/profile_repository.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/path.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/island/island_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../fakes/lesson_pack.dart';

import '../../helpers.dart';

/// No profile; completions come from [completions], Les bases' fifth lesson
/// always among them: Actions & ETF's lessons are open (M12-7).
class StreamedProfiles extends Fake implements ProfileRepository {
  final completions = StreamController<Set<String>>.broadcast();
  Set<String> last = const {'lb.cushion-2020'};

  @override
  Stream<Set<String>> watchCompletedNodes() async* {
    yield last;
    yield* completions.stream;
  }

  void complete(Set<String> ids) {
    last = {...ids, 'lb.cushion-2020'};
    completions.add(last);
  }

  @override
  Future<Profile?> load() async => null;
  @override
  Future<void> save(Profile profile) async {}
  @override
  Future<bool> showAll() async => false;
  @override
  Future<Set<String>> completedNodes() async => last;
  @override
  Stream<Map<String, DateTime>> watchCompletions() => watchCompletedNodes().map(
    (ids) => {for (final id in ids) id: DateTime.utc(2026, 10, 1)},
  );
  @override
  Future<void> completeNode(
    String nodeId, {
    String? answer,
    required DateTime at,
  }) async {}
}

late StreamedProfiles profiles;

Future<void> show(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  profiles = StreamedProfiles();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => decodePack(packJson())),
        contentPackProvider(lesBasesIsland)
            .overrideWith((ref) async => decodePack(emptyBasesJson())),
        profileRepositoryProvider.overrideWithValue(profiles),
        livingIslandProvider.overrideWith((ref) async => const []),
      ],
      child: MainApp(
        router: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const IslandScreen(islandId: 'actions-etf'),
            ),
            GoRoute(
              path: '/node/:id',
              builder: (_, s) => Text('node ${s.pathParameters['id']}'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the path in order, with progress', (tester) async {
    await show(tester);
    expect(find.text('Actions & ETF'), findsOneWidget);
    expect(find.text('0 sur 3 terminées'), findsOneWidget);
    // The current lesson in its card, the others beside their islets.
    expect(find.text('Apple ou ETF Monde ?'), findsOneWidget);
    expect(find.text('Prédiction'), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
    expect(find.text('Jouet · verrouillée'), findsOneWidget);
    expect(find.text('Mission · verrouillée'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        '1. Apple ou ETF Monde ?, Prédiction, à toi de jouer',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('2. Le jouet des frais, Jouet, verrouillée'),
      findsOneWidget,
    );
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect((progress.value, progress.color), (0.0, AppColors.progress));
  });

  testWidgets(
    'a locked node stays shut; the current one starts from its card',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Le jouet des frais'));
      await tester.pumpAndSettle();
      expect(find.text('node ae.fees'), findsNothing);

      await tester.tap(find.text('Commencer'));
      await tester.pumpAndSettle();
      expect(find.text('node ae.apple'), findsOneWidget);
    },
  );

  testWidgets('a lesson opens from its islet too', (tester) async {
    await show(tester);
    await tester.tap(
      find.bySemanticsLabel(
        '1. Apple ou ETF Monde ?, Prédiction, à toi de jouer',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('node ae.apple'), findsOneWidget);
  });

  testWidgets('a completion moves the path on while it is shown', (
    tester,
  ) async {
    await show(tester);
    profiles.complete({'ae.apple'});
    await tester.pumpAndSettle();
    expect(find.text('1 sur 3 terminées'), findsOneWidget);
    expect(find.text('Prédiction · terminée'), findsOneWidget);
    expect(
      find.bySemanticsLabel('2. Le jouet des frais, Jouet, à toi de jouer'),
      findsOneWidget,
    );
    expect(find.text('Mission · verrouillée'), findsOneWidget);
    expect(find.text('Jouet'), findsOneWidget);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester);
    await expectAccessible(tester);
  });

  testWidgets('closed: every islet locked, its header names the lesson it '
      'waits for (M12-7)', (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final pack = decodePack(packJson());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          islandPathProvider(actionsEtfIsland).overrideWith(
            (ref) async => IslandPathView(
              pack.title,
              [for (final n in pack.nodes) PathNode(n, NodeState.locked)],
              open: false,
              opensAfter: const Localized(
                'Février 2020\u202f: et ton matelas\u202f?',
                'February 2020: and your cushion?',
              ),
            ),
          ),
          livingIslandProvider.overrideWith((ref) async => const []),
        ],
        child: MainApp.screen(const IslandScreen(islandId: actionsEtfIsland)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        "S'ouvre après «\u00a0Février 2020\u202f: et ton matelas\u202f?\u00a0»",
      ),
      findsOneWidget,
    );
    expect(find.text('Commencer'), findsNothing);
  });
}
