import 'package:finance_companion/core/l10n/formats.dart';
import 'package:finance_companion/presentation/widgets/chart_axis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

  test('labels in the middle of even stretches: none clipped at an edge', () {
    expect(axisTicks(100), [12, 37, 62, 87]);
    expect(axisTicks(5), [1, 2, 3, 4]);
    expect(axisTicks(9, ticks: 3), [1, 4, 7]);
  });

  test('few points: as many labels as fit, never twice the same', () {
    expect(axisTicks(3), [0, 1, 2]);
    expect(axisTicks(1), [0]);
    expect(axisTicks(0), isEmpty);
  });

  test('the span picks the unit: days, months, then years', () {
    expect(axisUnit(day(2026, 9, 1), day(2026, 10, 20)), AxisUnit.day);
    expect(axisUnit(day(2025, 10, 20), day(2026, 10, 20)), AxisUnit.month);
    expect(axisUnit(day(2021, 10, 20), day(2026, 10, 20)), AxisUnit.year);
    // A single day reads as a day.
    expect(axisUnit(day(2026, 10, 20), day(2026, 10, 20)), AxisUnit.day);
  });

  test('a label that repeats its neighbour is left out', () {
    final dates = [
      for (var d = 0; d < 100; d++) day(2026, 7, 1).add(Duration(days: d)),
    ];
    String month(DateTime d) => '${d.month}';
    // Ticks 12, 37, 62, 87: July, August, September, September.
    expect(axisLabels(dates, month), {12: '7', 37: '8', 62: '9'});
    expect(axisLabels(const [], month), isEmpty);
  });
}
