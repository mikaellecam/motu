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
