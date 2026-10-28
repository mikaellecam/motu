/// What the Les bases pack's copy says happened is what its frozen data shows
/// (BRIEF §9). Real data only: CI runs on made-up figures and leaves this file
/// out (ADR-007).
@Tags(['real-data'])
library;

import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  final pack = decodePack(
    File('assets/packs/les-bases.json').readAsStringSync(),
  );
  final nodes = {for (final n in pack.nodes) n.id: n};
  Map<DateTime, Decimal> byDay(String dataset) => {
    for (final (t, v) in pack.datasets[dataset]!.points) t: v,
  };
  Decimal on(String dataset, int y, int m, int day) =>
      byDay(dataset)[DateTime.utc(y, m, day)]!;
  Decimal ratio(Decimal a, Decimal b) =>
      (a / b).toDecimal(scaleOnInfinitePrecision: 6) - Decimal.one;
  Matcher about(String value, String margin) {
    final (lo, hi) = (d(value) - d(margin), d(value) + d(margin));
    return predicate<Decimal>((v) => v >= lo && v <= hi, '$value ± $margin');
  }

  test('notes: 10 000 € at the end of 2015 bought what 8 275 € did, '
      'end of 2025', () {
    expect(on('ds.cash-2016-m', 2025, 12, 31), d('10000'));
    expect(on('ds.cash-real-2016-m', 2025, 12, 31), about('8275', '0.5'));
    // Prices up almost 21 %: 10 000 / 8 275 − 1.
    expect(
      ratio(d('10000'), on('ds.cash-real-2016-m', 2025, 12, 31)),
      about('0.208', '0.002'),
    );
  });

  test('the Livret in 2022: +1,3 %, buying what 9 570 € did; the gap closing '
      'in 2024', () {
    expect(on('ds.livret-a-2022-m', 2022, 12, 31), about('10129', '0.5'));
    expect(
      ratio(on('ds.livret-a-2022-m', 2022, 12, 31), d('10000')),
      about('0.013', '0.0005'),
    );
    expect(on('ds.livret-a-real-2022-m', 2022, 12, 31), about('9570', '0.5'));
    // Lower still at the end of 2023, higher at the end of 2024.
    final (y22, y23, y24) = (
      on('ds.livret-a-real-2022-m', 2022, 12, 31),
      on('ds.livret-a-real-2022-m', 2023, 12, 31),
      on('ds.livret-a-real-2022-m', 2024, 12, 31),
    );
    expect(y23, lessThan(y22));
    expect(y24, greaterThan(y23));
  });

  test('February 2020: −31 % in four weeks, 3 454 € at the end of March', () {
    final decision = decodeDecision(nodes['lb.cushion-2020']!, pack);
    expect(decision.moment, DateTime.utc(2020, 2, 21));
    final at = on(decision.dataset, 2020, 2, 21);
    expect(
      ratio(on(decision.dataset, 2020, 3, 20), at),
      about('-0.31', '0.005'),
    );
    final end = on(decision.dataset, 2020, 3, 31);
    expect(ratio(end, at), about('-0.23', '0.005'));
    expect(
      (decision.invested * end / at).toDecimal(scaleOnInfinitePrecision: 2),
      about('3454', '0.5'),
    );
  });
}
