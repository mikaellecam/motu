// Renders screens to PNG for PRs and the report. Not part of `flutter test`
// (it only scans test/), so CI never compares these images:
//
//   flutter test screenshots --update-goldens
//
// Files land in docs/screenshots/<name>.png.
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/routing/router.dart';
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

/// Renders [screen] with the app's theme and localizations, in [locale], and
/// writes `<name>.png`.
void screenshot(
  String name,
  Widget screen, {
  Size size = phone,
  String locale = 'fr',
}) => _capture(name, () => MainApp.screen(screen), size: size, locale: locale);

/// Renders the real app opened at [location] (tabs and all) and writes
/// `<name>.png`.
void screenshotRoute(
  String name,
  String location, {
  Size size = phone,
  String locale = 'fr',
}) => _capture(
  name,
  () => MainApp(router: buildRouter(initialLocation: location)),
  size: size,
  locale: locale,
);

/// [app] is built inside the test: a router built earlier would set up the
/// binding before the test framework does.
void _capture(
  String name,
  Widget Function() app, {
  required Size size,
  required String locale,
}) {
  testWidgets(name, (tester) async {
    await tester.runAsync(_loadFonts);
    tester.platformDispatcher.localesTestValue = [Locale(locale)];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    // Fixed frames, not pumpAndSettle: some screens animate forever (skeletons).
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/screenshots/$name.png'),
    );
  });
}
