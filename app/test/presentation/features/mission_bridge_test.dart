import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/node/node_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../fakes/lesson_pack.dart';
import '../../fakes/recording_profiles.dart';

import '../../helpers.dart';

Future<void> show(
  WidgetTester tester,
  String nodeId, {
  Set<String> completed = const {},
}) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 5400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => decodePack(packJson())),
        contentPackProvider(lesBasesIsland)
            .overrideWith((ref) async => decodePack(emptyBasesJson())),
        completedNodesProvider.overrideWith((ref) => Stream.value(completed)),
        cacheStatusProvider.overrideWith(
          (ref) => Stream.value(const Offline(null)),
        ),
        profileRepositoryProvider.overrideWithValue(RecordingProfiles()),
      ],
      child: MainApp(
        router: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => NodeScreen(nodeId: nodeId),
            ),
            GoRoute(
              path: '/explore',
              builder: (_, s) =>
                  Text('explore ${s.uri.queryParameters['wallet']}'),
            ),
            GoRoute(
              path: '/wallets/new',
              builder: (_, s) => Text('wizard ${s.uri.query}'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a mission: what to do, and the way there', (tester) async {
    await show(tester, 'ae.mission');
    expect(find.text('Ton premier ETF'), findsOneWidget);
    expect(find.text('Achète un ETF dans ton portefeuille.'), findsOneWidget);
    expect(
      find.text(
        'Elle se valide toute seule dès que ton portefeuille la remplit.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continuer'), findsNothing);
    await tester.tap(find.text("Ouvrir l'Explorer"));
    await tester.pumpAndSettle();
    expect(find.text('explore live'), findsOneWidget);
  });

  testWidgets('a mission done says so, then continues', (tester) async {
    await show(tester, 'ae.mission', completed: {'ae.mission'});
    expect(find.text('Mission accomplie'), findsOneWidget);
    expect(find.text("Ouvrir l'Explorer"), findsNothing);
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('a lesson with a bridge ends on « Rejoue-le toi-même »', (
    tester,
  ) async {
    await show(tester, 'ae.apple');
    expect(find.text('Rejoue-le toi-même'), findsNothing);
    await tester.tap(find.text('Apple'));
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rejoue-le toi-même'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'wizard step=1&date=2022-01-03&difficulty=realiste&from=ae.apple',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a lesson without a bridge ends on « Continuer » alone', (
    tester,
  ) async {
    await show(tester, 'ae.fees');
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(Slider).at(i), const Offset(-40, 0));
      await tester.pumpAndSettle();
    }
    expect(find.text('Continuer'), findsOneWidget);
    expect(find.text('Rejoue-le toi-même'), findsNothing);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester, 'ae.mission');
    await expectAccessible(tester);
  });
}
