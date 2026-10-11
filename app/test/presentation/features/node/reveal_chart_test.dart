import 'package:decimal/decimal.dart';
import 'package:finance_companion/presentation/features/node/reveal_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);

/// [child] on a bare screen, animations off when [still].
Future<void> pump(WidgetTester tester, Widget child, {bool still = false}) =>
    tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Material(child: child),
        ),
      ),
    );

double progress(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<LinesPainter>()
    .single
    .progress;

String shown(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: find.byType(CountUp), matching: find.byType(Text)),
    )
    .data!;

void main() {
  const chart = RevealChart(
    lines: [
      ChartLine([(0, 100), (1, 80), (2, 130)], Colors.blue),
    ],
    semanticsLabel: 'Apple',
  );

  group('the curve draws itself along its length', () {
    testWidgets('from nothing to whole, over the reveal', (tester) async {
      await pump(tester, chart);
      expect(progress(tester), 0);
      await tester.pump(revealDuration ~/ 2);
      expect(progress(tester), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(progress(tester), 1);
    });

    testWidgets('whole at once with animations off', (tester) async {
      await pump(tester, chart, still: true);
      expect(progress(tester), 1);
    });

    testWidgets('whole at once when it is not a reveal', (tester) async {
      await pump(
        tester,
        const RevealChart(
          lines: [
            ChartLine([(0, 1), (1, 2)], Colors.blue),
          ],
          semanticsLabel: 'x',
          animate: false,
        ),
      );
      expect(progress(tester), 1);
    });
  });

  group('the figures count up with it', () {
    final counter = CountUp(
      from: d('1000'),
      to: d('1143.51'),
      semanticsLabel: '1143.51 \$',
      builder: (_, v, _) => Text('${v.toStringAsFixed(2)} \$'),
    );

    testWidgets('from the start value, through the way, to the end exactly', (
      tester,
    ) async {
      await pump(tester, counter);
      expect(shown(tester), '1000.00 \$');
      await tester.pump(revealDuration ~/ 2);
      final halfway = double.parse(shown(tester).split(' ').first);
      expect(halfway, inExclusiveRange(1000, 1143.51));
      await tester.pumpAndSettle();
      expect(shown(tester), '1143.51 \$');
    });

    testWidgets('screen readers hear the end figure all along', (tester) async {
      await pump(tester, counter);
      await tester.pump(revealDuration ~/ 2);
      expect(find.bySemanticsLabel('1143.51 \$'), findsOneWidget);
    });

    testWidgets('the end figure at once with animations off', (tester) async {
      await pump(tester, counter, still: true);
      await tester.pump();
      expect(shown(tester), '1143.51 \$');
    });

    testWidgets('a legend row counts its value and its change together, and '
        'ends on the figures it was given', (tester) async {
      await pump(
        tester,
        ChartLegendRow(
          label: 'Coca-Cola',
          value: '1143.51 \$',
          change: '+14.35 %',
          count: (
            from: d('1000'),
            to: d('1143.51'),
            format: (v) => '${v.toStringAsFixed(2)} \$',
            percent: (r) => '+${(r * d('100')).toStringAsFixed(2)} %',
          ),
        ),
      );
      expect(find.text('1000.00 \$'), findsOneWidget);
      expect(find.text('+0.00 %'), findsOneWidget);
      await tester.pump(revealDuration ~/ 2);
      expect(find.text('+14.35 %'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('1143.51 \$'), findsOneWidget);
      expect(find.text('+14.35 %'), findsOneWidget);
    });
  });
}
