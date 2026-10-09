// Renders screens to PNG for PRs and the report. Not part of `flutter test`
// (it only scans test/), so CI never compares these images:
//
//   flutter test screenshots --update-goldens
//
// Files land in docs/screenshots/<name>.png.
import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
/// [overrides] feed the screen fixed data instead of the network.
void screenshot(
  String name,
  Widget screen, {
  Size size = phone,
  String locale = 'fr',
  List<Override> overrides = const [],
  Future<void> Function(WidgetTester tester)? act,
}) => _capture(
  name,
  () => MainApp.screen(screen),
  size: size,
  locale: locale,
  overrides: overrides,
  act: act,
);

/// Renders the real app opened at [location] (tabs and all) and writes
/// `<name>.png`.
/// [act] drives the screen (taps…) before the capture.
void screenshotRoute(
  String name,
  String location, {
  Size size = phone,
  String locale = 'fr',
  Future<void> Function(WidgetTester tester)? act,
}) => _capture(
  name,
  () => MainApp(router: buildRouter(initialLocation: location)),
  size: size,
  locale: locale,
  act: act,
);

/// [app] is built inside the test: a router built earlier would set up the
/// binding before the test framework does.
void _capture(
  String name,
  Widget Function() app, {
  required Size size,
  required String locale,
  List<Override> overrides = const [],
  Future<void> Function(WidgetTester tester)? act,
}) {
  testWidgets(name, (tester) async {
    await tester.runAsync(_loadFonts);
    tester.platformDispatcher.localesTestValue = [Locale(locale)];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // An empty in-memory database: screens that read data start from scratch.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), ...overrides],
        child: app(),
      ),
    );
    // Fixed frames, not pumpAndSettle: some screens animate forever (skeletons).
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    if (act != null) {
      await act(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/screenshots/$name.png'),
    );
  });
}
