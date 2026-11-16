import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/learning/place.dart';
import '../../application/trip/trip_wizard.dart';
import '../../application/order/order_ticket.dart' show OrderDone;
import '../../core/theme/tokens.dart';
import '../features/asset/asset_screen.dart';
import '../features/dca/dca_screen.dart';
import '../features/explorer/explorer_screen.dart';
import '../features/glossary/glossary_screen.dart';
import '../features/island/island_screen.dart';
import '../features/node/node_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/order/order_done_screen.dart';
import '../features/order/order_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/trip/stop_screen.dart';
import '../features/trip/summary_screen.dart';
import '../features/trip_wizard/trip_wizard_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../features/wallets/wallets_screen.dart';
import '../shell/app_shell.dart';

/// Routes of the app (BRIEF §3). The four tabs share a shell with the bottom
/// bar; every flow (asset, order, wizard, node player…) opens full screen
/// above it. Unknown locations go back to the island the user is on.
GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  onException: (_, _, router) => router.go('/'),
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/', builder: (_, _) => const HomeTab())],
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
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/tools/dca', builder: (_, _) => const DcaScreen()),
    GoRoute(
      path: '/island/:islandId',
      builder: (_, state) => IslandScreen(
        islandId: state.pathParameters['islandId']!,
        // Landed from the sea chart (M13-5).
        arriving: state.uri.queryParameters['arrive'] == '1',
      ),
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
    // A buy's world screen (M9-34); without what placing did, the order.
    GoRoute(
      path: '/wallet/:walletId/order/:orderId/done',
      builder: (_, state) => switch (state.extra) {
        final OrderDone done => OrderDoneScreen(
          walletId: state.pathParameters['walletId']!,
          done: done,
        ),
        _ => OrderScreen(orderId: state.pathParameters['orderId']!),
      },
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

/// The « Archipel » tab (BRIEF §3, M13-6): the island the user was on last
/// time, up close; the first time, where their way starts.
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(placeProvider).value) {
        (:final island, :final arriving) => IslandScreen(
          // A crossing lands on a new island: its own state, from its pier.
          key: ValueKey(island),
          islandId: island,
          arriving: arriving,
        ),
        null => const Scaffold(backgroundColor: AppColors.sea),
      };
}

class GlossaryTab extends StatelessWidget {
  const GlossaryTab({super.key});

  @override
  Widget build(BuildContext context) => const GlossaryScreen();
}
