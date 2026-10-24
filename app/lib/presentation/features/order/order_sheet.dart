import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/content.dart';
import '../../../application/order/order_ticket.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/wallet/order.dart';
import '../../../domain/wallet/position.dart';
import '../../widgets/term_text.dart';
import '../glossary/term_sheet.dart';

/// Opens the order sheet to [side] [assetId] in [walletId] (BRIEF §4.6); what
/// placing did comes back, with its message.
Future<({String message, OrderOutcome outcome})?> showOrderSheet(
  BuildContext context, {
  required String assetId,
  required String walletId,
  required Side side,
}) => showModalBottomSheet<({String message, OrderOutcome outcome})>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.9,
    maxChildSize: 0.95,
    builder: (context, controller) => OrderSheet(
      assetId: assetId,
      walletId: walletId,
      side: side,
      controller: controller,
    ),
  ),
);

/// The order sheet: type, amount or quantity with its quick chips, the
/// price for limit and stop, every validation error, the fees summary, the
/// pre-trade coach, when it will go, and « Acheter » or « Vendre ».
class OrderSheet extends ConsumerStatefulWidget {
  const OrderSheet({
    super.key,
    required this.assetId,
    required this.walletId,
    required this.side,
    this.controller,
  });

  final String assetId;
  final String walletId;
  final Side side;
  final ScrollController? controller;

