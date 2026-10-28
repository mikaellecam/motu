import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/node_player.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/clock/simulation_clock.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/node/node_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/bases_toys.dart';
import '../../fakes/lesson_pack.dart';
import '../../fakes/recording_profiles.dart';

import '../../helpers.dart';

const nnbsp = ' ';
const nbsp = ' ';

class _Fixed implements SimulationClock {
  const _Fixed();
  @override
  DateTime now() => DateTime.utc(2026, 10, 8, 12);
}

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

late RecordingProfiles profiles;

Future<void> show(
  WidgetTester tester,
  String nodeId, {
  CacheStatus status = const Fresh(),
}) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 5400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  profiles = RecordingProfiles();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => decodePack(packJson())),
        // Les bases' toys beside the lesson pack (M12-3).
        contentPacksProvider.overrideWith(
          (ref) async => [
            await ref.watch(contentPackProvider(actionsEtfIsland).future),
            decodePack(basesToysJson()),
          ],
        ),
        cacheStatusProvider.overrideWith((ref) => Stream.value(status)),
        profileRepositoryProvider.overrideWithValue(profiles),
        liveClockProvider.overrideWithValue(const _Fixed()),
        liveRevealProvider.overrideWith(
          (ref, id) async => LiveCurves(day(2025, 10, 8), day(2026, 10, 7), [
            LessonCurve(
              label: const Localized('Apple', 'Apple'),
              currency: 'USD',
              points: [
                (day(2025, 10, 8), Decimal.fromInt(1000)),
                (day(2026, 10, 7), Decimal.fromInt(1250)),
              ],
            ),
          ]),
        ),
      ],
      child: MainApp.screen(NodeScreen(nodeId: nodeId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('predict_reveal: an answer, then the curves and why', (
    tester,
  ) async {
    await show(tester, 'ae.apple');
    expect(find.text('Apple ou ETF Monde ?'), findsOneWidget);
    expect(find.text('Lequel a le plus chuté ?'), findsOneWidget);
    expect(find.text('ETF Monde'), findsOneWidget);
    expect(find.text('Bien vu$nnbsp!'), findsNothing);

    // Nothing to check before a choice.
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(profiles.completed, isEmpty);

    await tester.tap(find.text('ETF Monde'));
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(profiles.completed, [('ae.apple', 'world')]);
    // The verdict takes the question's place.
    expect(find.text("Raté, et c'est comme ça qu'on apprend"), findsOneWidget);
    expect(
      find.text(
        'Tu as répondu «${nbsp}ETF Monde$nbsp». La bonne '
        'réponse$nnbsp: «${nbsp}Apple$nbsp».',
      ),
      findsOneWidget,
    );
    expect(find.text('Lequel a le plus chuté ?'), findsNothing);
    expect(find.text('Pourquoi$nnbsp?'), findsOneWidget);

    // The curves drew in: each line's end, signed.
    expect(find.text('754,66$nbsp\$'), findsOneWidget);
    expect(find.text('−24,53$nnbsp%'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('−24,53$nnbsp%')).style?.color,
      AppColors.loss,
    );
    expect(find.text('820,00$nbsp\$'), findsOneWidget);
    expect(
      find.text('Avec 1${nnbsp}000,00$nbsp\$ placés au départ.'),
      findsOneWidget,
    );
    expect(
      find.text('Cours réels, clôtures hebdomadaires, 2022, en dollars.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^Courbes$nnbsp: Apple de 1${nnbsp}000,00')),
      findsOneWidget,
    );
    // The term link reads as the term's title.
    expect(
      find.text(
        'Une seule entreprise : pas de diversification, '
        'la Diversification se voit sur la durée.',
        findRichText: true,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text("Et aujourd'hui$nnbsp?"));
    await tester.pumpAndSettle();
    expect(
      find.text('Cours actuels, du 8 octobre 2025 au 7 octobre 2026.'),
      findsOneWidget,
    );
    expect(find.text('1${nnbsp}250,00$nbsp\$'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('offline: no « Et aujourd\'hui ? »', (tester) async {
    await show(tester, 'ae.apple', status: const Offline(null));
    await tester.tap(find.text('Apple'));
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Bien vu$nnbsp!'), findsOneWidget);
    expect(find.text("Et aujourd'hui$nnbsp?"), findsNothing);
  });

  testWidgets('toy: the past return, sliders, done once each one moved', (
    tester,
  ) async {
    await show(tester, 'ae.fees');
    expect(find.text('Le jouet des frais'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(5));
    expect(
      find.text(
        "+7,18$nnbsp% par an$nnbsp: ce qu'a fait l'ETF Monde de 2010 à 2020.",
      ),
      findsOneWidget,
    );
    expect(find.text('Frais de 0,20$nnbsp% par an'), findsOneWidget);
    expect(
      find.textContaining("Au bout de 30 ans, l'écart atteint"),
      findsOneWidget,
    );
    expect(find.text('Bouge chaque curseur pour terminer.'), findsOneWidget);
    expect(find.text('Continuer'), findsNothing);

    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(Slider).at(i), const Offset(-40, 0));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('Hypothèse$nnbsp:'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
    expect(profiles.completed, [('ae.fees', null)]);
  });

  testWidgets('toy: the loan, its payment, what it costs, when it is back', (
    tester,
  ) async {
    await show(tester, 'lb.loan-cost');
    expect(find.byType(Slider), findsNWidgets(3));
    expect(
      find.textContaining('Le crédit coûte 1${nnbsp}013,68'),
      findsOneWidget,
    );
    expect(find.text('Chaque mois'), findsOneWidget);
    expect(find.textContaining('111,49'), findsOneWidget);
    expect(find.textContaining('Au bout de 27 mois'), findsOneWidget);
    expect(find.text('36 mois'), findsOneWidget);
    expect(find.textContaining('Hypothèse'), findsNothing);

    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(Slider).at(i), const Offset(-40, 0));
      await tester.pumpAndSettle();
    }
    expect(find.text('Continuer'), findsOneWidget);
    expect(profiles.completed, [('lb.loan-cost', null)]);
  });

  testWidgets('toy: the cushion fills in so many months, or never', (
    tester,
  ) async {
    await show(tester, 'lb.safety-cushion');
    // 4 500 € at 200 € a month: 22,5, full in the 23rd.
    expect(find.textContaining('est plein en 23 mois'), findsOneWidget);
    expect(find.text('Ton matelas'), findsOneWidget);
    await tester.drag(find.byType(Slider).at(2), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Sans rien mettre de côté chaque mois, le matelas ne se remplit pas.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('quiz: a checkpoint\'s questions, under its own name', (
    tester,
  ) async {
    await show(tester, 'lb.spot-the-scam');
    expect(find.text("Repère l'arnaque"), findsOneWidget);
    await tester.tap(find.text('Une arnaque'));
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voir mon résultat'));
    await tester.pumpAndSettle();
    expect(find.text('Quiz'), findsOneWidget);
    expect(profiles.completed.single.$1, 'lb.spot-the-scam');
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester, 'ae.apple');
    await expectAccessible(tester);
  });
}
