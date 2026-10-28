import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/wallet/dca_plans.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chunky.dart';
import '../../../core/widgets/async_states.dart';
import '../../../domain/wallet/dca.dart';
import '../../widgets/asset_avatar.dart';
import '../order/order_sheet.dart' show headlineDecoration;

/// Opens the plan sheet for [assetId] in [walletId] (M9-41), prefilled with
/// the simulator's [amount] and [frequency]; once a plan is set up, says
/// when it buys first, with a way to the wallet that lists it.
Future<void> showPlanSheet(
  BuildContext context, {
  required String assetId,
  required String walletId,
  Money? amount,
  DcaFrequency frequency = DcaFrequency.monthly,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final l10n = AppLocalizations.of(context);
  final formats = Formats(Localizations.localeOf(context).languageCode);
  final plan = await showModalBottomSheet<DcaPlan>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) => PlanSheet(
        assetId: assetId,
        walletId: walletId,
        amount: amount,
        frequency: frequency,
        controller: controller,
      ),
    ),
  );
  if (plan == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.plan_done(formats.date(plan.start))),
      action: SnackBarAction(
        label: l10n.order_done_wallet,
        onPressed: () => router.push('/wallet/$walletId'),
      ),
    ),
  );
}

/// « Investir chaque mois »: the amount per purchase with its quick chips,
/// the frequency, the first purchase, and the button that sets it up.
class PlanSheet extends ConsumerStatefulWidget {
  const PlanSheet({
    super.key,
    required this.assetId,
    required this.walletId,
    this.amount,
    this.frequency = DcaFrequency.monthly,
    this.controller,
  });

  final String assetId;
  final String walletId;
  final Money? amount;
  final DcaFrequency frequency;
  final ScrollController? controller;

  @override
  ConsumerState<PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends ConsumerState<PlanSheet> {
  final _amount = TextEditingController();

  PlanSetupProvider get _provider => planSetupProvider(
    widget.assetId,
    widget.walletId,
    amount: widget.amount,
    frequency: widget.frequency,
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// A chip or the prefill rewrote the text: the field follows.
  void _sync(String text) {
    if (_amount.text != text) {
      _amount.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  Future<void> _submit() async {
    final plan = await ref.read(_provider.notifier).submit();
    if (plan == null || !mounted) return;
    Navigator.of(context).pop(plan);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    return switch (state) {
      AsyncValue(:final value?) => _form(context, value),
      AsyncValue(:final error?) => ErrorView(
        failure: error is Failure ? error : const ServerFailure(),
        onRetry: () => ref.invalidate(_provider),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(AppSpace.screenPadding),
        child: AsyncSkeleton(lines: 6),
      ),
    };
  }

  Widget _form(BuildContext context, PlanSetupState s) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final section = AppText.label.copyWith(color: AppColors.ink);
    final actions = ref.read(_provider.notifier);
    final c = s.context;
    final frequency = s.form.frequency.name;
    _sync(s.form.amount);

    String error(ValidationFailure e) => switch (e.code) {
      'amount_too_large' => l10n.dca_error_too_large(
        formats.money(e.params['max']! as Money),
      ),
      'amount_below_fees' => l10n.dca_error_fees(
        formats.money(e.params['fees']! as Money),
      ),
      'amount_below_one_share' => l10n.order_error_amount_below_one_share(
        formats.price(e.params['price']! as Price),
      ),
      _ => l10n.order_error_amount_not_positive,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            controller: widget.controller,
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screenPadding,
              0,
              AppSpace.screenPadding,
              AppSpace.x4,
            ),
            children: [
              Row(
                children: [
                  AssetAvatar(c.asset),
                  const SizedBox(width: AppSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.asset.name, style: AppText.title),
                        Text(l10n.plan_title, style: muted),
                      ],
                    ),
                  ),
                  ChunkyIconButton(
                    icon: Icons.close,
                    label: MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.x3),
              Text(l10n.plan_intro, style: text.bodyMedium),
              const SizedBox(height: AppSpace.x4),
              Text(l10n.plan_amount, style: section),
              const SizedBox(height: AppSpace.x2),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: AppText.figureLarge.copyWith(color: AppColors.ink),
                decoration: headlineDecoration(
                  label: l10n.plan_amount,
                  suffix: '€',
                  errors: [
                    if (s.showErrors)
                      for (final e in s.errors) error(e),
                  ],
                ),
                onChanged: actions.setAmount,
              ),
              const SizedBox(height: AppSpace.x3),
              Wrap(
                spacing: AppSpace.x2,
                runSpacing: AppSpace.x2,
                children: [
                  for (final euros in planQuickAmounts)
                    ChunkyChip(
                      label: formats.amount(
                        Decimal.fromInt(euros),
                        Currency.eur,
                        decimals: 0,
                      ),
                      onTap: () => actions.quick(euros),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.x4),
              Text(l10n.dca_frequency, style: section),
              const SizedBox(height: AppSpace.x2),
              ChunkySegmented(
                segments: [
                  (DcaFrequency.monthly, l10n.dca_monthly),
                  (DcaFrequency.weekly, l10n.dca_weekly),
                ],
                selected: s.form.frequency,
                onChanged: actions.setFrequency,
              ),
              const SizedBox(height: AppSpace.x4),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const ExcludeSemantics(
                            child: Icon(
                              Icons.event_repeat,
                              size: AppSpace.x5,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: AppSpace.x2),
                          Expanded(
                            child: Text(
                              l10n.plan_first(formats.date(c.firstPurchase)),
                              style: AppText.bodyStrong,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.x1),
                      Text(l10n.plan_then(frequency), style: muted),
                      const SizedBox(height: AppSpace.x2),
                      Text(l10n.plan_cash_note, style: muted),
                    ],
                  ),
                ),
              ),
              if (s.failure case final failure?)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.x2),
                  child: Text(
                    failureMessage(context, failure),
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.alertText,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // In reach whatever the sheet shows above it, as on the order sheet.
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screenPadding,
              AppSpace.x3,
              AppSpace.screenPadding,
              AppSpace.x3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChunkyButton(
                  label: switch (s.amount) {
                    final amount? when s.errors.isEmpty =>
                      l10n.plan_submit_amount(formats.money(amount), frequency),
                    _ => l10n.plan_submit(frequency),
                  },
                  onPressed: s.canSubmit || (!s.showErrors && !c.finished)
                      ? _submit
                      : null,
                ),
                const SizedBox(height: AppSpace.x2),
                Text(
                  l10n.order_fictional,
                  style: muted,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
