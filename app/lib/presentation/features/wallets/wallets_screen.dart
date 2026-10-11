import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/wallet/wallet_providers.dart';
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
import '../../widgets/sign_color.dart';

/// The Portefeuille tab (BRIEF §3): the live wallet, the time trips, a new
/// trip, and the lessons the user can replay as a trip.
class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(walletsListProvider);
    final list = state.value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tab_wallets)),
      body: switch (list) {
        final list? => ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            if (list.live case final live?) _WalletCard(live),
            const SizedBox(height: AppSpace.x6),
            Text(l10n.wallets_trips_title, style: text.titleMedium),
            const SizedBox(height: AppSpace.x2),
            if (list.trips.isEmpty)
              Text(
                l10n.wallets_no_trips,
                style: text.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            for (final trip in list.trips) ...[
              _WalletCard(trip),
              const SizedBox(height: AppSpace.x3),
            ],
            const SizedBox(height: AppSpace.x3),
            OutlinedButton.icon(
              onPressed: () => context.push('/wallets/new'),
              icon: const Icon(Icons.add),
              label: Text(l10n.wallets_new_trip),
            ),
            if (list.suggestions.isNotEmpty) ...[
              const SizedBox(height: AppSpace.x6),
              Text(l10n.wallets_suggestions_title, style: text.titleMedium),
              for (final s in list.suggestions) ...[
                const SizedBox(height: AppSpace.x3),
                _SuggestionCard(s),
              ],
            ],
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

/// A wallet with its value, loaded on its own: one wallet that cannot be
/// valued (offline, nothing cached) leaves the others alone.
class _WalletCard extends ConsumerWidget {
  const _WalletCard(this.wallet);
  final WalletSummary wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final overview = ref.watch(walletOverviewProvider(wallet.id)).value;
    final live = wallet.kind == WalletKind.live;
    final difficulty = wallet.difficulty;
    final ratio = overview?.changeRatio;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/wallet/${wallet.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  live ? l10n.wallet_live_name : wallet.name,
                  if (!live && difficulty != null)
                    _difficulty(l10n, difficulty),
                ].join(' · '),
                style: text.titleMedium,
              ),
              Text(
                live
                    ? l10n.wallets_live_subtitle
                    : l10n.wallets_trip_date(
                        formats.date(wallet.simDate ?? wallet.startDate),
                      ),
                style: muted,
              ),
              const SizedBox(height: AppSpace.x2),
              if (overview == null)
                const SizedBox(height: AppSpace.x8)
              else ...[
                Text(
                  formats.amount(overview.total, Currency.eur),
                  style: AppText.figure.copyWith(color: AppColors.ink),
                ),
                Text(
                  l10n.wallet_change_since_start(
                    [
                      formats.amount(
                        overview.change,
                        Currency.eur,
                        signed: true,
                      ),
                      if (ratio != null)
                        '(${formats.percent(ratio, signed: true)})',
                    ].join(' '),
                  ),
                  style: text.bodySmall?.copyWith(
                    color: signColor(overview.change),
                  ),
                ),
              ],
              switch (wallet.status) {
                WalletStatus.active => const SizedBox.shrink(),
                WalletStatus.stopped => Padding(
                  padding: const EdgeInsets.only(top: AppSpace.x2),
                  child: Text(
                    l10n.wallets_status_stopped,
                    style: text.bodySmall?.copyWith(color: AppColors.alertText),
                  ),
                ),
                WalletStatus.finished => Padding(
                  padding: const EdgeInsets.only(top: AppSpace.x2),
                  child: Text(l10n.wallets_status_finished, style: muted),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

/// A completed lesson's bridge: replay its moment as a trip.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard(this.suggestion);
  final BridgeSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final bridge = suggestion.bridge;
    final query = {
      'step': '1',
      'date': bridge.date.toIso8601String().substring(0, 10),
      'difficulty': ?bridge.difficulty,
      'from': suggestion.nodeId,
    };

    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(suggestion.title.of(language), style: text.titleMedium),
          Text(
            l10n.wallets_suggestion_date(formats.date(bridge.date)),
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpace.x3),
          ChunkyButton(
            label: l10n.wallets_suggestion_go,
            onPressed: () => context.push(
              Uri(path: '/wallets/new', queryParameters: query).toString(),
            ),
          ),
        ],
      ),
    );
  }
}
