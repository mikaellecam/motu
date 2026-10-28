import 'dart:io';

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/presentation/features/node/node_screen.dart';
import 'package:flutter/material.dart';

import 'screenshot.dart';

// The bundled « Ton premier ETF » mission, not done yet.

void main() {
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );
  screenshot(
    'm6-5-mission',
    const NodeScreen(nodeId: 'ae.mission-first-etf'),
    size: const Size(390, 520),
    overrides: [
      contentPackProvider(actionsEtfIsland).overrideWith((ref) async => pack),
      lesBasesPack,
      completedNodesProvider.overrideWith((ref) => Stream.value(const {})),
    ],
  );
}
