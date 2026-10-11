import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../application/trip/trip_wizard.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../features/map/archipelago_map.dart';
import '../features/asset/asset_screen.dart';
import '../features/explorer/explorer_screen.dart';
import '../features/glossary/glossary_screen.dart';
import '../features/island/island_screen.dart';
import '../features/node/node_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/trip/stop_screen.dart';
import '../features/trip/summary_screen.dart';
import '../features/trip_wizard/trip_wizard_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../features/wallets/wallets_screen.dart';
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
            GoRoute(path: '/wallets', builder: (_, _) => const WalletsScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/explore',
              builder: (_, state) =>
                  ExplorerScreen(walletId: state.uri.queryParameters['wallet']),
            ),
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
    GoRoute(
      path: '/island/:islandId',
      builder: (_, state) =>
          IslandScreen(islandId: state.pathParameters['islandId']!),
    ),
    GoRoute(
      path: '/node/:nodeId',
      builder: (_, state) =>
          NodeScreen(nodeId: state.pathParameters['nodeId']!),
    ),
    GoRoute(
      path: '/wallets/new',
      builder: (_, state) => TripWizardScreen(
        args: TripWizardArgs.fromQuery(state.uri.queryParameters),
      ),
    ),
    GoRoute(
      path: '/wallet/:walletId',
      builder: (_, state) =>
          WalletScreen(walletId: state.pathParameters['walletId']!),
    ),
    GoRoute(
      path: '/wallet/:walletId/stop/:eventId',
      builder: (_, state) =>
          StopScreen(walletId: state.pathParameters['walletId']!),
    ),
    GoRoute(
      path: '/wallet/:walletId/summary',
      builder: (_, state) =>
          TripSummaryScreen(walletId: state.pathParameters['walletId']!),
    ),
    _pending('/wallet/:walletId/order/:orderId'),
    GoRoute(
      path: '/asset/:assetId',
      builder: (_, state) => AssetScreen(
        assetId: state.pathParameters['assetId']!,
        walletId: state.uri.queryParameters['wallet'],
      ),
    ),
  ],
);

GoRoute _pending(String path) =>
    GoRoute(path: path, builder: (_, _) => const PendingScreen());

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
      // World screens sit on the sea (BRIEF §10.2).
      backgroundColor: AppColors.sea,
      body: ArchipelagoMap(onOpen: (_) => context.push('/island/actions-etf')),
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

class GlossaryTab extends StatelessWidget {
  const GlossaryTab({super.key});

  @override
  Widget build(BuildContext context) => const GlossaryScreen();
}
