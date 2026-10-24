import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/order/order_tracker.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../domain/market/asset.dart';
import '../../../domain/wallet/order.dart';
import '../../../domain/wallet/order_matcher.dart';
import '../../../domain/wallet/position.dart';
import '../../widgets/asset_avatar.dart';

/// An order and its steps (BRIEF §4.6: sent → market opens → executed),
/// with « Annuler l'ordre » while it waits.
class OrderScreen extends ConsumerWidget {
  const OrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(orderTrackerProvider(orderId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.order_screen_title)),
      body: switch (state) {
        AsyncValue(:final value?) => ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.x3),
                child: OrderHeading(value.detail.order, value.asset),
              ),
            ),
            const SizedBox(height: AppSpace.x4),
            Card(
              // One node per step for screen readers.
              semanticContainer: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.x3),
                child: Column(children: _steps(context, value)),
              ),
            ),
            if (value.detail.status == OrderStatus.pending) ...[
              const SizedBox(height: AppSpace.x4),
              OutlinedButton(
                onPressed: () => _cancel(context, ref),
                child: Text(l10n.order_cancel),
              ),
            ],
          ],
        ),
        AsyncValue(:final error?) => Center(
          child: ErrorView(
            failure: error is Failure ? error : const ServerFailure(),
            onRetry: () => ref.invalidate(orderTrackerProvider(orderId)),
          ),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(AppSpace.screenPadding),
          child: AsyncSkeleton(lines: 6),
        ),
      },
    );
  }

  List<Widget> _steps(BuildContext context, OrderView v) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final order = v.detail.order;
    final status = v.detail.status;
    String at(DateTime t) => l10n.order_step_at(
      formats.date(t.toLocal()),
      formats.time(t.toLocal()),
    );
    final pending = status == OrderStatus.pending;
    final byUser = v.detail.cancelReason == CancelReason.byUser;

    final sent = _Step(
      l10n.order_step_sent,
      v.trip
          ? l10n.order_step_on(formats.date(order.createdAt))
          : at(order.createdAt),
      _Mark.done,
    );
    final middleMark = pending
        ? (v.opened ? _Mark.done : _Mark.current)
        : (byUser ? _Mark.upcoming : _Mark.done);
    final trigger = order.limitPrice ?? order.stopPrice;
    final middle = switch ((order.type, order.side, v.trip, v.opensAt)) {
      (OrderType.market, _, true, _) => _Step(
        l10n.order_step_trip,
        l10n.order_step_trip_note,
        middleMark,
      ),
      // Filled at the quote while its market was open.
      (OrderType.market, _, false, null) => null,
      (OrderType.market, _, false, final opensAt?) => _Step(
        l10n.order_step_opening,
        pending && v.opened ? l10n.order_step_opened : at(opensAt),
        middleMark,
      ),
      (final type, final side, _, _) => _Step(
        l10n.order_step_price,
        switch ((type, side)) {
          (OrderType.limit, Side.buy) => l10n.order_step_price_limit_buy,
          (OrderType.limit, Side.sell) => l10n.order_step_price_limit_sell,
          (_, Side.buy) => l10n.order_step_price_stop_buy,
          (_, Side.sell) => l10n.order_step_price_stop_sell,
        }(formats.price(trigger!)),
        middleMark,
      ),
    };
    final last = switch ((status, v.detail.fill)) {
      (OrderStatus.filled, final fill?) => _Step(
        l10n.order_step_filled,
        [
          l10n.order_step_filled_detail(
            _quantity(l10n, formats, v.asset, fill.quantity),
            formats.price(fill.price),
            formats.date(fill.date),
          ),
          l10n.order_step_fees(formats.money(fill.fees)),
        ].join('\n'),
        _Mark.done,
      ),
      (OrderStatus.cancelled, _) => _Step(
        l10n.order_step_cancelled,
        l10n.order_cancel_reason(v.detail.cancelReason?.name ?? ''),
        _Mark.done,
      ),
      _ => _Step(
        l10n.order_step_filled,
        null,
        v.opened ? _Mark.current : _Mark.upcoming,
      ),
    };
    return [sent, ?middle, last];
  }

  /// « Annuler l'ordre », once confirmed.
  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.order_cancel_title),
        content: Text(l10n.order_cancel_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.order_cancel_keep),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.order_cancel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(orderTrackerProvider(orderId).notifier).cancel();
    } on Failure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure))));
    }
  }
}

String _quantity(
  AppLocalizations l10n,
  Formats formats,
  Asset asset,
  Quantity quantity,
) {
  final form = formats.countForm(quantity.toDecimal());
  return switch (asset.type) {
    AssetType.stock => l10n.wallet_quantity_stock(
      form,
      formats.quantity(quantity),
    ),
    AssetType.etf => l10n.wallet_quantity_etf(form, formats.quantity(quantity)),
  };
}

/// « Achat · Apple » over its size and type: the order screen and the
/// wallet's pending orders.
class OrderHeading extends StatelessWidget {
  const OrderHeading(this.order, this.asset, {super.key});

  final Order order;
  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final size = switch (order.size) {
      AmountSize(:final amount) => formats.money(amount),
      QuantitySize(:final quantity) => _quantity(
        l10n,
        formats,
        asset,
        quantity,
      ),
    };
    final type = switch (order.type) {
      OrderType.market => l10n.order_type_market,
      OrderType.limit => l10n.order_type_limit,
      OrderType.stop => l10n.order_type_stop,
    };
    return Row(
      children: [
        AssetAvatar(asset),
        const SizedBox(width: AppSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.order_row_title(order.side.name, asset.name),
                style: text.titleMedium,
              ),
              Text(
                l10n.order_row_detail(size, type),
                style: text.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _Mark { done, current, upcoming }

class _Step extends StatelessWidget {
  const _Step(this.title, this.detail, this.mark);

  final String title;
  final String? detail;
  final _Mark mark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final reached = mark != _Mark.upcoming;
    return MergeSemantics(
      child: Semantics(
        label: l10n.order_step_state(mark.name),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.x2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(switch (mark) {
                _Mark.done => Icons.check_circle,
                _Mark.current => Icons.radio_button_checked,
                _Mark.upcoming => Icons.radio_button_unchecked,
              }, color: reached ? AppColors.primary : AppColors.muted),
              const SizedBox(width: AppSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall?.copyWith(
                        color: reached ? AppColors.ink : AppColors.muted,
                      ),
                    ),
                    if (detail case final detail?)
                      Text(
                        detail,
                        style: text.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
