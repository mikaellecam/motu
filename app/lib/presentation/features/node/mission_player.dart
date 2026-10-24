import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/learning/missions.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chunky.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../domain/learning/missions.dart';
import '../../widgets/term_text.dart';
import 'node_screen.dart';

/// `mission` (BRIEF §4.3): what to do in the sandbox and a way there. It
/// completes by itself when the wallet shows it, never by a button.
class MissionPlayer extends ConsumerWidget {
  const MissionPlayer({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;

    return playerState(
      ref.watch(missionViewProvider(nodeId)),
      onRetry: () => ref.invalidate(missionViewProvider(nodeId)),
      data: (view) {
        final (go, place) = switch (view.mission.place) {
          MissionPlace.explorer => (
            l10n.mission_go_explorer,
            '/explore?wallet=${WalletRepository.liveWalletId}',
          ),
          MissionPlace.wallet => (
            l10n.mission_go_wallet,
            '/wallet/${WalletRepository.liveWalletId}',
          ),
        };
        return ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            LessonCard(
              label: nodeTypeName(l10n, view.node.type),
              headline: view.node.title.of(language),
              children: [
                TermText(
                  view.mission.goal.of(language),
                  terms: view.terms,
                  style: text.bodyLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.x4),
            ChunkyCard(
              child: Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: AppSpace.minTarget,
                        height: AppSpace.minTarget,
                        decoration: BoxDecoration(
                          color: view.done
                              ? AppColors.progress
                              : AppColors.line,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.ink,
                            width: AppShape.chunkyBorder,
                          ),
                        ),
                        child: Icon(
                          view.done ? Icons.check : Icons.flag_outlined,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.x3),
                    Expanded(
                      child: Text(
                        view.done ? l10n.mission_done : l10n.mission_auto,
                        style: view.done ? AppText.bodyStrong : text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.x6),
            if (view.done)
              LessonEnd(node: view.node)
            else
              ChunkyButton(label: go, onPressed: () => context.go(place)),
          ],
        );
      },
    );
  }
}
