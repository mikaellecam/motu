import 'dart:convert';

import 'package:flutter/services.dart';

/// The baseline pack of [islandId] shipped with the app (`assets/packs/`),
/// so the first launch has content offline (ADR-006).
///
/// Decoded here rather than with `loadString`, which hands text over 50 KB
/// to another isolate: a few milliseconds for a pack, and nothing a widget
/// test's clock waits on forever.
Future<String> bundledPack(String islandId) async {
  final data = await rootBundle.load('assets/packs/$islandId.json');
  return utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}
