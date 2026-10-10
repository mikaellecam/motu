import 'package:flutter/services.dart';

/// The baseline pack of [islandId] shipped with the app (`assets/packs/`),
/// so the first launch has content offline (ADR-006).
Future<String> bundledPack(String islandId) =>
    rootBundle.loadString('assets/packs/$islandId.json');
