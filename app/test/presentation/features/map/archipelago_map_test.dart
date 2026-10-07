import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:finance_companion/presentation/features/map/archipelago_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers.dart';

void main() {
  Future<List<IslandId>> pumpMap(WidgetTester tester) async {
    final opened = <IslandId>[];
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, ArchipelagoMap(onOpen: opened.add));
    return opened;
  }

  testWidgets('five labelled islands, four of them coming soon', (
    tester,
  ) async {
    await pumpMap(tester);
    for (final name in [
      'Actions & ETF',
      'Trading',
      'Immobilier',
      'Crypto',
      'Les bases',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Bientôt'), findsNWidgets(4));
  });

  testWidgets('Actions & ETF opens; locked islands do nothing', (tester) async {
    final opened = await pumpMap(tester);
    await tester.tap(find.text('Actions & ETF'));
    await tester.tap(find.text('Trading'), warnIfMissed: false);
    expect(opened, [IslandId.actionsEtf]);
  });

  testWidgets('screen readers hear each island, and which ones are not open', (
    tester,
  ) async {
    await pumpMap(tester);
    expect(find.bySemanticsLabel('Actions & ETF'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Actions & ETF')),
      matchesSemantics(
        label: 'Actions & ETF',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Trading, bientôt')),
      matchesSemantics(label: 'Trading, bientôt'),
    );
  });

  testWidgets('labels are comfortable tap targets', (tester) async {
    await pumpMap(tester);
    // Measured on screen, at the opening zoom: the smallest the map allows.
    for (final name in ['Actions & ETF', 'Trading']) {
      final target = find
          .ancestor(of: find.text(name), matching: find.byType(GestureDetector))
          .first;
      expect(
        tester.getRect(target).height,
        greaterThanOrEqualTo(44),
        reason: name,
      );
    }
  });

  testWidgets('pan and zoom within bounds', (tester) async {
    await pumpMap(tester);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.minScale, 0.75);
    expect(viewer.maxScale, 2.5);
    expect(viewer.panEnabled, isTrue);
    expect(viewer.scaleEnabled, isTrue);
  });
}