  @override
  ConsumerState<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends ConsumerState<OrderSheet> {
  final _size = TextEditingController();
  final _price = TextEditingController();

  OrderTicketProvider get _provider =>
      orderTicketProvider(widget.assetId, widget.walletId, widget.side);

  @override
  void dispose() {
    _size.dispose();
    _price.dispose();
    super.dispose();
  }

  /// A chip or a type change rewrote the text: the field follows.
  void _sync(TextEditingController controller, String text) {
    if (controller.text != text) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  Future<void> _setType(OrderType type) async {
    final term = await ref.read(_provider.notifier).setType(type);
    if (term != null && mounted) await showTermSheet(context, term);
  }

  Future<void> _submit(TicketState s) async {
    final outcome = await ref.read(_provider.notifier).submit();
    if (outcome == null || !mounted) return;
    Navigator.of(context)
        .pop((message: _message(outcome, s), outcome: outcome));
  }

  String _message(OrderOutcome outcome, TicketState s) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final name = s.context.asset.name;
    return switch (outcome) {
      OrderExecuted(:final fill) =>
        (fill.side == Side.buy ? l10n.order_done_buy : l10n.order_done_sell)(
          formats.quantity(fill.quantity),
          name,
          formats.price(fill.price),
        ),
      OrderSent(trip: true) => l10n.order_sent_trip,
      OrderSent(:final opensAt?) => l10n.order_sent_opening(
        formats.date(opensAt.toLocal()),
        formats.time(opensAt.toLocal()),
      ),
      OrderSent() => l10n.order_sent_waiting,
    };
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

  Widget _form(BuildContext context, TicketState s) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final formats = Formats(language);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final actions = ref.read(_provider.notifier);
    final form = s.form;
    final c = s.context;
    final buy = form.side == Side.buy;
    _sync(_size, form.mode == SizeMode.amount ? form.amount : form.quantity);
    _sync(_price, form.price);
    final terms =
        ref
            .watch(contentPackProvider(actionsEtfIsland))
            .value
            ?.glossary
            .map((id, t) => MapEntry(id, t.title)) ??
        const {};

    // Where each error shows: a price error under the price, the rest
    // under the amount.
    const priceCodes = {'limit_price_not_positive', 'stop_price_not_positive'};
    final shown = s.showErrors ? s.errors : const <ValidationFailure>[];
    final sizeErrors = [
      for (final e in shown)
        if (!priceCodes.contains(e.code)) _error(l10n, formats, e),
    ];
    final priceErrors = [
      for (final e in shown)
        if (priceCodes.contains(e.code)) _error(l10n, formats, e),
    ];
    final amountMode = form.mode == SizeMode.amount;
    final section = AppText.label.copyWith(color: AppColors.ink);

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          buy
                              ? l10n.order_title_buy(c.asset.name)
                              : l10n.order_title_sell(c.asset.name),
                          style: AppText.title,
                        ),
                        Text(formats.price(c.price), style: muted),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.x4),
              Text(l10n.order_type_label, style: section),
              const SizedBox(height: AppSpace.x2),
              SegmentedButton<OrderType>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: OrderType.market,
                    label: Text(l10n.order_type_market),
                  ),
                  ButtonSegment(
                    value: OrderType.limit,
                    label: Text(l10n.order_type_limit),
                  ),
                  ButtonSegment(
                    value: OrderType.stop,
                    label: Text(l10n.order_type_stop),
                  ),
                ],
                selected: {form.type},
                onSelectionChanged: (selected) => _setType(selected.first),
              ),
              const SizedBox(height: AppSpace.x4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      amountMode
                          ? l10n.order_mode_amount
                          : l10n.order_mode_quantity,
                      style: section,
                    ),
                  ),
                  SegmentedButton<SizeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: SizeMode.amount,
                        label: Text(l10n.order_mode_amount_short),
                      ),
                      ButtonSegment(
                        value: SizeMode.quantity,
                        label: Text(l10n.order_mode_quantity_short),
                      ),
                    ],
                    selected: {form.mode},
                    onSelectionChanged: (selected) =>
                        actions.setMode(selected.first),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.x2),
              TextField(
                key: ValueKey(form.mode),
                controller: _size,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: AppText.figureLarge.copyWith(color: AppColors.ink),
                decoration: _headline(
                  label: amountMode
                      ? l10n.order_amount_label
                      : l10n.order_quantity_label,
                  suffix: amountMode ? '€' : null,
                  available: buy
                      ? l10n.order_available_cash(
                          formats.money(c.availableCash),
                        )
                      : l10n.order_available_shares(
                          formats.countForm(c.availableQuantity.toDecimal()),
                          formats.quantity(c.availableQuantity),
                        ),
                  errors: sizeErrors,
                ),
                onChanged: amountMode ? actions.setAmount : actions.setQuantity,
              ),
              const SizedBox(height: AppSpace.x3),
              Wrap(
                spacing: AppSpace.x2,
                runSpacing: AppSpace.x2,
                children: [
                  for (final choice in quickChoices(form.side, form.mode))
                    ActionChip(
                      label: Text(switch (choice) {
                        QuickAmount(:final euros) => formats.amount(
                          Decimal.fromInt(euros),
                          Currency.eur,
                          decimals: 0,
                        ),
                        QuickMax() => l10n.order_quick_max,
                        QuickShares(:final shares) => l10n.order_quick_shares(
                          shares,
                        ),
                        QuickHalf() => l10n.order_quick_half,
                        QuickAll() => l10n.order_quick_all,
                      }),
                      onPressed: () => actions.quick(choice),
                    ),
                ],
              ),
              if (form.type != OrderType.market) ...[
                const SizedBox(height: AppSpace.x4),
                TextField(
                  key: ValueKey(form.type),
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: form.type == OrderType.limit
                        ? l10n.order_price_limit(c.asset.currency.code)
                        : l10n.order_price_stop(c.asset.currency.code),
                    error: priceErrors.isEmpty ? null : _Errors(priceErrors),
                  ),
                  onChanged: actions.setPrice,
                ),
                const SizedBox(height: AppSpace.x1),
                Text(switch ((form.type, buy)) {
                  (OrderType.limit, true) => l10n.order_hint_limit_buy,
                  (OrderType.limit, false) => l10n.order_hint_limit_sell,
                  (_, true) => l10n.order_hint_stop_buy,
                  (_, false) => l10n.order_hint_stop_sell,
                }, style: muted),
                Text(l10n.order_gtc, style: muted),
              ],
              if (s.estimate case final e?) ...[
                const SizedBox(height: AppSpace.x4),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.x4),
                    child: Column(
                      children: [
                        for (final (label, value) in [
                          (
                            l10n.order_line_shares,
                            formats.quantity(e.quantity),
                          ),
                          (l10n.order_line_value, formats.money(e.notional)),
                          (l10n.order_line_fees, formats.money(e.fees)),
                          (
                            buy
                                ? l10n.order_line_total_buy
                                : l10n.order_line_total_sell,
                            formats.money(e.total),
                          ),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpace.x1,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(label, style: text.bodyMedium),
                                ),
                                Text(
                                  value,
                                  style: AppText.figure.copyWith(
                                    color: AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: AppSpace.x1),
                        Text(l10n.order_estimate_note, style: muted),
                      ],
                    ),
                  ),
                ),
              ],
              if (s.weight case final w?) ...[
                const SizedBox(height: AppSpace.x4),
                ChunkyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.order_coach_label,
                        style: AppText.label.copyWith(color: AppColors.primary),
                      ),
                      const SizedBox(height: AppSpace.x1),
                      Text(
                        l10n.order_coach(
                          c.asset.name,
                          formats.percent(w.after, decimals: 0),
                          formats.percent(w.before, decimals: 0),
                        ),
                        style: AppText.bodyStrong,
                      ),
                      if (s.overThreshold) ...[
                        const SizedBox(height: AppSpace.x2),
                        TermText(
                          l10n.order_coach_over(
                            formats.percent(c.threshold, decimals: 0),
                            '{{concentration|${l10n.order_coach_term}}}',
                          ),
                          terms: terms,
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.alertText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.x4),
              if (c.isTrip)
                Text(l10n.order_trip_next, style: muted)
              else if (!c.marketOpen &&
                  form.type == OrderType.market &&
                  c.nextOpen != null)
                Text(
                  l10n.order_market_closed(
                    c.asset.exchange.name,
                    formats.date(c.nextOpen!.toLocal()),
                    formats.time(c.nextOpen!.toLocal()),
                  ),
                  style: muted,
                )
              else if (c.offline &&
                  form.type == OrderType.market &&
                  c.nextOpen != null)
                Text(
                  l10n.order_offline_next(
                    formats.date(c.nextOpen!.toLocal()),
                    formats.time(c.nextOpen!.toLocal()),
                  ),
                  style: muted,
                ),
              if (c.isTrip) ...[
                const SizedBox(height: AppSpace.x3),
                TextField(
                  // Keeps the reason typed when the limit price above it comes
                  // or goes.
                  key: const ValueKey('order-reason'),
                  decoration: InputDecoration(labelText: l10n.order_reason),
                  onChanged: actions.setReason,
                ),
              ],
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
        // In reach whatever the sheet shows above it (§10.1: a flat money
        // button).
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
                FilledButton(
                  onPressed: s.canSubmit || (!s.showErrors && !c.finished)
                      ? () => _submit(s)
                      : null,
                  child: Text(switch (s.estimate) {
                    final e? when amountMode =>
                      (buy ? l10n.order_buy_for : l10n.order_sell_for)(
                        formats.money(e.notional),
                      ),
                    _ => buy ? l10n.asset_buy : l10n.asset_sell,
                  }),
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

  /// The amount or quantity as the sheet's headline: a big figure in a box,
  /// what is available under it, or why it cannot go.
  InputDecoration _headline({
    required String label,
    required String? suffix,
    required String available,
    required List<String> errors,
  }) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppShape.flatCardRadius),
      borderSide: BorderSide(color: color, width: 2),
    );
    return InputDecoration(
      // Said by screen readers; shown only while the box is empty.
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      labelStyle: AppText.body.copyWith(color: AppColors.muted),
      suffixText: suffix,
      suffixStyle: AppText.title.copyWith(color: AppColors.ink),
      helperText: available,
      helperMaxLines: 2,
      error: errors.isEmpty ? null : _Errors(errors),
      enabledBorder: border(AppColors.ink),
      focusedBorder: border(AppColors.primary),
      errorBorder: border(AppColors.alertText),
      focusedErrorBorder: border(AppColors.alertText),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.x4,
        vertical: AppSpace.x3,
      ),
    );
  }

  String _error(AppLocalizations l10n, Formats formats, ValidationFailure e) =>
      switch (e.code) {
        'amount_not_positive' => l10n.order_error_amount_not_positive,
        'quantity_not_positive' => l10n.order_error_quantity_not_positive,
        'quantity_not_whole' => l10n.order_error_quantity_not_whole,
        'limit_price_not_positive' => l10n.order_error_limit_price_not_positive,
        'stop_price_not_positive' => l10n.order_error_stop_price_not_positive,
        'asset_unavailable' => l10n.order_error_asset_unavailable,
        'amount_below_one_share' => l10n.order_error_amount_below_one_share(
          formats.price(e.params['price']! as Price),
        ),
        'insufficient_cash' => l10n.order_error_insufficient_cash(
          formats.money(e.params['cash']! as Money),
        ),
        'insufficient_quantity' => l10n.order_error_insufficient_quantity(
          formats.quantity(e.params['held']! as Quantity),
        ),
        'amount_below_fees' => l10n.order_error_amount_below_fees(
          formats.money(e.params['fees']! as Money),
        ),
        _ => e.code,
      };
}

/// Why a field cannot go, each reason with a warning icon: never colour
/// alone.
class _Errors extends StatelessWidget {
  const _Errors(this.messages);

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: AppColors.alertText);
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.x1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: AppSpace.x4 + AppSpace.x1,
                      color: AppColors.alertText,
                    ),
                  ),
                  const SizedBox(width: AppSpace.x1),
                  Expanded(child: Text(message, style: style)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
