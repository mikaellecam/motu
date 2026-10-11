import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/domain/learning/decision.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:finance_companion/domain/learning/puzzle.dart';
import 'package:finance_companion/domain/learning/reveal.dart';
import 'package:finance_companion/domain/learning/sort.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);

/// The bundled Actions & ETF pack (M6-8): every lesson plays, and what its
/// copy says happened is what its frozen data shows.
void main() {
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );
  final nodes = {for (final n in pack.nodes) n.id: n};
  List<(DateTime, Decimal)> points(String dataset) =>
      pack.datasets[dataset]!.points;
  Decimal change(String dataset) => curveChange(points(dataset))!;
  Matcher about(String value, String margin) {
    final (lo, hi) = (d(value) - d(margin), d(value) + d(margin));
    return predicate<Decimal>((v) => v >= lo && v <= hi, '$value ± $margin');
  }

  test('every lesson plays: its payload decodes for its player', () {
    for (final node in pack.nodes) {
      switch (node.type) {
        case NodeType.predictReveal:
          decodePredictReveal(node, pack);
        case NodeType.toy:
          decodeToy(node, pack);
        case NodeType.decision:
          decodeDecision(node, pack);
        case NodeType.sort:
          decodeSort(node, pack);
        case NodeType.buildPuzzle:
          decodePuzzle(node, pack);
        case NodeType.checkpoint:
          decodeCheckpoint(node, pack);
        case NodeType.mission:
          decodeMission(node, pack);
      }
    }
    expect(pack.glossary, hasLength(26));
  });

  group('what the copy says matches the frozen data', () {
    test('Livret ou ETF ?: the ETF more than tripled, the Livret +15 %', () {
      final reveal = decodePredictReveal(nodes['ae.livret-vs-etf']!, pack);
      expect(reveal.answer, 'etf');
      expect(change('ds.acwi-eur-2016-m'), greaterThan(d('2')));
      expect(change('ds.livret-a-2016-m'), about('0.155', '0.005'));
      // −19 % from January to March 2020, in euros.
      final byDay = {for (final (t, v) in points('ds.acwi-eur-2016-m')) t: v};
      final fall =
          (byDay[DateTime.utc(2020, 3, 31)]! /
                  byDay[DateTime.utc(2020, 1, 31)]!)
              .toDecimal(scaleOnInfinitePrecision: 6) -
          Decimal.one;
      expect(fall, about('-0.19', '0.005'));
    });

    test('Apple fell more than the world ETF in 2022: −24 % and −17 %', () {
      expect(
        decodePredictReveal(nodes['ae.apple-vs-world-2022']!, pack).answer,
        'apple',
      );
      expect(change('ds.aapl-2022-w'), about('-0.24', '0.005'));
      expect(change('ds.acwi-2022-w'), about('-0.17', '0.005'));
    });

    test('March 2020: −32 % in five weeks, then +70 % by February 2021', () {
      final decision = decodeDecision(nodes['ae.march-2020']!, pack);
      final curve = points(decision.dataset);
      final atMoment = curve.firstWhere((p) => p.$1 == decision.moment).$2;
      final peak = curve
          .where((p) => p.$1.isBefore(decision.moment))
          .map((p) => p.$2)
          .reduce((a, b) => a > b ? a : b);
      expect(
        (atMoment / peak).toDecimal(scaleOnInfinitePrecision: 6) - Decimal.one,
        about('-0.32', '0.005'),
      );
      expect(changeAfter(curve, decision.moment), about('0.70', '0.005'));
    });

    test('risk ladder: Livret, world ETF, emerging ETF, then Apple', () {
      final sort = decodeSort(nodes['ae.risk-ladder']!, pack);
      final values = {
        for (final item in sort.items)
          item.id: itemValue(
            item,
            item.dataset == null ? null : points(item.dataset!),
          )!,
      };
      expect(trueOrder([for (final i in sort.items) i.id], values), [
        'livret',
        'world',
        'emerging',
        'apple',
      ]);
      expect(values['world'], about('0.17', '0.005'));
      expect(values['apple'], greaterThan(values['world']! * d('1.8')));
    });

    test(
      'the dollar trap: +14 % in dollars, +0,5 % in euros, dollar −12 %',
      () {
        expect(
          decodePredictReveal(nodes['ae.dollar-trap']!, pack).answer,
          'little',
        );
        expect(change('ds.ko-2017-w'), about('0.14', '0.005'));
        expect(change('ds.ko-eur-2017-w'), about('0.005', '0.0025'));
        expect(change('ds.usd-eur-2017-w'), about('-0.12', '0.005'));
      },
    );

    test('a calm portfolio exists; the world ETF alone is not one', () {
      final puzzle = decodePuzzle(nodes['ae.calm-portfolio']!, pack);
      final prices = {
        for (final a in puzzle.assets) a.dataset: points(a.dataset),
      };
      PuzzleCheck check(Map<String, Decimal> weights) => checkPuzzle(
        puzzle.rules,
        puzzle.assets,
        weights: weights,
        volatility: portfolioVolatility(prices, weights),
      );
      expect(
        check({
          'ds.acwi-3y-d': d('0.1'),
          'ds.agg-3y-d': d('0.4'),
          'ds.bwx-3y-d': d('0.4'),
          'ds.vgk-3y-d': d('0.1'),
        }).solved,
        isTrue,
      );
      final alone = check({'ds.acwi-3y-d': Decimal.one});
      expect((alone.volatility, alone.assets), (false, false));
    });
  });
}
