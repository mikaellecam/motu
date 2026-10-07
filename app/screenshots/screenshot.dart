// Renders screens to PNG for PRs and the report. Not part of `flutter test`
// (it only scans test/), so CI never compares these images:
//
//   flutter test screenshots --update-goldens
//
// Files land in docs/screenshots/<name>.png.
import 'package:finance_companion/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone-sized canvas, in logical pixels.
const phone = Size(390, 844);

Future<void> _loadFonts() async {
  for (final (family, asset) in [
    ('Baloo2', 'assets/fonts/Baloo2-Variable.ttf'),
    ('Figtree', 'assets/fonts/Figtree-Variable.ttf'),
    ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
  }
}

/// Renders [screen] inside the real app shell, in [locale], and writes
/// `<name>.png`.
void screenshot(
  String name,
  Widget screen, {
  Size size = phone,
  String locale = 'fr',
}) {
  testWidgets(name, (tester) async {
    await tester.runAsync(_loadFonts);
    tester.platformDispatcher.localesTestValue = [Locale(locale)];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MainApp(home: screen));
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/screenshots/$name.png'),
    );
  });
}
