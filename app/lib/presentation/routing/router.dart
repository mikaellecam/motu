import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/trip/trip_wizard.dart';
import '../../application/learning/ui_level.dart';
import '../../application/wallet/living_island.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../features/map/archipelago.dart';
import '../features/map/archipelago_map.dart';
import '../features/map/next_step_card.dart';
import '../features/asset/asset_screen.dart';
import '../features/explorer/explorer_screen.dart';
import '../features/glossary/glossary_screen.dart';
import '../features/island/island_screen.dart';
import '../features/node/node_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/order/order_screen.dart';
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
    GoRoute(
      path: '/wallet/:walletId/order/:orderId',
      builder: (_, state) =>
          OrderScreen(orderId: state.pathParameters['orderId']!),
    ),
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

/// The map tab (BRIEF §3, §4.2): « Ton archipel », the islands opened and
/// the level in the header, settings, and the next-step card at the bottom.
class MapTab extends ConsumerWidget {
  const MapTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Offline or still loading, the island stands as it last did, or bare.
    final buildings = ref.watch(livingIslandProvider).value ?? const [];
    final level = ref.watch(currentUiLevelProvider).value;
    final open = archipelago.where((i) => !i.locked).length;
    return Scaffold(
      // World screens sit on the sea (BRIEF §10.2).
      backgroundColor: AppColors.sea,
      body: Stack(
        children: [
          Positioned.fill(
            child: ArchipelagoMap(
              buildings: buildings,
              onOpen: (_) => context.push('/island/actions-etf'),
            ),
          ),
          const Positioned(
            left: AppSpace.screenPadding,
            right: AppSpace.screenPadding,
            bottom: AppSpace.screenPadding,
            child: NextStepCard(),
          ),
        ],
      ),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.map_title),
            Text(
              l10n.map_islands_open(open, archipelago.length),
              style: AppText.caption.copyWith(color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          if (level != null) _LevelChip(level),
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

/// « Niveau 2 » (BRIEF §4.15), in the level colour.
class _LevelChip extends StatelessWidget {
  const _LevelChip(this.level);
  final int level;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpace.x3,
      vertical: AppSpace.x1,
    ),
    decoration: BoxDecoration(
      color: AppColors.progress,
      borderRadius: BorderRadius.circular(AppShape.chunkyButtonRadius),
      border: Border.all(color: AppColors.ink, width: 2),
    ),
    child: Text(
      AppLocalizations.of(context).map_level(level),
      style: AppText.label.copyWith(color: AppColors.ink),
    ),
  );
}

class GlossaryTab extends StatelessWidget {
  const GlossaryTab({super.key});

  @override
  Widget build(BuildContext context) => const GlossaryScreen();
}
