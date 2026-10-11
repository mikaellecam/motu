import 'dart:async';

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/repositories/profile_repository.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/island/island_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../fakes/lesson_pack.dart';

/// No profile; completions come from [completions].
class StreamedProfiles extends Fake implements ProfileRepository {
  final completions = StreamController<Set<String>>.broadcast();
  Set<String> last = const {};

  @override
  Stream<Set<String>> watchCompletedNodes() async* {
    yield last;
    yield* completions.stream;
  }

  void complete(Set<String> ids) {
    last = ids;
    completions.add(ids);
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
        profileRepositoryProvider.overrideWithValue(profiles),
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
    expect(find.text('Apple ou ETF Monde ?'), findsOneWidget);
    expect(find.text('Prédiction'), findsOneWidget);
    expect(find.text('Jouet'), findsOneWidget);
    expect(find.text('À toi'), findsOneWidget);
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
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect((progress.value, progress.color), (0.0, AppColors.progress));
  });

  testWidgets('a locked node stays shut; an open one opens its player', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Le jouet des frais'));
    await tester.pumpAndSettle();
    expect(find.text('node ae.fees'), findsNothing);

    await tester.tap(find.text('Apple ou ETF Monde ?'));
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
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      find.bySemanticsLabel('2. Le jouet des frais, Jouet, à toi de jouer'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });
}
