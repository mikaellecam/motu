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
    (
      'ChunkyChip',
      ChunkyChip(label: '500 €', onTap: () {}),
      AppShape.chunkySmallShadow,
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

  testWidgets(
    'ChunkySegmented picks one segment; each meets the 44 px target',
    (tester) async {
      String? picked;
      for (final compact in [false, true]) {
        await pumpApp(
          tester,
          Center(
            child: ChunkySegmented(
              segments: const [('week', '1S'), ('year', '1A')],
              selected: 'year',
              onChanged: (value) => picked = value,
              compact: compact,
            ),
          ),
        );
        await tester.tap(find.text('1S'));
        expect(picked, 'week');

        for (final (label, selected) in [('1S', false), ('1A', true)]) {
          final segment = find.ancestor(
            of: find.text(label),
            matching: find.byType(GestureDetector),
          );
          final size = tester.getSize(segment.first);
          expect(size.height, greaterThanOrEqualTo(44));
          expect(size.width, greaterThanOrEqualTo(44));
          expect(
            tester.getSemantics(find.text(label)),
            matchesSemantics(
              label: label,
              isButton: true,
              hasSelectedState: true,
              isSelected: selected,
              isInMutuallyExclusiveGroup: true,
              hasTapAction: true,
            ),
          );
        }
      }
    },
  );

  testWidgets('ChunkyChip says whether its filter is on', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      Center(
        child: ChunkyChip(label: 'ETF', selected: true, onTap: () => taps++),
      ),
    );
    await tester.tap(find.byType(ChunkyChip));
    await tester.pumpAndSettle();
    expect(taps, 1);
    final size = tester.getSize(find.byType(ChunkyChip));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(find.byType(ChunkyChip)),
      matchesSemantics(
        label: 'ETF',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('ChunkySearchField reports what is typed, and clears', (
    tester,
  ) async {
    final typed = <String>[];
    var cleared = 0;
    await pumpApp(
      tester,
      ChunkySearchField(
        hint: 'Rechercher',
        onChanged: typed.add,
        onClear: () => cleared++,
      ),
    );
    await tester.enterText(find.byType(TextField), 'apple');
    expect(typed, ['apple']);
    await tester.tap(find.byIcon(Icons.close));
    expect(cleared, 1);
  });

  testWidgets('ChunkyBackButton shows only where it can go back', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  leading: ChunkyBackButton.leadingOf(context),
                  leadingWidth: ChunkyBackButton.width,
                  title: const Text('Apple'),
                ),
              ),
            ),
          ),
          child: Builder(
            builder: (context) =>
                Text(ChunkyBackButton.leadingOf(context) == null ? 'root' : ''),
          ),
        ),
      ),
    );
    expect(find.text('root'), findsOneWidget);

    await tester.tap(find.text('root'));
    await tester.pumpAndSettle();
    expect(find.byType(ChunkyBackButton), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.byType(ChunkyBackButton));
    await tester.pumpAndSettle();
    expect(find.text('Apple'), findsNothing);
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
