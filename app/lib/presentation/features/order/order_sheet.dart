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

/// Opens the order sheet to [side] [assetId] in [walletId] (BRIEF §4.6); the
/// message to show once placed comes back, with the order placed.
Future<({String message, String orderId})?> showOrderSheet(
  BuildContext context, {
  required String assetId,
  required String walletId,
  required Side side,
}) => showModalBottomSheet<({String message, String orderId})>(
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
        .pop((message: _message(outcome, s), orderId: outcome.orderId));
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

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenPadding,
        0,
        AppSpace.screenPadding,
        AppSpace.x8,
      ),
      children: [
        Text(
          buy
              ? l10n.order_title_buy(c.asset.name)
              : l10n.order_title_sell(c.asset.name),
          style: AppText.title,
        ),
        Text(formats.price(c.price), style: muted),
        const SizedBox(height: AppSpace.x4),
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
        const SizedBox(height: AppSpace.x3),
        SegmentedButton<SizeMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: SizeMode.amount,
              label: Text(l10n.order_mode_amount),
            ),
            ButtonSegment(
              value: SizeMode.quantity,
              label: Text(l10n.order_mode_quantity),
            ),
          ],
          selected: {form.mode},
          onSelectionChanged: (selected) => actions.setMode(selected.first),
        ),
        const SizedBox(height: AppSpace.x3),
        TextField(
          key: ValueKey(form.mode),
          controller: _size,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: form.mode == SizeMode.amount
                ? l10n.order_amount_label
                : l10n.order_quantity_label,
            suffixText: form.mode == SizeMode.amount ? '€' : null,
          ),
          onChanged: form.mode == SizeMode.amount
              ? actions.setAmount
              : actions.setQuantity,
        ),
        const SizedBox(height: AppSpace.x2),
        Wrap(
          spacing: AppSpace.x2,
          children: [
            for (final choice in quickChoices(form.side, form.mode))
              ActionChip(
                label: Text(switch (choice) {
                  QuickAmount(:final euros) => formats.money(
                    Money(euros * 100, Currency.eur),
                  ),
                  QuickMax() => l10n.order_quick_max,
                  QuickShares(:final shares) => l10n.order_quick_shares(shares),
                  QuickHalf() => l10n.order_quick_half,
                  QuickAll() => l10n.order_quick_all,
                }),
                onPressed: () => actions.quick(choice),
              ),
          ],
        ),
        if (form.type != OrderType.market) ...[
          const SizedBox(height: AppSpace.x3),
          TextField(
            key: ValueKey(form.type),
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: form.type == OrderType.limit
                  ? l10n.order_price_limit(c.asset.currency.code)
                  : l10n.order_price_stop(c.asset.currency.code),
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
        if (s.showErrors)
          for (final error in s.errors)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.x2),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error(l10n, formats, error),
                  style: text.bodyMedium?.copyWith(color: AppColors.alertText),
                ),
              ),
            ),
        if (s.estimate case final e?) ...[
          const SizedBox(height: AppSpace.x4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.x4),
              child: Column(
                children: [
                  for (final (label, value) in [
                    (l10n.order_line_shares, formats.quantity(e.quantity)),
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
                          Expanded(child: Text(label, style: text.bodyMedium)),
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
          ),
        if (c.isTrip) ...[
          const SizedBox(height: AppSpace.x3),
          TextField(
            decoration: InputDecoration(labelText: l10n.order_reason),
            onChanged: actions.setReason,
          ),
        ],
        if (s.failure case final failure?)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.x2),
            child: Text(
              failureMessage(context, failure),
              style: text.bodyMedium?.copyWith(color: AppColors.alertText),
            ),
          ),
        const SizedBox(height: AppSpace.x4),
        ChunkyButton(
          label: buy ? l10n.asset_buy : l10n.asset_sell,
          onPressed: s.canSubmit || (!s.form.submitted && !c.finished)
              ? () => _submit(s)
              : null,
        ),
      ],
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
