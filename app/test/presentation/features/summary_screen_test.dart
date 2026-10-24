import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/trip/trip_summary.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/wallet/trip_summary.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/trip/summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';

const nnbsp = '\u202f';
const nbsp = '\u00a0';

DateTime day(int m, int d) => DateTime.utc(2020, m, d);
Decimal dec(String s) => Decimal.parse(s);

const _l = Localized('x', 'x');

TripSummary summary({
  List<ReplayLine> journal = const [],
  bool capped = false,
  bool worst = true,
}) => TripSummary(
  name: 'Covid',
  start: day(2, 18),
  end: day(12, 31),
  moneyIn: const Money(1200000, Currency.eur),
  outcomes: [
    OutcomeRow(Outcome.you, value: dec('12850.4'), twr: dec('0.0712')),
    OutcomeRow(Outcome.world, value: dec('13410'), twr: dec('0.1175')),
    OutcomeRow(Outcome.livret, value: dec('12060.5'), twr: dec('0.005')),
    if (worst)
      OutcomeRow(
        Outcome.worst,
        value: dec('10180'),
        twr: dec('-0.1683'),
        date: day(3, 16),
      ),
  ],
  livretCapped: capped,
  journal: journal,
  terms: const [
    GlossaryTerm(
      id: 'pire-baisse',
      title: Localized('Pire baisse', 'Maximum drawdown'),
      short: _l,
      body: _l,
    ),
  ],
);

Future<void> show(WidgetTester tester, TripSummary s) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tripSummaryProvider.overrideWith((ref, id) async => s),
        // The island over it: no city, no lessons.
        walletIslandProvider.overrideWith((ref, id) async => const []),
        islandPathProvider(actionsEtfIsland)
            .overrideWith((ref) async => const IslandPathView(_l, [])),
      ],
      child: MainApp(
        router: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const TripSummaryScreen(walletId: 'trip'),
            ),
            // Where the buttons lead, as the address they were sent to.
            GoRoute(
              path: '/wallets/new',
              builder: (_, state) => Text('wizard ${state.uri.query}'),
            ),
            GoRoute(path: '/wallets', builder: (_, _) => const Text('wallets')),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color? colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  testWidgets('the trip against the same money elsewhere', (tester) async {
    await show(tester, summary());
    expect(find.text('Fin du voyage «${nbsp}Covid$nbsp»'), findsOneWidget);
    expect(find.text('Du 18 février 2020 au 31 décembre 2020'), findsOneWidget);
    expect(
      find.text('Argent versé$nnbsp: 12${nnbsp}000,00$nbsp€'),
      findsOneWidget,
    );

    for (final label in [
      'Ton voyage',
      'Sans rien toucher',
      'Sur un Livret A',
      'Ta pire décision',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Si tu avais tout vendu le 16 mars 2020'), findsOneWidget);
    expect(find.text('Au taux de chaque époque'), findsOneWidget);
    expect(find.text('12${nnbsp}850,40$nbsp€'), findsOneWidget);
    expect(find.text('+7,12$nnbsp%'), findsOneWidget);
    expect(colorOf(tester, '+7,12$nnbsp%'), AppColors.gain);
    expect(find.text('−16,83$nnbsp%'), findsOneWidget);
    expect(colorOf(tester, '−16,83$nnbsp%'), AppColors.loss);

    expect(find.widgetWithText(ActionChip, 'Pire baisse'), findsOneWidget);
    expect(
      find.text('Aucune décision notée pendant ce voyage.'),
      findsOneWidget,
    );
  });

  testWidgets('no sell, a capped Livret', (tester) async {
    await show(tester, summary(worst: false, capped: true));
    expect(find.text('Ta pire décision'), findsNothing);
    expect(
      find.text('Plafond atteint$nnbsp: le surplus est resté en liquidités'),
      findsOneWidget,
    );
  });

  testWidgets('the journal replayed with what happened next', (tester) async {
    await show(
      tester,
      summary(
        journal: [
          ReplayLine(
            JournalEntry(
              date: day(3, 16),
              decision: 'sell_half',
              reason: 'Trop de stress',
            ),
            sold: const ['Apple', 'LVMH'],
            moved: dec('0.61'),
          ),
          ReplayLine(
            JournalEntry(date: day(4, 1), decision: 'hold'),
            moved: dec('-0.02'),
          ),
          ReplayLine(JournalEntry(date: day(12, 30), decision: 'sell_all')),
          ReplayLine(JournalEntry(date: day(5, 4), decision: 'continue')),
          ReplayLine(
            JournalEntry(
              date: day(6, 1),
              decision: 'buy',
              eventId: 'o-1',
              reason: 'Les prix ont baissé',
            ),
            sold: const ['ETF Monde'],
            moved: dec('0.12'),
          ),
          ReplayLine(
            JournalEntry(date: day(12, 1), decision: 'sell', eventId: 'o-2'),
          ),
        ],
      ),
    );
    expect(find.text('Le 16 mars 2020'), findsOneWidget);
    expect(
      find.text('Tu as vendu la moitié$nnbsp: Apple, LVMH.'),
      findsOneWidget,
    );
    expect(find.text('«${nbsp}Trop de stress$nbsp»'), findsOneWidget);
    expect(
      find.text('Depuis, ces parts ont fait +61,00$nnbsp%.'),
      findsOneWidget,
    );

    expect(find.text('Tu as gardé tes positions.'), findsOneWidget);
    final held =
        'Depuis, ton portefeuille a fait −2,00$nnbsp%, versements mis à part.';
    expect(find.text(held), findsOneWidget);
    expect(colorOf(tester, held), AppColors.loss);

    // A sell placed on the last day never filled.
    expect(find.text('Tu as choisi de tout vendre.'), findsOneWidget);
    expect(find.text('Tu as continué le voyage.'), findsOneWidget);
    // Trip orders noted in the journal.
    expect(find.text('Tu as acheté ETF Monde.'), findsOneWidget);
    expect(
      find.text('Depuis, ces parts ont fait +12,00$nnbsp%.'),
      findsOneWidget,
    );
    expect(
      find.text("Ton ordre de vente n'a pas été exécuté avant la fin."),
      findsOneWidget,
    );
    expect(find.text('Aucune décision notée pendant ce voyage.'), findsNothing);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester, summary());
    await expectAccessible(tester);
  });

  testWidgets('play again: the wizard at its difficulty step, same start', (
    tester,
  ) async {
    await show(tester, summary());
    final again = find.text('Rejouer avec une autre difficulté');
    // Built below the fold: brought on screen before the tap.
    await tester.scrollUntilVisible(again, 200);
    await tester.ensureVisible(again);
    await tester.pumpAndSettle();
    await tester.tap(again);
    await tester.pumpAndSettle();
    expect(find.text('wizard step=2&date=2020-02-18'), findsOneWidget);
  });

  testWidgets('or back to the wallets', (tester) async {
    await show(tester, summary());
    final back = find.text('Retour à mes portefeuilles');
    // Built below the fold: brought on screen before the tap.
    await tester.scrollUntilVisible(back, 200);
    await tester.ensureVisible(back);
    await tester.pumpAndSettle();
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('wallets'), findsOneWidget);
  });
}
