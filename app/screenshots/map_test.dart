import 'package:finance_companion/application/learning/ui_level.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// The « Archipel » tab at the first launch: the port, nothing but the
// breakwater's ghost and its pin (M13-6, M13-7); touching the pin shows its
// lesson's card (M13-9).

void main() {
  screenshotRoute(
    'm7-1-map',
    '/',
    overrides: [currentUiLevelProvider.overrideWith((ref) async => 1)],
  );

  screenshotRoute(
    'm13-9-lesson-card',
    '/',
    overrides: [currentUiLevelProvider.overrideWith((ref) async => 1)],
    act: (tester) async {
      // The island loads a moment after the tab.
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.bySemanticsLabel(RegExp(r'^1\. ')));
    },
  );
}
