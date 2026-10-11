import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'application/learning/missions.dart';
import 'application/providers.dart';
import 'application/settings/settings.dart';
import 'application/wallet/live_catch_up.dart';
import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'presentation/routing/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // First launch: the questionnaire before anything else (BRIEF §3).
  final profile = await container.read(profileRepositoryProvider).load();
  // The live wallet exists from the first launch (BRIEF §4.5).
  await container
      .read(walletRepositoryProvider)
      .ensureLiveWallet(container.read(liveClockProvider).now());
  // Pending orders fill on the sessions that closed since (M4-6); the app
  // opens without waiting for the network.
  container.read(liveCatchUpProvider.notifier).run().ignore();
  // Missions complete by themselves while the app runs (BRIEF §4.3).
  container.read(missionTrackerProvider);
  final router = buildRouter(
    initialLocation: profile == null ? '/onboarding' : '/',
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      // The language chosen in Settings, else the device's (BRIEF §4.14).
      child: Consumer(
        builder: (context, ref, _) => MainApp(
          router: router,
          locale: switch (ref.watch(appLanguageProvider)) {
            final code? => Locale(code),
            null => null,
          },
        ),
      ),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.router, this.locale});

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

  /// The language to show; null follows the device.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).app_title,
      theme: appTheme(),
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
