import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'application/providers.dart';
import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'presentation/routing/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // First launch: the questionnaire before anything else (BRIEF §3).
  final profile = await container.read(profileRepositoryProvider).load();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MainApp(
        router: buildRouter(
          initialLocation: profile == null ? '/onboarding' : '/',
        ),
      ),
    ),
  );
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
