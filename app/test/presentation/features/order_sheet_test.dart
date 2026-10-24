import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/learning/glossary.dart';
import 'package:finance_companion/application/order/order_ticket.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/clock/simulation_clock.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/glossary/term_sheet.dart';
import 'package:finance_companion/presentation/features/order/order_sheet.dart';
import 'package:finance_companion/presentation/widgets/term_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const nnbsp = ' ';
const nbsp = ' ';

Decimal d(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(d(s), Currency.eur);

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

TicketContext context({
  bool trip = false,
  String held = '0',
  bool offline = false,
}) => TicketContext(
  asset: apple,
  walletId: trip ? 'trip' : 'live',
  isTrip: trip,
  finished: false,
  rules: TradingRules(
    fxFeeRate: d('0.0015'),
    fixedFee: const Money.zero(Currency.eur),
    fractionalShares: true,
  ),
  price: Price(d('102'), Currency.usd),
  fxRate: d('0.8547'),
  availableCash: eur('50000'),
  availableQuantity: Quantity.truncate(d(held)),
  positionValue: d(held) * d('87.1794'),
  walletTotal: d('50000') + d(held) * d('87.1794'),
  threshold: d('0.40'),
  asOf: DateTime.utc(2026, 10, 8, 12),
  // Offline, open now: the next session opens at 15 h 30, Paris time.
  marketOpen: offline,
  offline: offline,
  // Opens at 15 h 30, Paris time.
  nextOpen: trip ? null : DateTime.utc(2026, 10, 8, 13, 30),
);

/// The real rules on a fixed context; placing only records.
class FakeTicket extends OrderTicket {
  FakeTicket(this.fixed, {this.gate});
  final TicketContext fixed;
  final String? gate;
  final placed = <Order>[];

  @override
  Future<TicketState> build(String assetId, String walletId, Side side) async =>
      ticketState(fixed, TicketForm(side: side), orderId: 'o');

  @override
  Future<String?> setType(OrderType type) async {
    // The form changes at once; the gate's own lookup is not needed here.
    super.setType(type).ignore();
    return type == OrderType.limit ? gate : null;
  }

  @override
  Future<OrderOutcome?> submit() async {
    final s = state.value!;
    final submitted = ticketState(
      fixed,
      s.form.copyWith(submitted: true),
      orderId: 'o',
    );
    state = AsyncData(submitted);
    if (!submitted.canSubmit) return null;
    placed.add(submitted.order!);
    return OrderSent('o', opensAt: fixed.nextOpen, trip: fixed.isTrip);
  }
}

class _Fixed implements SimulationClock {
  const _Fixed();
  @override
  DateTime now() => DateTime.utc(2026, 10, 8, 12);
}

late FakeTicket ticket;
({String message, String orderId})? result;

Future<void> show(
  WidgetTester tester, {
  Side side = Side.buy,
  bool trip = false,
  String held = '0',
  String? gate,
  bool offline = false,
}) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1170, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  ticket = FakeTicket(
    context(trip: trip, held: held, offline: offline),
    gate: gate,
  );
  result = null;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderTicketProvider.overrideWith2((_) => ticket),
        // The coach's glossary link: no pack to download.
        contentPackProvider(actionsEtfIsland).overrideWith(
          (ref) async => const ContentPack(
            id: 'actions-etf',
            version: 1,
            title: Localized('Actions & ETF', 'Stocks & ETFs'),
            nodes: [],
            datasets: {},
            glossary: {},
          ),
        ),
        liveClockProvider.overrideWithValue(const _Fixed()),
        termSheetProvider.overrideWith(
          (ref, id) async => TermSheetView(
            term: GlossaryTerm(
              id: id,
              title: const Localized('Ordre à cours limité', 'Limit order'),
              short: const Localized('x', 'x'),
              body: const Localized('x', 'x'),
            ),
            related: const [],
            firstOpen: true,
            terms: const {},
          ),
        ),
      ],
      child: MainApp.screen(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await showOrderSheet(
                  context,
                  assetId: 'apple',
                  walletId: trip ? 'trip' : 'live',
                  side: side,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  testWidgets('a buy: priced, weighed, with when it will go', (tester) async {
    await show(tester);
    expect(find.text('Acheter Apple'), findsOneWidget);
    expect(find.text('Au marché'), findsOneWidget);
    await tester.enterText(field('Montant en euros'), '8 717,94');
    await tester.pumpAndSettle();
    for (final (label, value) in [
      ('Parts', '100'),
      ('Valeur', '8${nnbsp}717,94$nbsp€'),
      ('Frais', '13,08$nbsp€'),
      ('Total à payer', '8${nnbsp}731,02$nbsp€'),
    ]) {
      // In the summary: the mode toggle says « Parts » too.
      final summary = find.byType(Card);
      expect(
        find.descendant(of: summary, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
      expect(find.text(value), findsOneWidget, reason: label);
    }
    expect(
      find.text(
        'Apple pèserait 17$nnbsp% de ton portefeuille, contre 0$nnbsp% aujourd\'hui.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Le Nasdaq est fermé.'), findsOneWidget);
    expect(find.textContaining('h${nbsp}30'), findsOneWidget);

    // The button names what it buys.
    await tester.tap(
      find.widgetWithText(FilledButton, 'Acheter pour 8${nnbsp}717,94$nbsp€'),
    );
    await tester.pumpAndSettle();
    expect(ticket.placed.single.size, isA<AmountSize>());
    expect(result!.message, contains('Ordre envoyé'));
    expect(result!.orderId, 'o');
  });

  testWidgets('offline, market open: it goes at the next opening', (
    tester,
  ) async {
    await show(tester, offline: true);
    expect(find.textContaining('est fermé'), findsNothing);
    expect(
      find.textContaining(
        'Pas de cours à jour$nnbsp: ton ordre partira à la prochaine ouverture',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('h${nbsp}30'), findsOneWidget);
  });

  testWidgets('every error in words; the coach flags a heavy line', (
    tester,
  ) async {
    await show(tester);
    // Valider first: every problem shows.
    await tester.tap(find.widgetWithText(FilledButton, 'Acheter'));
    await tester.pumpAndSettle();
    expect(find.text('Saisis un montant supérieur à zéro.'), findsOneWidget);
    expect(ticket.placed, isEmpty);

    await tester.enterText(field('Montant en euros'), '60000');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Tu as 50${nnbsp}000,00$nbsp€ de liquidités. Baisse le montant, ou vends d\'abord une position.',
      ),
      findsOneWidget,
    );

    await tester.enterText(field('Montant en euros'), '30000');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Au-delà de 40', findRichText: true),
      findsOneWidget,
    );
    expect(
      tester.widget<TermText>(find.byType(TermText)).style?.color,
      AppColors.alertText,
    );
  });

  testWidgets('chips: an amount, Max, shares', (tester) async {
    await show(tester);
    await tester.tap(find.text('500$nbsp€'));
    await tester.pumpAndSettle();
    expect(find.text('500'), findsOneWidget, reason: 'the field follows');
    await tester.tap(find.text('Max'));
    await tester.pumpAndSettle();
    expect(find.text('Total à payer'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<SizeMode>),
        matching: find.text('Parts'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 parts'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Card), matching: find.text('Parts')),
      findsOneWidget,
    );
    expect(find.text('5'), findsWidgets);
  });

  testWidgets('a limit: the first time, its glossary sheet; then its price', (
    tester,
  ) async {
    await show(tester, gate: 'ordre-limite');
    await tester.tap(find.text('À cours limité'));
    await tester.pumpAndSettle();
    expect(find.byType(TermSheet), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(field('Cours limite (USD)'), findsOneWidget);
    expect(
      find.text('Achat dès que le cours descend à ce prix ou moins.'),
      findsOneWidget,
    );
    expect(find.text("Valable jusqu'à annulation."), findsOneWidget);
  });

  testWidgets('a sell: half or all of what can be sold', (tester) async {
    await show(tester, side: Side.sell, held: '6');
    expect(find.text('Vendre Apple'), findsOneWidget);
    await tester.tap(find.text('La moitié'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsWidgets);
    expect(find.text('Tu reçois'), findsOneWidget);
    await tester.tap(find.text('Tout'));
    await tester.pumpAndSettle();
    expect(find.text('6'), findsWidgets);
  });

  testWidgets('in a trip: the next trading day, and a reason for the journal', (
    tester,
  ) async {
    await show(tester, trip: true);
    expect(
      find.text('Ton ordre partira au prochain jour de cotation du voyage.'),
      findsOneWidget,
    );
    expect(
      field('Pourquoi$nnbsp? (facultatif, noté dans ton journal)'),
      findsOneWidget,
    );
    await tester.enterText(field('Montant en euros'), '500');
    await tester.pumpAndSettle();
    final reason = field('Pourquoi$nnbsp? (facultatif, noté dans ton journal)');
    await tester.ensureVisible(reason);
    await tester.enterText(reason, 'Pour voir');
    await tester.pumpAndSettle();
    expect(ticket.state.value!.form.reason, 'Pour voir');
    // A limit price coming and going above it leaves the reason typed.
    for (final type in ['À cours limité', 'Au marché']) {
      await tester.tap(find.text(type));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Pour voir'), findsOneWidget);
    }
    await tester.tap(
      find.widgetWithText(FilledButton, 'Acheter pour 500,00$nbsp€'),
    );
    await tester.pumpAndSettle();
    expect(
      result!.message,
      'Ordre envoyé$nnbsp: il partira au prochain jour de cotation du voyage.',
    );
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester);
    await expectAccessible(tester);
  });
}
