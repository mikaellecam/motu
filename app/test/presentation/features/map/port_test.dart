import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/presentation/features/map/port.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ids = [for (final p in portParts) p.nodeId];
  List<int> standing(List<bool> built) => [
    for (final (i, b) in built.indexed)
      if (b) i,
  ];

  group('portBuilt', () {
    test('none done: only the old jetty, no part', () {
      expect(portBuilt({}, skipped: false), List.filled(9, false));
    });

    test('all done: the whole harbour, the lighthouse lit', () {
      expect(portBuilt(ids.toSet(), skipped: false), List.filled(9, true));
    });

    test('out of order: each lesson builds its own part only', () {
      expect(
        standing(
          portBuilt({'lb.loan-cost', 'lb.safety-cushion'}, skipped: false),
        ),
        [0, 5],
      );
    });

    test('skipped at onboarding: built through the ferry quay, and what '
        'the lessons built since', () {
      expect(standing(portBuilt({}, skipped: true)), [0, 1, 2, 3, 4]);
      expect(standing(portBuilt({'lb.spot-the-scam'}, skipped: true)), [
        0,
        1,
        2,
        3,
        4,
        7,
      ]);
    });

    test('ids that are no part\'s change nothing', () {
      expect(
        portBuilt({'ae.livret-vs-etf', 'lb.unknown'}, skipped: false),
        List.filled(9, false),
      );
    });

    test('a part per lesson of the pack, in its order (BRIEF §4.3)', () {
      final pack = jsonDecode(
        File('../content/packs/les-bases/1/island.json').readAsStringSync(),
      ) as Map<String, Object?>;
      expect(ids, pack['nodes']);
    });
  });

  group('portLines', () {
    test('nothing done: no line, unless Actions & ETF is open', () {
      expect(portLines({}, actionsEtfOpen: false), isEmpty);
      expect(portLines({}, actionsEtfOpen: true), {actionsEtfIsland});
    });

    test('the loan\'s lesson opens Immobilier\'s', () {
      expect(portLines({'lb.loan-cost'}, actionsEtfOpen: true), {
        actionsEtfIsland,
        realEstateIsland,
      });
    });

    test('spotting the scam alone opens neither Trading nor Crypto', () {
      expect(portLines({'lb.spot-the-scam'}, actionsEtfOpen: true), {
        actionsEtfIsland,
      });
    });

    test('each with its lesson of Actions & ETF', () {
      expect(
        portLines({'lb.spot-the-scam', 'ae.risk-ladder'}, actionsEtfOpen: true),
        {actionsEtfIsland, cryptoIsland},
      );
      expect(
        portLines({
          'lb.spot-the-scam',
          'ae.risk-ladder',
          'ae.checkpoint-1',
        }, actionsEtfOpen: true),
        {actionsEtfIsland, cryptoIsland, tradingIsland},
      );
    });
  });

  group('the painter', () {
    Future<Uint8List> paint({
      required double tile,
      required List<bool> built,
      Set<String> lines = const {},
    }) async {
      final size = Size(tile * 12, tile * 9);
      final recorder = ui.PictureRecorder();
      PortPainter(
        built: built,
        lines: lines,
        tile: tile,
      ).paint(Canvas(recorder), size);
      final image = await recorder.endRecording().toImage(
        size.width.round(),
        size.height.round(),
      );
      return (await image.toByteData())!.buffer.asUint8List();
    }

    for (final tile in [30.0, 80.0]) {
      testWidgets('at $tile px a tile, a part built changes the picture, and '
          'the same parts draw the same', (tester) async {
        await tester.runAsync(() async {
          final bare = await paint(tile: tile, built: List.filled(9, false));
          final again = await paint(tile: tile, built: List.filled(9, false));
          final lit = await paint(
            tile: tile,
            built: [for (var i = 0; i < 9; i++) i == 8],
          );
          expect(sameBytes(bare, again), isTrue);
          expect(sameBytes(bare, lit), isFalse);
        });
      });
    }

    testWidgets('an open line leaves the harbour', (tester) async {
      await tester.runAsync(() async {
        final none = await paint(tile: 30, built: []);
        final one = await paint(tile: 30, built: [], lines: {actionsEtfIsland});
        expect(sameBytes(none, one), isFalse);
      });
    });

    test('repaints when what stands changes', () {
      final a = PortPainter(built: const [true], lines: const {});
      expect(
        a.shouldRepaint(PortPainter(built: const [true], lines: const {})),
        isFalse,
      );
      expect(
        a.shouldRepaint(PortPainter(built: const [false], lines: const {})),
        isTrue,
      );
      expect(
        a.shouldRepaint(
          PortPainter(built: const [true], lines: const {cryptoIsland}),
        ),
        isTrue,
      );
    });
  });
}

bool sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
