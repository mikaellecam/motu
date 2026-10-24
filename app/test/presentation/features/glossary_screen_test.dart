import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/glossary.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/clock/simulation_clock.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/glossary/glossary_screen.dart';
import 'package:finance_companion/presentation/features/glossary/term_sheet.dart';
import 'package:finance_companion/presentation/widgets/term_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_glossary.dart';
import '../../fakes/glossary_pack.dart';

import '../../helpers.dart';

const nnbsp = ' ';

class _Fixed implements SimulationClock {
  const _Fixed();
  @override
  DateTime now() => DateTime.utc(2026, 10, 11, 9);
}

final apple = Asset(
  id: 'apple',
  symbol: 'AAPL',
  name: 'Apple',
  type: AssetType.stock,
  exchange: Exchange.nasdaq,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(1980, 12, 12),
);

late FakeGlossary glossary;

Future<void> show(WidgetTester tester, Widget screen) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 3000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  glossary = FakeGlossary(discovered: {'indice'});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => decodePack(glossaryPackJson())),
        glossaryRepositoryProvider.overrideWithValue(glossary),
        // `ae.fees` is done: its term `etf` was met.
        completedNodesProvider.overrideWith((ref) => Stream.value({'ae.fees'})),
        liveClockProvider.overrideWithValue(const _Fixed()),
        liveExampleProvider.overrideWith(
          (ref, args) async => LiveExampleView(
            kind: args.$1,
            asset: apple,
            figure: Decimal.parse('0.2812'),
            closes: [
              (DateTime.utc(2025, 10, 10), Decimal.fromInt(220)),
              (DateTime.utc(2026, 10, 9), Decimal.fromInt(250)),
            ],
          ),
        ),
      ],
      child: MainApp.screen(screen),
    ),
  );
  await tester.pumpAndSettle();
}

/// [finder] inside the open sheet.
Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

void main() {
  testWidgets('the index: by letter, with where each term stands', (
    tester,
  ) async {
    await show(tester, const GlossaryScreen());
    expect(find.text('1 notion découverte sur 6'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1 / 6,
    );
    for (final letter in ['D', 'E', 'I', 'R', 'V']) {
      expect(find.text(letter), findsOneWidget, reason: letter);
    }
    // One flat card per letter, a line between its rows: « Écart » and
    // « ETF » share E's.
    expect(find.byType(Card), findsNWidgets(5));
    final e = find.ancestor(
      of: find.text('Écart'),
      matching: find.byType(Card),
    );
    expect(find.descendant(of: e, matching: find.text('ETF')), findsOneWidget);
    expect(
      find.descendant(of: e, matching: find.byType(Divider)),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Indice, découverte'), findsOneWidget);
    expect(find.bySemanticsLabel('ETF, nouvelle, à ouvrir'), findsOneWidget);
    expect(find.bySemanticsLabel('Écart, à découvrir'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.widgetWithText(NotionBadge, 'Nouvelle'), findsOneWidget);
    // Said in words, not by the absence of a mark: diversification, écart,
    // risque de change, volatilité.
    expect(
      find.descendant(
        of: find.byType(Card),
        matching: find.text('À découvrir'),
      ),
      findsNWidgets(4),
    );

    await tester.enterText(find.byType(TextField), 'ecart');
    await tester.pumpAndSettle();
    expect(find.text('Écart'), findsOneWidget);
    expect(find.text('ETF'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Découvertes'));
    await tester.pumpAndSettle();
    expect(find.text('Indice'), findsOneWidget);
    expect(find.text('ETF'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Aucune notion ne correspond.'), findsOneWidget);
  });

  testWidgets('the sheet: new notion, definition, example, for you, related', (
    tester,
  ) async {
    await show(tester, const GlossaryScreen());
    await tester.tap(find.text('ETF'));
    await tester.pumpAndSettle();
    expect(glossary.opened, ['etf']);
    expect(find.widgetWithText(NotionBadge, 'Nouvelle notion'), findsOneWidget);
    expect(inSheet(find.text('ETF, en une ligne.')), findsOneWidget);
    // The longer definition waits behind « En savoir plus ».
    final body = inSheet(
      find.textContaining('ETF, expliqué.', findRichText: true),
    );
    expect(body, findsNothing);
    await tester.tap(find.text('En savoir plus'));
    await tester.pumpAndSettle();
    expect(body, findsOneWidget);
    expect(find.text('En savoir plus'), findsNothing);
    expect(find.text('Ce que ça change pour toi'), findsOneWidget);
    expect(find.text('Ce que ETF change pour toi.'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Diversification'), findsOneWidget);

    // A related term replaces this sheet.
    await tester.tap(find.widgetWithText(ActionChip, 'Indice'));
    await tester.pumpAndSettle();
    expect(glossary.opened, ['etf', 'indice']);
    expect(inSheet(find.text('Indice, en une ligne.')), findsOneWidget);
    expect(inSheet(find.text('ETF, en une ligne.')), findsNothing);
    expect(
      find.widgetWithText(NotionBadge, 'Nouvelle notion'),
      findsNothing,
      reason: 'already discovered',
    );

    // ✕ closes it.
    await tester.tap(find.bySemanticsLabel('Fermer'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('a live example on real data', (tester) async {
    await show(tester, const GlossaryScreen());
    await tester.tap(find.text('Volatilité'));
    await tester.pumpAndSettle();
    expect(find.text('Sur données réelles'), findsOneWidget);
    expect(
      find.text('Volatilité de Apple sur un an$nnbsp: 28,12$nnbsp%.'),
      findsOneWidget,
    );
  });

  testWidgets('« Tester en 30 secondes »: all right, mastered', (tester) async {
    await show(tester, const GlossaryScreen());
    await tester.tap(find.text('ETF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tester en 30 secondes'));
    await tester.pumpAndSettle();
    expect(find.text('Question 1 sur 2'), findsOneWidget);
    for (final answer in ['Un indice', 'Souvent bas']) {
      await tester.tap(find.text(answer));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining(RegExp('Question suivante|Voir mon résultat')),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Tout juste$nnbsp: notion acquise.'), findsOneWidget);
    expect(glossary.passed, ['etf']);
  });

  testWidgets('a {{term}} link in lesson text opens its sheet', (tester) async {
    await show(
      tester,
      const Scaffold(
        body: TermText(
          'Voir {{indice|l\'indice}}.',
          terms: {'indice': Localized('Indice', 'Index')},
        ),
      ),
    );
    final link = tester.widget<RichText>(find.byType(RichText).first);
    expect(link.text.toPlainText(), "Voir l'indice.");
    await tester.tapOnText(find.textRange.ofSubstring("l'indice"));
    await tester.pumpAndSettle();
    expect(find.text('Indice, en une ligne.'), findsOneWidget);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester, const GlossaryScreen());
    await expectAccessible(tester);

    await tester.tap(find.text('ETF'));
    await tester.pumpAndSettle();
    await expectAccessible(tester);
  });
}
