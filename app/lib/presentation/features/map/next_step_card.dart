import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/companion/companion.dart';
import '../../../application/learning/next_step_card.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chunky.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../domain/learning/next_step.dart';
import '../companion/companion_card.dart';

/// The one action the map recommends (BRIEF §4.2), as `nextStep` picks it;
/// it follows the user's progress as it happens. Nothing before the
/// questionnaire, nor while it loads.
class NextStepCard extends ConsumerWidget {
  const NextStepCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(nextStepViewProvider).value;
    if (view == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final title = view.title?.of(language);
    final card = switch (view.step) {
      PlayNode(:final nodeId) => (
        l10n.next_step_lesson,
        title,
        l10n.next_step_play,
        ChunkyButtonKind.primary,
        () => context.push('/node/$nodeId'),
      ),
      DoMission(:final nodeId) => (
        l10n.next_step_mission,
        title,
        l10n.next_step_mission_go,
        ChunkyButtonKind.progress,
        () => context.push('/node/$nodeId'),
      ),
      ContinueTrip(:final walletId) => (
        l10n.next_step_trip,
        view.tripName,
        l10n.next_step_trip_go,
        ChunkyButtonKind.primary,
        () => context.push('/wallet/$walletId'),
      ),
      OpenLiveWallet() => (
        l10n.next_step_wallet,
        l10n.next_step_wallet_title,
        l10n.next_step_wallet_go,
        ChunkyButtonKind.primary,
        () => context.push('/wallet/${WalletRepository.liveWalletId}'),
      ),
      ReadMoment() => switch (view.moment) {
        final moment? => (
          l10n.companion_kicker,
          companionCopy(
            l10n,
            Formats(language),
            moment,
            asset:
                ref
                    .watch(companionNamesProvider)
                    .value
                    ?.assets[moment.assetId] ??
                moment.assetId ??
                '',
          ).$1,
          l10n.next_step_read,
          ChunkyButtonKind.progress,
          () => showCompanionSheet(context, moment),
        ),
        null => null,
      },
    };
    if (card == null) return const SizedBox.shrink();
    final (kicker, name, action, kind, go) = card;
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(kicker, style: AppText.caption.copyWith(color: AppColors.muted)),
          if (name != null) ...[
            const SizedBox(height: AppSpace.x1),
            Text(name, style: AppText.title.copyWith(color: AppColors.ink)),
          ],
          const SizedBox(height: AppSpace.x3),
          ChunkyButton(label: action, kind: kind, onPressed: go),
        ],
      ),
    );
  }
}
