import 'package:flutter/material.dart';

import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.home});

  /// Replaces the home screen; used by the debug entry points.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).app_title,
      theme: appTheme(),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home:
          home ??
          Builder(
            builder: (context) => Scaffold(
              body: Center(child: Text(AppLocalizations.of(context).app_title)),
            ),
          ),
    );
  }
}
