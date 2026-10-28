import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/theme/tokens.dart';

/// The bottom tab bar around the four tabs (BRIEF §3). Each tab keeps its own
/// navigation stack; tapping the current tab returns to its root.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      // Its ink top edge makes the bar one block with its tabs (BRIEF §10.1).
      bottomNavigationBar: DecoratedBox(
        // In front: the bar paints its own surface over a background.
        position: DecorationPosition.foreground,
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.ink, width: AppShape.chunkyBorder),
          ),
        ),
        child: NavigationBar(
          height: AppSpace.tabBarHeight,
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map),
              label: l10n.tab_map,
            ),
            NavigationDestination(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: const Icon(Icons.account_balance_wallet),
              label: l10n.tab_wallets,
            ),
            NavigationDestination(
              icon: const Icon(Icons.explore_outlined),
              selectedIcon: const Icon(Icons.explore),
              label: l10n.tab_explore,
            ),
            NavigationDestination(
              icon: const Icon(Icons.menu_book_outlined),
              selectedIcon: const Icon(Icons.menu_book),
              label: l10n.tab_glossary,
            ),
          ],
        ),
      ),
    );
  }
}
