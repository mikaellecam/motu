import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'presentation/routing/router.dart';

void main() {
  runApp(MainApp(router: buildRouter()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.router});

  /// A single screen with the app's theme and localizations: debug entry
  /// points and screenshots.
  MainApp.screen(Widget screen, {Key? key})
    : this(
        key: key,
        router: GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => screen)],
        ),
      );

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).app_title,
      theme: appTheme(),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
