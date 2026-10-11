import 'package:finance_companion/core/l10n/app_localizations.dart';
import 'package:finance_companion/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] inside the app theme and localizations, in [locale].
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  String locale = 'fr',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
  // Let the localization delegates resolve.
  await tester.pump();
}

/// The accessibility pass (M9-3): every tap target at least 44 × 44, every
/// tappable labelled, text readable against its background.
Future<void> expectAccessible(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Renders the next pumps with text at [scale] (130 % for the pass); the
/// tear-down puts it back.
void textAt(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}
