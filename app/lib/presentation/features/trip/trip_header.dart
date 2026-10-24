import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chunky.dart';

/// A trip's header (BRIEF §4.5), on its wallet and its automatic stop: the
/// clock, « Voyage « {name} » » with its [chip], the simulated [date] in
/// Baloo, then [actions] and the way out of the trip, back to the wallets.
/// Only the way out while the trip loads ([name] or [date] null). Being in
/// a trip shows in this content, never as a tint (§10.2).
class TripHeader extends StatelessWidget {
  const TripHeader({
    super.key,
    this.name,
    this.date,
    this.chip,
    this.chipColor = AppColors.surface,
    this.actions = const [],
  });

  final String? name;
  final DateTime? date;

  /// The trip's difficulty, or what stopped it; none when null.
  final String? chip;

  /// The chip's fill: neutral, or a token that means it (§10.2).
  final Color chipColor;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.screenPadding,
          vertical: AppSpace.x3,
        ),
        child: Row(
          children: [
            if ((name, date) case (final name?, final date?)) ...[
              ExcludeSemantics(
                child: Container(
                  width: AppSpace.minTarget,
                  height: AppSpace.minTarget,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(
                      AppShape.flatButtonRadius,
                    ),
                    border: Border.all(color: AppColors.ink, width: 2.5),
                  ),
                  child: const Icon(Icons.schedule, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: AppSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpace.x2,
                      runSpacing: AppSpace.x1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l10n.stop_trip_name(name),
                          style: AppText.label.copyWith(color: AppColors.muted),
                        ),
                        if (chip case final chip?)
                          DecoratedBox(
                            decoration: ShapeDecoration(
                              color: chipColor,
                              shape: const StadiumBorder(
                                side: BorderSide(
                                  color: AppColors.ink,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.x2,
                                vertical: 2,
                              ),
                              child: Text(chip, style: AppText.label),
                            ),
                          ),
                      ],
                    ),
                    Text(formats.date(date), style: AppText.title),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.x3),
            ] else
              const Spacer(),
            ...actions,
            ChunkyIconButton(
              icon: Icons.logout,
              label: l10n.trip_exit,
              onPressed: () => context.go('/wallets'),
            ),
          ],
        ),
      ),
    );
  }
}
