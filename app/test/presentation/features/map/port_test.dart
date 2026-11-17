import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:finance_companion/presentation/features/map/iso.dart';
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
    IsoProjection at(double tile) {
      final p0 = IsoProjection(tile: tile, unit: tile * 14 / 30);
      final size = Size(tile * 12, tile * 9);
      return p0.shifted(
        Offset(size.width * 0.55, size.height * 0.2) - p0.project(1.4, 3.4),
      );
    }

    Future<Uint8List> paint({
      required double tile,
      required List<bool> built,
      Set<String> lines = const {},
      Set<int> ghosts = const {},
      Map<int, double> rising = const {},
      Map<int, double> fading = const {},
    }) async {
      final size = Size(tile * 12, tile * 9);
      final recorder = ui.PictureRecorder();
      paintPort(
        BlockPen(Canvas(recorder), AppColors.ink, 1.2),
        at(tile),
        size,
        built: built,
        lines: lines,
        ghosts: ghosts,
        rising: rising,
        fading: fading,
      );
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

    testWidgets('an open line leaves the harbour, from its ferry quay only '
        '(M13-7)', (tester) async {
      await tester.runAsync(() async {
        final quay = [for (var i = 0; i < 9; i++) i == 4];
        final none = await paint(tile: 30, built: quay);
        final one = await paint(
          tile: 30,
          built: quay,
          lines: {actionsEtfIsland},
        );
        expect(sameBytes(none, one), isFalse);
        // No quay: no line, whatever is open.
        final bare = await paint(tile: 30, built: []);
        final noQuay = await paint(
          tile: 30,
          built: [],
          lines: {actionsEtfIsland},
        );
        expect(sameBytes(bare, noQuay), isTrue);
      });
    });

    testWidgets('a part unlocked, not built, shows as its ghost (M13-7)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final bare = await paint(tile: 30, built: []);
        final ghost = await paint(tile: 30, built: [], ghosts: {5});
        final built = await paint(
          tile: 30,
          built: [for (var i = 0; i < 9; i++) i == 5],
        );
        expect(sameBytes(bare, ghost), isFalse);
        expect(sameBytes(built, ghost), isFalse);
      });
    });

    testWidgets('a part just done rises from the ground into its ghost, '
        'which then fades (M13-17)', (tester) async {
      await tester.runAsync(() async {
        const tile = 60.0, crane = 5;
        final only = [for (var i = 0; i < 9; i++) i == crane];
        final bare = await paint(tile: tile, built: []);
        final built = await paint(tile: tile, built: only);
        final half = await paint(tile: tile, built: only, rising: {crane: 0.5});
        // Below the line climbing from under its footprint to over its top,
        // the part as built; above it, nothing yet.
        final part = portParts[crane];
        final p = at(tile);
        final ground = p.project(part.x, part.y).dy + tile;
        final top = p.project(part.x, part.y, part.top).dy - tile / 2;
        final line = ground - (ground - top) * 0.5;
        final width = (tile * 12).round() * 4;
        final height = (tile * 9).round();
        // Bytes differing between [a] and [b] in rows [from] to [to]: a
        // clipped stroke's anti-aliasing differs by a pixel or two, so the
        // part is compared by how much of it is there.
        int apart(Uint8List a, Uint8List b, int from, int to) => [
          for (var i = from * width; i < to * width; i++)
            if (a[i] != b[i]) i,
        ].length;
        final below = (line.ceil() + 1, height);
        final above = (0, line.floor() - 1);
        expect(
          apart(half, built, below.$1, below.$2),
          lessThan(apart(bare, built, below.$1, below.$2) * 0.05),
          reason: 'below the line, the part as built',
        );
        expect(
          apart(half, bare, above.$1, above.$2),
          lessThan(apart(built, bare, above.$1, above.$2) * 0.05),
          reason: 'above it, nothing yet',
        );
        expect(sameBytes(half, built), isFalse);
        expect(sameBytes(half, bare), isFalse);
        // Not risen at all: nothing yet; risen: the part.
        expect(
          sameBytes(
            await paint(tile: tile, built: only, rising: {crane: 0}),
            bare,
          ),
          isTrue,
        );
        expect(
          sameBytes(
            await paint(tile: tile, built: only, rising: {crane: 1}),
            built,
          ),
          isTrue,
        );
        // Its ghost over it until it has faded.
        final ghosted = await paint(
          tile: tile,
          built: only,
          fading: {crane: 1},
        );
        expect(sameBytes(ghosted, built), isFalse);
        expect(
          sameBytes(
            await paint(tile: tile, built: only, fading: {crane: 0}),
            built,
          ),
          isTrue,
        );
      });
    });

    test('the quay stands with Les bases\' fifth part', () {
      expect(quayStands(const []), isFalse);
      expect(quayStands([for (var i = 0; i < 9; i++) i == 4]), isTrue);
      expect(quayStands([for (var i = 0; i < 9; i++) i != 4]), isFalse);
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

  group('the village (M13-11)', () {
    for (final tile in [40.0, 80.0]) {
      testWidgets('at $tile px a tile, its cottages stand behind the rails, '
          'there from the start', (tester) async {
        await tester.runAsync(() async {
          final p = IsoProjection(
            tile: tile,
            unit: tile * 14 / 30,
            origin: Offset(tile * 8, tile * 3),
          );
          final size = Size(tile * 14, tile * 9);
          final recorder = ui.PictureRecorder();
          paintPort(
            BlockPen(Canvas(recorder), AppColors.ink, 1.2),
            p,
            size,
            built: const [],
            lines: const {},
          );
          final image = await recorder.endRecording().toImage(
            size.width.round(),
            size.height.round(),
          );
          final bytes = (await image.toByteData())!;
          Color at(Offset o) {
            final i = (o.dy.round() * image.width + o.dx.round()) * 4;
            return Color.fromARGB(
              bytes.getUint8(i + 3),
              bytes.getUint8(i),
              bytes.getUint8(i + 1),
              bytes.getUint8(i + 2),
            );
          }

          // A cottage's walls, where the grass would be.
          expect(at(p.project(-3.2 + 0.31, 1.8, 0.2)), isNot(MapPalette.grass));
          // The church's tower.
          expect(
            at(p.project(-4.15 - 0.55 + 0.17, 3.25, 1.0)),
            PortPalette.quay.right,
          );
          // Grass still between the houses.
          expect(at(p.project(-5.6, 7.5)), MapPalette.grass);
        });
      });
    }
  });
}

bool sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
