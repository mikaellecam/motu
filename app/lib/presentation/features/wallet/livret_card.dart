import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/wallet/livret_line.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../widgets/sign_color.dart';

/// The wallet's Livret A line (BRIEF §4.11): balance, this year's interest,
/// rate and ceiling, and « Verser » · « Retirer » unless the wallet is done
/// ([canMove] false). Nothing while it loads or when it cannot be read.
class LivretCard extends ConsumerWidget {
  const LivretCard({super.key, required this.walletId, required this.canMove});

  final String walletId;
  final bool canMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = ref.watch(livretLineProvider(walletId)).value;
    if (line == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);

    Future<void> move({required bool deposit}) async {
      final message = await showLivretSheet(
        context,
        walletId: walletId,
        deposit: deposit,
      );
      if (message != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.livret_title, style: text.titleMedium),
                ),
                Text(
                  formats.money(line.balance),
                  style: AppText.figure.copyWith(color: AppColors.ink),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.x1),
            Text(
              l10n.livret_interest(
                formats.amount(line.accrued, Currency.eur, signed: true),
              ),
              style: text.bodySmall?.copyWith(
                color: signColor(line.accrued, ratio: true),
              ),
            ),
            Text(
              l10n.livret_terms(
                formats.percent(line.rate),
                formats.money(line.ceiling),
              ),
              style: muted,
            ),
            if (canMove) ...[
              const SizedBox(height: AppSpace.x2),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => move(deposit: true),
                      child: Text(l10n.livret_deposit),
                    ),
                  ),
                  const SizedBox(width: AppSpace.x2),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: line.balance.isPositive
                          ? () => move(deposit: false)
                          : null,
                      child: Text(l10n.livret_withdraw),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// « Verser » or « Retirer »: the amount, what bounds it, and the message
/// to show once done.
Future<String?> showLivretSheet(
  BuildContext context, {
  required String walletId,
  required bool deposit,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: LivretSheet(walletId: walletId, deposit: deposit),
  ),
);

class LivretSheet extends ConsumerWidget {
  const LivretSheet({super.key, required this.walletId, required this.deposit});

  final String walletId;
  final bool deposit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = ref.watch(livretLineProvider(walletId)).value;
    if (line == null) return const SizedBox.shrink();
    final provider = livretTransferProvider(walletId, deposit);
    final form = ref.watch(provider);
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final room = line.balance < line.ceiling
        ? line.ceiling - line.balance
        : const Money.zero(Currency.eur);

    String message(ValidationFailure e) => switch (e.code) {
      'insufficient_cash' => l10n.livret_error_cash(
        formats.money(e.params['cash']! as Money),
      ),
      'livret_ceiling' => l10n.livret_error_ceiling(
        formats.money(line.ceiling),
        formats.money(e.params['room']! as Money),
      ),
      'livret_insufficient_balance' => l10n.livret_error_balance(
        formats.money(e.params['balance']! as Money),
      ),
      _ => l10n.order_error_amount_not_positive,
    };

    Future<void> submit() async {
      final moved = await ref.read(provider.notifier).submit(line);
      if (moved == null || !context.mounted) return;
      Navigator.of(context).pop(
        (deposit ? l10n.livret_done_deposit : l10n.livret_done_withdraw)(
          formats.money(moved),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenPadding,
        0,
        AppSpace.screenPadding,
        AppSpace.screenPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            deposit ? l10n.livret_deposit_title : l10n.livret_withdraw_title,
            style: AppText.title,
          ),
          const SizedBox(height: AppSpace.x2),
          Text(
            deposit
                ? l10n.livret_available_cash(formats.money(line.availableCash))
                : l10n.livret_available_balance(formats.money(line.balance)),
            style: text.bodyMedium,
          ),
          // The room left, unless the error below already says it.
          if (deposit && !form.errors.any((e) => e.code == 'livret_ceiling'))
            Text(
              l10n.livret_error_ceiling(
                formats.money(line.ceiling),
                formats.money(room),
              ),
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            ),
          const SizedBox(height: AppSpace.x3),
          TextField(
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.order_amount_label,
              suffixText: '€',
            ),
            onChanged: (value) =>
                ref.read(provider.notifier).setAmount(value, line),
            onSubmitted: (_) => submit(),
          ),
          for (final e in form.errors)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.x1),
              child: Text(
                message(e),
                style: text.bodySmall?.copyWith(color: AppColors.alertText),
              ),
            ),
          if (form.failure case final failure?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.x1),
              child: Text(
                failureMessage(context, failure),
                style: text.bodySmall?.copyWith(color: AppColors.alertText),
              ),
            ),
          const SizedBox(height: AppSpace.x2),
          Text(
            deposit ? l10n.livret_note_deposit : l10n.livret_note_withdraw,
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpace.x3),
          FilledButton(
            onPressed: submit,
            child: Text(deposit ? l10n.livret_deposit : l10n.livret_withdraw),
          ),
        ],
      ),
    );
  }
}
