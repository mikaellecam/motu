import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/explorer/explorer.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/features/explorer/explorer_screen.dart';
import 'package:finance_companion/core/widgets/chunky.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const nnbsp = ' ';
const nbsp = ' ';

ExplorerRow row(
  String id,
  String name,
  AssetType type,
  String region, {
  String? price,
  String? change,
  int? band,
}) => ExplorerRow(
  asset: Asset(
    id: id,
    symbol: id.toUpperCase(),
    name: name,
    type: type,
    exchange: Exchange.nasdaq,
    currency: Currency.usd,
    region: region,
    listingDate: DateTime.utc(2000),
  ),
  price: price == null ? null : Price(Decimal.parse(price), Currency.usd),
  yearChange: change == null ? null : Decimal.parse(change),
  riskBand: band,
);

final catalogue = [
  row(
    'apple',
    'Apple',
    AssetType.stock,
    'us',
    price: '236.4',
    change: '-0.02',
    band: 4,
  ),
  row(
    'world',
    'ETF Monde',
    AssetType.etf,
    'world',
    price: '131.2',
    change: '0.123',
    band: 3,
  ),
  row('hermes', 'Hermès', AssetType.stock, 'europe', price: '48.1'),
  row(
    'nvidia',
    'Nvidia',
    AssetType.stock,
    'us',
    price: '180',
    change: '0.42',
    band: 5,
  ),
];

Future<void> show(WidgetTester tester, List<ExplorerRow> rows) async {
  tester.platformDispatcher.localesTestValue = [const Locale('fr')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
        explorerRowsProvider.overrideWith((ref, walletId) async => rows),
      ],
      child: MainApp.screen(const ExplorerScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drift closes its watch queries on a timer once the tree is gone.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('rows: region, risk, price, 1-year change', (tester) async {
    await show(tester, catalogue);
    expect(find.text('Monde'), findsOneWidget);
    expect(find.text('États-Unis'), findsNWidgets(2));
    expect(find.text('Europe'), findsOneWidget);
    expect(find.text('236,40$nbsp\$'), findsOneWidget);
    expect(find.text('+12,30$nnbsp% sur 1 an'), findsOneWidget);
    expect(find.text('−2,00$nnbsp% sur 1 an'), findsOneWidget);
    // The row reads as one: the meter's label is part of it.
    expect(find.bySemanticsLabel(RegExp('Risque 3 sur 5')), findsOneWidget);
    expect(find.text('pas assez de données'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('ETFs then stocks, each under its title and what it is', (
    tester,
  ) async {
    await show(tester, catalogue);
    Finder inList(String text) => find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.text(text),
    );
    expect(inList("Un panier d'entreprises en un seul achat"), findsOneWidget);
    expect(
      inList(
        'Une seule entreprise$nnbsp: plus de potentiel, plus de secousses',
      ),
      findsOneWidget,
    );
    final tops = [
      for (final text in ['ETF', 'ETF Monde', 'Actions', 'Apple', 'Hermès'])
        tester.getTopLeft(inList(text)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));

    // Filters and search narrow both groups; one left empty is not shown.
    await tester.tap(find.widgetWithText(ChunkyChip, 'Actions'));
    await tester.pumpAndSettle();
    expect(inList('ETF'), findsNothing);
    expect(inList('Actions'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChunkyChip, 'Tout'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'monde');
    await tester.pump();
    expect(inList('ETF'), findsOneWidget);
    expect(inList('Actions'), findsNothing);
    await unmount(tester);
  });

  testWidgets('filter chips are pills', (tester) async {
    await show(tester, catalogue);
    final faces = find.descendant(
      of: find.byType(ChunkyChip),
      matching: find.byType(DecoratedBox),
    );
    expect(faces, findsNWidgets(4));
    for (final face in faces.evaluate()) {
      final decoration = (face.widget as DecoratedBox).decoration;
      final radius =
          (decoration as BoxDecoration).borderRadius! as BorderRadius;
      expect(radius.topLeft.x * 2, face.size!.height);
    }
    await unmount(tester);
  });

  testWidgets('search ignores accents; nothing found says so', (tester) async {
    await show(tester, catalogue);
    await tester.enterText(find.byType(TextField), 'hermes');
    await tester.pump();
    expect(find.text('Hermès'), findsOneWidget);
    expect(find.text('Apple'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(
      find.text('Aucun actif ne correspond à «${nbsp}zzz$nbsp».'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('filters, and favorites that stick', (tester) async {
    await show(tester, catalogue);
    await tester.tap(find.widgetWithText(ChunkyChip, 'ETF'));
    await tester.pumpAndSettle();
    expect(find.text('ETF Monde'), findsOneWidget);
    expect(find.text('Apple'), findsNothing);

    await tester.tap(find.widgetWithText(ChunkyChip, 'Favoris'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Pas encore de favori. Touche l'étoile d'un actif pour le retrouver ici.",
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ChunkyChip, 'Tout'));
    await tester.pumpAndSettle();
    final star = find.descendant(
      of: find.ancestor(of: find.text('Apple'), matching: find.byType(InkWell)),
      matching: find.byTooltip('Ajouter aux favoris'),
    );
    final button = find.ancestor(of: star, matching: find.byType(IconButton));
    expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Retirer des favoris'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChunkyChip, 'Favoris'));
    await tester.pumpAndSettle();
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Nvidia'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a long catalogue builds only the rows on screen', (
    tester,
  ) async {
    final many = [
      for (var i = 0; i < 60; i++)
        row(
          'a$i',
          'Actif ${i.toString().padLeft(2, '0')}',
          AssetType.stock,
          'us',
          price: '10',
        ),
    ];
    await show(tester, many);
    final built = find.textContaining('Actif ').evaluate().length;
    expect(built, lessThan(30));
    await tester.scrollUntilVisible(
      find.text('Actif 59'),
      600,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Actif 59'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester, catalogue);
    await expectAccessible(tester);
    await unmount(tester);
  });
}
