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
