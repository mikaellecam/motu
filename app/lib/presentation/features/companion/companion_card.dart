import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/companion/companion.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chunky.dart';
import '../../../data/repositories/companion_repository.dart';
import '../../../domain/companion/rules.dart';
import '../glossary/term_sheet.dart';

/// A companion moment (BRIEF §4.12): what happened, in words that describe
/// and never prescribe, its glossary terms and lesson, and « J'ai compris ».
/// [onDone] runs once it is dismissed (a sheet closes).
class CompanionCard extends ConsumerWidget {
  const CompanionCard(this.moment, {super.key, this.onDone});

  final ActiveMoment moment;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final namesState = ref.watch(companionNamesProvider);
    // Not the asset's id for a frame: the names first, unless they fail.
    if (namesState.isLoading && !namesState.hasValue) {
      return const SizedBox.shrink();
    }
    final names = namesState.value;
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final formats = Formats(language);
    final text = Theme.of(context).textTheme;
    final (title, body) = companionCopy(
      l10n,
      formats,
      moment,
      asset: names?.assets[moment.assetId] ?? moment.assetId ?? '',
    );
    final lesson = names?.lessons[moment.rule.lesson]?.of(language);

    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.companion_kicker,
            style: AppText.caption.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpace.x1),
          Text(title, style: AppText.titleSmall),
          const SizedBox(height: AppSpace.x2),
          Text(body, style: text.bodyMedium),
          const SizedBox(height: AppSpace.x2),
          Wrap(
            spacing: AppSpace.x2,
            runSpacing: AppSpace.x1,
            children: [
              for (final term in moment.rule.glossary)
                if (names?.terms[term] case final title?)
                  ChunkyChip(
                    label: title.of(language),
                    onTap: () => showTermSheet(context, term),
                  ),
            ],
          ),
          if (lesson != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.push('/node/${moment.rule.lesson}'),
                child: Text(l10n.companion_lesson(lesson)),
              ),
            ),
          const SizedBox(height: AppSpace.x2),
          ChunkyButton(
            label: l10n.companion_got_it,
            kind: ChunkyButtonKind.progress,
            onPressed: () async {
              await ref.read(companionActionsProvider.notifier).dismiss(moment);
              onDone?.call();
            },
          ),
        ],
      ),
    );
  }
}

/// [moment]'s title and body. Ratios show without sign where the words
/// already say which way (« a perdu 15 % »), with one where they do not.
(String, String) companionCopy(
  AppLocalizations l10n,
  Formats formats,
  ActiveMoment moment, {
  required String asset,
}) {
  final p = moment.params;
  String size(String key) => formats.percent((p[key]! as Decimal).abs());
  String price(String key) => formats.price(p[key]! as Price);
  return switch (moment.rule) {
    CompanionRule.firstLoss => (
      l10n.companion_first_loss_title,
      l10n.companion_first_loss_body(asset),
    ),
    CompanionRule.positionDrop => (
      l10n.companion_position_drop_title(asset),
      l10n.companion_position_drop_body(asset, size('drop')),
    ),
    CompanionRule.portfolioDrawdown => (
      l10n.companion_portfolio_drawdown_title,
      l10n.companion_portfolio_drawdown_body(size('drawdown')),
    ),
    CompanionRule.concentration => (
      l10n.companion_concentration_title,
      l10n.companion_concentration_body(asset, size('weight')),
    ),
    CompanionRule.idleCash => (
      l10n.companion_idle_cash_title,
      l10n.companion_idle_cash_body(size('cashWeight')),
    ),
    CompanionRule.panicSell => (
      l10n.companion_panic_sell_title,
      l10n.companion_panic_sell_body(asset, price('sellPrice')),
    ),
    CompanionRule.panicSellFollowUp => (
      l10n.companion_panic_sell_followup_title,
      l10n.companion_panic_sell_followup_body(
        asset,
        price('sellPrice'),
        price('priceNow'),
        formats.percent(p['change']! as Decimal, signed: true),
      ),
    ),
    CompanionRule.fxSwing => (
      l10n.companion_fx_swing_title,
      l10n.companion_fx_swing_body(size('move'), size('exposure')),
    ),
  };
}

/// The card on its own, from the map's next-step card; it closes once read.
Future<void> showCompanionSheet(BuildContext context, ActiveMoment moment) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenPadding,
          0,
          AppSpace.screenPadding,
          AppSpace.screenPadding,
        ),
        child: CompanionCard(moment, onDone: () => Navigator.of(sheet).pop()),
      ),
    );

/// The oldest moment not read yet of [walletId] (about [assetId] on an asset
/// page), with space below; nothing when there is none.
class WalletCompanionCard extends ConsumerWidget {
  const WalletCompanionCard({super.key, required this.walletId, this.assetId});

  final String walletId;
  final String? assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moment = ref.watch(walletMomentProvider(walletId, assetId)).value;
    if (moment == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.x4),
      child: CompanionCard(moment, key: ValueKey(moment.id)),
    );
  }
}
