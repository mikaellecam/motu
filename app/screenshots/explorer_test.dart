import 'package:finance_companion/application/explorer/explorer.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/presentation/features/explorer/explorer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalogue.dart';
import 'screenshot.dart';

void main() {
  final overrides = [
    cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
    explorerRowsProvider.overrideWith((ref, _) async => catalogueRows),
  ];
  screenshot('m4-3-explorer', const ExplorerScreen(), overrides: overrides);
  screenshot(
    'm4-3-explorer-search',
    const ExplorerScreen(),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.widgetWithText(ChoiceChip, 'Actions'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'hermes');
      await tester.pump();
    },
  );
}
