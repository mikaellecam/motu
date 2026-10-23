import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/core/widgets/chunky.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  testWidgets('ChunkyButton taps, and meets the 44 px target', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      Center(
        child: ChunkyButton(label: 'Réessayer', onPressed: () => taps++),
      ),
    );
    await tester.tap(find.byType(ChunkyButton));
    await tester.pumpAndSettle();
    expect(taps, 1);

    // Shrink-wrapped in a Center, yet still a comfortable target.
    final size = tester.getSize(find.byType(ChunkyButton));
    expect(size.height, inInclusiveRange(44, 80));
    expect(size.width, inInclusiveRange(44, 400));
    expect(
      tester.getSemantics(find.byType(ChunkyButton)),
      matchesSemantics(
        label: 'Réessayer',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: false,
      ),
    );
  });

  // tester.tap reports down and up in the same frame, like a quick tap in a
  // scroll view: the press must still play in full.
  for (final (name, block, depth) in [
    (
      'ChunkyButton',
      ChunkyButton(label: 'Réessayer', onPressed: () {}),
      AppShape.chunkyButtonShadow,
    ),
    (
      'ChunkyChoice',
      ChunkyChoice(label: 'Long terme', selected: false, onTap: () {}),
      AppShape.chunkyCardShadow,
    ),
  ]) {
    testWidgets('a quick tap sinks a $name onto its shadow', (tester) async {
      await pumpApp(tester, Center(child: block));
      final face = find
          .descendant(
            of: find.byWidget(block),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final rest = tester.getRect(face).top;

      await tester.tap(find.byWidget(block));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(face).top, rest + depth);

      await tester.pumpAndSettle();
      expect(tester.getRect(face).top, rest);
    });
  }

  testWidgets('a disabled ChunkyButton ignores taps', (tester) async {
    await pumpApp(
      tester,
      const Center(child: ChunkyButton(label: 'Réessayer', onPressed: null)),
    );
    await tester.tap(find.byType(ChunkyButton));
    await tester.pump();
    expect(
      tester.getSemantics(find.byType(ChunkyButton)),
      matchesSemantics(
        label: 'Réessayer',
        isButton: true,
        hasEnabledState: true,
      ),
    );
  });
}
