import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/wallet/wallet_providers.dart';
import '../../../application/trip/trip_wizard.dart';
import '../../../application/wallet/wallets_list.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../domain/wallet/wallet.dart';
import '../../widgets/section_title.dart';
import '../../widgets/sign_color.dart';
import '../node/node_screen.dart' show LessonCard;

/// The Portefeuille tab (BRIEF §3, artboard Wallets-A): the live wallet, the
/// time trips, the lessons the user can replay as a trip, a new trip, and the
/// DCA simulator.
class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final muted = AppText.caption.copyWith(color: AppColors.muted);
    final state = ref.watch(walletsListProvider);
    final list = state.value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.wallets_title)),
      body: switch (list) {
        final list? => ListView(
          // The intro right under the title, as one header.
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenPadding,
            0,
            AppSpace.screenPadding,
            AppSpace.screenPadding,
          ),
          children: [
            Text(l10n.wallets_intro, style: muted),
            const SizedBox(height: AppSpace.x4),
            if (list.live case final live?) _WalletRow(live),
            MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: SectionTitle(
                      l10n.wallets_trips_title,
                      top: AppSpace.x6,
                    ),
                  ),
                  if (list.trips.isNotEmpty)
                    Text('${list.trips.length}', style: muted),
                ],
              ),
            ),
            if (list.trips.isEmpty)
              Text(
                l10n.wallets_no_trips,
                style: AppText.body.copyWith(color: AppColors.muted),
              ),
            for (final (i, trip) in list.trips.indexed) ...[
              if (i > 0) const SizedBox(height: AppSpace.x4),
              _WalletRow(trip),
            ],
            for (final s in list.suggestions) ...[
              const SizedBox(height: AppSpace.x4),
              _SuggestionCard(s),
            ],
            const SizedBox(height: AppSpace.x4),
            ChunkyButton(
              icon: Icons.add,
              label: l10n.wallets_new_trip,
              onPressed: () => context.push('/wallets/new'),
            ),
            const SizedBox(height: AppSpace.x6),
            // The sandbox's other tool (BRIEF §4.10).
            _Row(
              icon: Icons.event_repeat_outlined,
              onTap: () => context.push('/tools/dca'),
              lines: [
                Text(l10n.wallets_dca_title, style: AppText.bodyStrong),
                Text(l10n.wallets_dca_body, style: muted),
              ],
              trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
            ),
          ],
        ),
        null when state.hasError => Center(
          child: ErrorView(
            failure: state.error is Failure
                ? state.error! as Failure
                : const StorageFailure(),
            onRetry: () => ref.invalidate(walletsListProvider),
          ),
        ),
        null => const Padding(
          padding: EdgeInsets.all(AppSpace.screenPadding),
          child: AsyncSkeleton(lines: 4),
        ),
      },
    );
  }
}

Formats _formats(BuildContext context) =>
    Formats(Localizations.localeOf(context).languageCode);

String _difficulty(AppLocalizations l10n, String id) => switch (id) {
  'decouverte' => l10n.difficulty_decouverte,
  'realiste' => l10n.difficulty_realiste,
  'serre' => l10n.difficulty_serre,
  'sur-mesure' => l10n.difficulty_sur_mesure,
  final other => other,
};

/// A flat row of the list: an icon tile (neutral, §10.2: no token means the
/// artboard's tints), what it is, then [trailing]. The whole row opens
/// [onTap].
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.lines,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final List<Widget> lines;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Row(
          children: [
            Container(
              width: AppSpace.minTarget,
              height: AppSpace.minTarget,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(AppShape.flatButtonRadius),
              ),
              child: Icon(icon, color: AppColors.ink),
            ),
            const SizedBox(width: AppSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpace.x1,
                children: lines,
              ),
            ),
            if (trailing case final trailing?) ...[
              const SizedBox(width: AppSpace.x3),
              trailing,
            ],
          ],
        ),
      ),
    ),
  );
}

/// « En direct », a trip's difficulty: a neutral pill beside a name.
class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const ShapeDecoration(
      color: AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: AppColors.ink, width: 2)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2, vertical: 2),
      child: Text(label, style: AppText.label),
    ),
  );
}

/// A wallet with its value, loaded on its own: one wallet that cannot be
/// valued (offline, nothing cached) leaves the others alone.
class _WalletRow extends ConsumerWidget {
  const _WalletRow(this.wallet);
  final WalletSummary wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final muted = AppText.caption.copyWith(color: AppColors.muted);
    final overview = ref.watch(walletOverviewProvider(wallet.id)).value;
    final live = wallet.kind == WalletKind.live;
    final difficulty = wallet.difficulty;
    final chip = live
        ? l10n.wallets_live_chip
        : difficulty == null
        ? null
        : _difficulty(l10n, difficulty);
    final (status, stopped) = switch (live ? null : tripLine(wallet)) {
      null => (l10n.wallets_live_subtitle, false),
      TripOngoing(:final day, :final stopped) => (
        l10n.wallets_trip_ongoing(formats.date(day)),
        stopped,
      ),
      TripOver(:final from, oneMonth: true) => (
        l10n.wallets_trip_over_month(formats.month(from)),
        false,
      ),
      TripOver(:final from, :final to) => (
        l10n.wallets_trip_over(
          formats.elision(formats.month(from)),
          formats.month(from),
          formats.month(to),
        ),
        false,
      ),
    };

    return _Row(
      icon: live
          ? Icons.account_balance_wallet_outlined
          : Icons.calendar_today_outlined,
      onTap: () => context.push('/wallet/${wallet.id}'),
      lines: [
        Wrap(
          spacing: AppSpace.x2,
          runSpacing: AppSpace.x1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              live ? l10n.wallets_live_name : wallet.name,
              style: AppText.bodyStrong,
            ),
            if (chip != null) _Chip(chip),
          ],
        ),
        Text(status, style: muted),
        if (stopped)
          Text(
            l10n.wallets_status_stopped,
            style: AppText.caption.copyWith(color: AppColors.alertText),
          ),
      ],
      trailing: switch (overview) {
        null => null,
        final o => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formats.amount(o.total, Currency.eur),
              style: AppText.figure.copyWith(color: AppColors.ink),
            ),
            // The amount when nothing was put in to measure a % against.
            if (o.changeRatio case final ratio?)
              Text(
                formats.percent(ratio, signed: true),
                style: AppText.label.copyWith(
                  color: signColor(ratio, ratio: true),
                ),
              )
            else
              Text(
                formats.amount(o.change, Currency.eur, signed: true),
                style: AppText.label.copyWith(color: signColor(o.change)),
              ),
          ],
        ),
      },
    );
  }
}

/// A completed lesson's bridge: replay its moment as a trip, in a companion
/// card.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard(this.suggestion);
  final BridgeSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    return LessonCard(
      label: l10n.wallets_suggestion_kicker,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: suggestion.title.of(language),
                style: AppText.bodyStrong,
              ),
              TextSpan(text: ' ${l10n.wallets_suggestion_body}'),
            ],
          ),
          style: AppText.body,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: ChunkyButton(
            kind: ChunkyButtonKind.progress,
            label: l10n.wallets_suggestion_go,
            onPressed: () => context.push(
              bridgeLocation(suggestion.bridge, suggestion.nodeId),
            ),
          ),
        ),
      ],
    );
  }
}
