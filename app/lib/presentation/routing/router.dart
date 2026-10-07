import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_localizations.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../shell/app_shell.dart';

/// Routes of the app (BRIEF §3). The four tabs share a shell with the bottom
/// bar; every flow (asset, order, wizard, node player…) opens full screen
/// above it. Unknown locations go back to the map.
GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  onException: (_, _, router) => router.go('/'),
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/', builder: (_, _) => const MapTab())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/wallets', builder: (_, _) => const WalletsTab()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/explore', builder: (_, _) => const ExploreTab()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/glossary', builder: (_, _) => const GlossaryTab()),
          ],
        ),
      ],
    ),
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
    _pending('/settings'),
    _pending('/tools/dca'),
    _pending('/island/:islandId'),
    _pending('/node/:nodeId'),
    GoRoute(
      path: '/wallets/new',
      builder: (_, state) => PendingScreen(
        args: TripWizardArgs.fromQuery(state.uri.queryParameters),
      ),
    ),
    _pending('/wallet/:walletId'),
    _pending('/wallet/:walletId/stop/:eventId'),
    _pending('/wallet/:walletId/summary'),
    _pending('/wallet/:walletId/order/:orderId'),
    _pending('/asset/:assetId'),
  ],
);

GoRoute _pending(String path) =>
    GoRoute(path: path, builder: (_, _) => const PendingScreen());

/// Prefill of the trip wizard, from a deep link such as
/// `/wallets/new?step=1&date=2020-02-18&difficulty=realiste&from=ae.march-2020`
/// (a lesson's "Rejoue-le toi-même" bridge, BRIEF §1.2). Values that don't
/// parse are dropped; the wizard then asks for them.
final class TripWizardArgs {
  const TripWizardArgs({
    this.step = 1,
    this.date,
    this.difficulty,
    this.fromNode,
  });

  factory TripWizardArgs.fromQuery(Map<String, String> query) {
    final step = int.tryParse(query['step'] ?? '');
    final date = DateTime.tryParse(query['date'] ?? '');
    return TripWizardArgs(
      step: step != null && step >= 1 && step <= 3 ? step : 1,
      date: date == null ? null : DateTime.utc(date.year, date.month, date.day),
      difficulty: query['difficulty'],
      fromNode: query['from'],
    );
  }

  /// Wizard step, 1 to 3.
  final int step;
  final DateTime? date;
  final String? difficulty;

  /// The node the bridge came from.
  final String? fromNode;
}

/// Stands in for a screen its own issue has not built yet: a way back, no
/// made-up content.
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key, this.args});

  /// What the screen will be opened with (tests read it).
  final Object? args;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
}

/// The map tab: « Ton archipel », settings in the header (BRIEF §3, §4.2).
class MapTab extends StatelessWidget {
  const MapTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.map_title),
        actions: [
          IconButton(
            tooltip: l10n.map_settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

class WalletsTab extends StatelessWidget {
  const WalletsTab({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).tab_wallets)),
  );
}

class ExploreTab extends StatelessWidget {
  const ExploreTab({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).tab_explore)),
  );
}

class GlossaryTab extends StatelessWidget {
  const GlossaryTab({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).tab_glossary)),
  );
}
