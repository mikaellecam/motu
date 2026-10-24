import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';

import '../../core/l10n/formats.dart';

/// Where a chart of [count] points labels its x-axis (M9-22): [ticks] labels,
/// each in the middle of an even stretch, so none is clipped at an edge; every
/// point when there are no more than that.
List<int> axisTicks(int count, {int ticks = 4}) {
  if (count <= ticks) return [for (var i = 0; i < count; i++) i];
  return {
    for (var k = 0; k < ticks; k++) ((k + 0.5) * (count - 1) / ticks).round(),
  }.toList();
}

/// What an axis from [first] to [last] counts in: days up to two months,
/// months up to a year and a bit, years beyond.
AxisUnit axisUnit(DateTime first, DateTime last) =>
    switch (last.difference(first).inDays) {
      <= 62 => AxisUnit.day,
      <= 400 => AxisUnit.month,
      _ => AxisUnit.year,
    };

/// The labels a chart of [dates] shows, by point: one per tick, read by
/// [label], unless it repeats the one before (two ticks in one month).
Map<int, String> axisLabels(
  List<DateTime> dates,
  String Function(DateTime) label,
) {
  final labels = <int, String>{};
  String? previous;
  for (final i in axisTicks(dates.length)) {
    final text = label(dates[i]);
    if (text != previous) labels[i] = text;
    previous = text;
  }
  return labels;
}

/// A chart's titles: its [dates] on the x-axis, a few, in their unit; no
/// other axis (the figures around the chart give the values).
FlTitlesData dateAxis(
  List<DateTime> dates,
  Formats formats, {
  TextStyle? style,
}) {
  final unit = dates.isEmpty ? AxisUnit.day : axisUnit(dates.first, dates.last);
  final labels = axisLabels(dates, (d) => formats.axisDate(d, unit));
  return FlTitlesData(
    leftTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    topTitles: const AxisTitles(),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final label = value == value.roundToDouble()
              ? labels[value.round()]
              : null;
          if (label == null) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            child: Text(label, style: style),
          );
        },
      ),
    ),
  );
}
