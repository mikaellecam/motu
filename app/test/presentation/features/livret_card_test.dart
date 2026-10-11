import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/livret_line.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/wallet/livret_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const nnbsp = ' ';
const nbsp = ' ';

Money eur(String s) => Money.book(Decimal.parse(s), Currency.eur);

LivretLine line({String balance = '0', String accrued = '0'}) => LivretLine(
  day: DateTime.utc(2026, 10, 8),
  balance: eur(balance),
  accrued: Decimal.parse(accrued),
  rate: Decimal.parse('0.017'),
  ceiling: eur('22950'),
  availableCash: eur('50000'),
);

late AppDatabase db;

Future<void> show(
  WidgetTester tester,
  LivretLine l, {
  bool canMove = true,
}) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await WalletRepository(db).ensureLiveWallet(DateTime.utc(2026, 10, 5));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        livretLineProvider.overrideWith((ref, id) async => l),
      ],
      child: MainApp.screen(
        Scaffold(
          body: LivretCard(walletId: 'live', canMove: canMove),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the balance, this year\'s interest, the rate and the ceiling', (
    tester,
  ) async {
    await show(tester, line(balance: '1000', accrued: '0.708333'));
    expect(find.text('Livret A'), findsOneWidget);
    expect(find.text('1${nnbsp}000,00$nbsp€'), findsOneWidget);
    expect(
      find.text(
        "Intérêts de l'année$nnbsp: +0,71$nbsp€, versés le 31 décembre",
      ),
      findsOneWidget,
    );
    expect(
      find.text('1,70$nnbsp% par an · plafond 22${nnbsp}950,00$nbsp€'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Retirer'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('nothing on it: nothing to withdraw', (tester) async {
    await show(tester, line());
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Retirer'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a finished trip only shows its Livret', (tester) async {
    await show(tester, line(balance: '1000'), canMove: false);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('« Verser »: the bounds in words, then the deposit booked', (
    tester,
  ) async {
    await show(tester, line());
    await tester.tap(find.widgetWithText(OutlinedButton, 'Verser'));
    await tester.pumpAndSettle();
    expect(find.text('Verser sur le Livret A'), findsOneWidget);
    expect(
      find.text('Liquidités disponibles$nnbsp: 50${nnbsp}000,00$nbsp€'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '30000');
    await tester.pump();
    // Crossed, the bound becomes the error, said once.
    expect(
      find.text(
        'Le plafond est de 22${nnbsp}950,00$nbsp€$nnbsp: tu peux encore '
        'verser 22${nnbsp}950,00$nbsp€.',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '1000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Verser'));
    await tester.pumpAndSettle();
    expect(find.text('Verser sur le Livret A'), findsNothing);
    expect(
      find.text('1${nnbsp}000,00$nbsp€ versés sur ton Livret A.'),
      findsOneWidget,
    );
    final moved = (await WalletRepository(db).load('live')).livretMovements;
    expect(moved.single.amount, eur('1000'));
  });
}
