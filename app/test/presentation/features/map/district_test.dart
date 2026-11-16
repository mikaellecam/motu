import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/presentation/features/map/archipelago.dart';
import 'package:finance_companion/presentation/features/map/district.dart';
import 'package:finance_companion/presentation/features/map/iso.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ids = [for (final b in districtBuildings) b.nodeId];

  group('districtGrown', () {
    test('none done: every building plain', () {
      expect(districtGrown({}), List.filled(12, false));
    });

    test('all done: every building grown', () {
      expect(districtGrown(ids.toSet()), List.filled(12, true));
    });

    test('out of order: each lesson grows its own building only', () {
      final grown = districtGrown({'ae.compound-toy', 'ae.livret-vs-etf'});
      expect(
        [
          for (final (i, g) in grown.indexed)
            if (g) i,
        ],
        [0, 6],
      );
    });

    test('ids that are no building\'s change nothing', () {
      expect(
        districtGrown({'lb.safety-cushion', 'ae.not-in-the-pack'}),
        List.filled(12, false),
      );
    });

    test('a building per lesson of the pack, in its order (BRIEF §4.3)', () {
      final pack = jsonDecode(
        File('../content/packs/actions-etf/1/island.json').readAsStringSync(),
      ) as Map<String, Object?>;
      expect(ids, pack['nodes']);
    });
  });

  group('paintDistrict', () {
    final tiles = archipelago
        .firstWhere((i) => i.id == IslandId.actionsEtf)
        .tiles;

    /// The district at [tile] px a tile, its pixels.
    Future<Uint8List> paint({
      required double tile,
      required List<bool> grown,
      bool ferry = true,
    }) async {
      final size = Size(tile * 12, tile * 9);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final p = IsoProjection(
        tile: tile,
        unit: tile * 0.53,
        origin: Offset(size.width * 0.55, size.height * 0.25),
      );
      paintDistrict(
        BlockPen(canvas, AppColors.ink, 1.3),
        p,
        tiles,
        grown: grown,
        ferry: ferry,
      );
      final image = await recorder.endRecording().toImage(
        size.width.round(),
        size.height.round(),
      );
      final bytes = await image.toByteData();
      return bytes!.buffer.asUint8List();
    }

    for (final tile in [34.0, 80.0]) {
      testWidgets('at $tile px a tile, a grown building changes the picture, '
          'and the same lessons draw the same', (tester) async {
        await tester.runAsync(() async {
          final plain = await paint(tile: tile, grown: List.filled(12, false));
          final one = await paint(
            tile: tile,
            grown: [for (var i = 0; i < 12; i++) i == 11],
          );
          final same = await paint(tile: tile, grown: List.filled(12, false));
          expect(sameBytes(plain, same), isTrue);
          expect(sameBytes(plain, one), isFalse);
        });
      });
    }

    testWidgets('the ferry at its pier, once the line is open', (tester) async {
      await tester.runAsync(() async {
        final docked = await paint(tile: 34, grown: [], ferry: true);
        final none = await paint(tile: 34, grown: [], ferry: false);
        expect(sameBytes(docked, none), isFalse);
      });
    });

    test('zoomed in from 60 px a tile', () {
      expect(districtDetailed(const IsoProjection(tile: 59)), isFalse);
      expect(districtDetailed(const IsoProjection(tile: 60)), isTrue);
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
