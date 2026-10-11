import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/clock/simulation_clock.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/node/node_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/more_lessons.dart';
import '../../fakes/recording_profiles.dart';

const nnbsp = ' ';
const nbsp = ' ';

class _Fixed implements SimulationClock {
  const _Fixed();
  @override
  DateTime now() => DateTime.utc(2026, 10, 11, 9);
}

late RecordingProfiles profiles;

Future<void> show(WidgetTester tester, String nodeId) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  profiles = RecordingProfiles();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => decodePack(morePackJson())),
        profileRepositoryProvider.overrideWithValue(profiles),
        liveClockProvider.overrideWithValue(const _Fixed()),
      ],
      child: MainApp.screen(NodeScreen(nodeId: nodeId)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('decision: a choice, then what happened to each', (tester) async {
    await show(tester, 'ae.march');
    expect(find.text('Mars 2020 : vendre ou tenir ?'), findsOneWidget);
    expect(
      find.text('Le 20 mars 2020, les marchés ont perdu un tiers en un mois.'),
      findsOneWidget,
    );
    expect(find.text('Que fais-tu$nnbsp?'), findsOneWidget);
    expect(find.text('Si ça remonte : Garder gagne.'), findsOneWidget);
    expect(find.text('Ce qui s\'est passé ensuite'), findsNothing);

    await tap(tester, 'Valider');
    expect(profiles.completed, isEmpty);
    await tap(tester, 'Vendre la moitié');
    await tap(tester, 'Valider');
    expect(profiles.completed, [('ae.march', 'half')]);

    expect(find.text('Ce qui s\'est passé ensuite'), findsOneWidget);
    expect(
      find.text(
        '10${nnbsp}000,00$nbsp\$ au 20 mars 2020, devenus au 26 février 2021$nnbsp:',
      ),
      findsOneWidget,
    );
    expect(find.text('17${nnbsp}000,00$nbsp\$'), findsOneWidget);
    expect(find.text('Vendre la moitié (ton choix)'), findsOneWidget);
    expect(find.text('+35,00$nnbsp%'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('+35,00$nnbsp%')).style?.color,
      AppColors.gain,
    );
    expect(
      find.text('Le marché a tout repris en quelques mois.'),
      findsOneWidget,
    );
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('sort: drag into place, then the real order', (tester) async {
    await show(tester, 'ae.ladder');
    expect(find.text('Moins risqué'), findsOneWidget);
    expect(find.text('Plus risqué'), findsOneWidget);
    expect(find.text('Fais glisser pour ranger.'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == 'Déplacer'),
      findsNWidgets(3),
    );

    // « Action seule » from the top to the bottom.
    final handle = find.byIcon(Icons.drag_handle).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 400));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tap(tester, 'Valider');
    expect(profiles.completed.single.$1, 'ae.ladder');
    expect(find.text('3 sur 3 à la bonne place'), findsOneWidget);
    expect(find.text("L'ordre réel, par volatilité"), findsOneWidget);
    expect(find.text('0,00$nnbsp%'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('build_puzzle: rules checked live, Valider once all hold', (
    tester,
  ) async {
    await show(tester, 'ae.calm');
    expect(find.byType(Slider), findsNWidgets(3));
    expect(find.text('Total$nnbsp: 0$nnbsp%'), findsOneWidget);
    expect(
      find.text('Volatilité du portefeuille$nnbsp: donne une part à un actif.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Volatilité sous 5$nnbsp%, pas encore respectée'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Au moins 2 actifs, pas encore respectée'),
      findsOneWidget,
    );

    // 50 % in each of the two series that move against each other.
    for (final i in [0, 1]) {
      final slider = find.byType(Slider).at(i);
      await tester.tapAt(tester.getCenter(slider));
      await tester.pumpAndSettle();
    }
    expect(find.text('Total$nnbsp: 100$nnbsp%'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Volatilité sous 5$nnbsp%, respectée'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Au moins 2 zones géographiques, respectée'),
      findsOneWidget,
    );

    await tap(tester, 'Valider');
    expect(profiles.completed.single.$1, 'ae.calm');
    expect(find.text('Toutes les règles sont respectées.'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('checkpoint: one question at a time, then the score', (
    tester,
  ) async {
    await show(tester, 'ae.quiz');
    expect(find.text('Question 1 sur 2'), findsOneWidget);
    await tap(tester, 'Une seule entreprise');
    await tap(tester, 'Valider');
    expect(
      find.text("Pas cette fois$nnbsp: c'était Des milliers d'entreprises."),
      findsOneWidget,
    );
    expect(
      find.text("Il suit un indice de milliers d'entreprises."),
      findsOneWidget,
    );

    await tap(tester, 'Question suivante');
    expect(find.text('Question 2 sur 2'), findsOneWidget);
    await tap(tester, 'Oui');
    await tap(tester, 'Valider');
    expect(find.text('Bien vu$nnbsp!'), findsOneWidget);

    await tap(tester, 'Voir mon résultat');
    expect(find.text('1 sur 2'), findsOneWidget);
    expect(find.text("Point d'étape terminé."), findsOneWidget);
    expect(profiles.completed, [('ae.quiz', '1/2')]);
  });
}
