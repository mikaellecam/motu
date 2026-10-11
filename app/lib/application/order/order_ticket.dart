import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../domain/learning/profile_rules.dart';
import '../../domain/market/asset.dart';
import '../../domain/wallet/order.dart';
import '../../domain/wallet/order_matcher.dart';
import '../../domain/wallet/order_ticket.dart';
import '../../domain/wallet/position.dart';
import '../../domain/wallet/validation.dart';
import '../../domain/wallet/wallet.dart';
import '../asset/asset_page.dart';
import '../learning/content.dart';
import '../providers.dart';
import '../trip/trip_wizard.dart' show parseAmount;
import '../wallet/wallet_providers.dart';
import '../wallet/wallets_list.dart';

part 'order_ticket.g.dart';

/// The order sheet (BRIEF §4.6): what is being written, checked by
/// `validateOrder` as it changes, priced, weighed by the pre-trade coach,
/// then placed.

/// Whether the order is written as a € amount or as a number of shares.
enum SizeMode { amount, quantity }

/// What the sheet knows when it opens: the wallet's rules and room, the
/// asset's price, the coach's threshold, and when the market opens.
final class TicketContext {
  const TicketContext({
    required this.asset,
    required this.walletId,
    required this.isTrip,
    required this.finished,
    required this.rules,
    required this.price,
    required this.fxRate,
    required this.availableCash,
    required this.availableQuantity,
    required this.positionValue,
    required this.walletTotal,
    required this.threshold,
    required this.asOf,
    this.marketOpen = false,
    this.nextOpen,
  });

  final Asset asset;
  final String walletId;
  final bool isTrip;

  /// A finished trip takes no order (M5-5).
  final bool finished;
  final TradingRules rules;

  /// The last price at the wallet's clock.
  final Price price;
  final Decimal fxRate;

  /// Cash minus what pending buys hold back.
  final Money availableCash;

  /// The position minus what pending sells hold back.
  final Quantity availableQuantity;
  final Decimal positionValue;
  final Decimal walletTotal;

  /// The profile's concentration threshold (§4.12).
  final Decimal threshold;
  final DateTime asOf;

  /// Live wallet only: the asset's market is open now, or opens [nextOpen].
  final bool marketOpen;
  final DateTime? nextOpen;
}

/// The order as written in the sheet.
final class TicketForm {
  const TicketForm({
    required this.side,
    this.type = OrderType.market,
    this.mode = SizeMode.amount,
    this.amount = '',
    this.quantity = '',
    this.price = '',
    this.reason = '',
    this.submitted = false,
  });

  final Side side;
  final OrderType type;
  final SizeMode mode;
  final String amount;
  final String quantity;

  /// The limit or stop price, in the asset's currency.
  final String price;

  /// Trip only: why, saved to the journal.
  final String reason;

  /// « Valider » was pressed: every error shows.
  final bool submitted;

  TicketForm copyWith({
    OrderType? type,
    SizeMode? mode,
    String? amount,
    String? quantity,
    String? price,
    String? reason,
    bool? submitted,
  }) => TicketForm(
    side: side,
    type: type ?? this.type,
    mode: mode ?? this.mode,
    amount: amount ?? this.amount,
    quantity: quantity ?? this.quantity,
    price: price ?? this.price,
    reason: reason ?? this.reason,
    submitted: submitted ?? this.submitted,
  );
}

/// Everything the sheet shows.
final class TicketState {
  const TicketState({
    required this.context,
    required this.form,
    required this.order,
    required this.errors,
    required this.estimate,
    required this.weight,
    this.submitting = false,
    this.failure,
  });

  final TicketContext context;
  final TicketForm form;

  /// Null while the input cannot be read as an order.
  final Order? order;

  /// From `validateOrder`; shown once there is input or after « Valider ».
  final List<ValidationFailure> errors;
  final OrderEstimate? estimate;
  final ({Decimal before, Decimal after})? weight;
  final bool submitting;
  final Failure? failure;

  bool get showErrors =>
      form.submitted ||
      (form.mode == SizeMode.amount ? form.amount : form.quantity)
          .trim()
          .isNotEmpty;

  /// The coach flags a weight above the profile's threshold (never blocks).
  bool get overThreshold => weight != null && weight!.after > context.threshold;

  bool get canSubmit =>
      !context.finished && order != null && errors.isEmpty && !submitting;
}

/// What placing did, for the message the sheet leaves behind.
sealed class OrderOutcome {
  const OrderOutcome();
}

/// Live, market open: filled at the quote.
final class OrderExecuted extends OrderOutcome {
  const OrderExecuted(this.fill);
  final Fill fill;
}

/// Pending: until the market opens ([opensAt], live), the trip moves on
/// ([trip]), or else the price is reached (limit, stop).
final class OrderSent extends OrderOutcome {
  const OrderSent({this.opensAt, this.trip = false});
  final DateTime? opensAt;
  final bool trip;
}

@riverpod
class OrderTicket extends _$OrderTicket {
  @override
  Future<TicketState> build(String assetId, String walletId, Side side) async {
    final wallets = ref.watch(walletRepositoryProvider);
    final market = ref.watch(marketRepositoryProvider);
    final profiles = ref.watch(profileRepositoryProvider);
    final now = ref.watch(liveClockProvider).now();
    final assetF = ref.watch(assetOverviewProvider(assetId, walletId).future)
      ..ignore();
    final walletF = ref.watch(walletOverviewProvider(walletId).future)
      ..ignore();
    final overview = await assetF;
    final wallet = await walletF;
    final state = await wallets.load(walletId);
    final profile = await profiles.load();

    final price = overview.price;
    var reservedSells = const Quantity.zero();
    for (final o in state.pendingOrders) {
      if (o.assetId == assetId && o.side == Side.sell) {
        reservedSells += quantityToReserve(
          o,
          rules: state.params.rules,
          referencePrice: price,
          fxRate: overview.fxRate,
        );
      }
    }
    final held = state.positions[assetId]?.quantity ?? const Quantity.zero();
    final live = state.kind == WalletKind.live;
    var open = false;
    DateTime? nextOpen;
    if (live) {
      final year = now.toUtc().year;
      final calendar = await market.calendar(
        {overview.asset.exchange},
        fromYear: year,
        toYear: year + 1,
      );
      open = calendar.isOpen(overview.asset.exchange, now);
      if (!open) nextOpen = calendar.nextOpen(overview.asset.exchange, now);
    }
    final context = TicketContext(
      asset: overview.asset,
      walletId: walletId,
      isTrip: !live,
      finished: state.status == WalletStatus.finished,
      rules: state.params.rules,
      price: price,
      fxRate: overview.fxRate,
      availableCash: wallet.availableCash,
      availableQuantity: held - reservedSells,
      positionValue: overview.position?.value ?? Decimal.zero,
      walletTotal: wallet.total,
      threshold: profile == null
          ? Decimal.parse('0.40')
          : momentThresholds(profile).concentration,
      asOf: overview.asOf,
      marketOpen: open,
      nextOpen: nextOpen,
    );
    return _derive(context, TicketForm(side: side));
  }

  TicketState _derive(TicketContext c, TicketForm form, {Failure? failure}) =>
      ticketState(
        c,
        form,
        orderId:
            'o-${ref.read(liveClockProvider).now().microsecondsSinceEpoch}',
        failure: failure,
      );

  void _edit(TicketForm Function(TicketForm form) change) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(_derive(current.context, change(current.form)));
  }

  /// Picks the order type. The first time limit or stop is picked, returns
  /// the glossary term to open (BRIEF §4.6: soft gate), when the pack has
  /// it and it was never opened.
  Future<String?> setType(OrderType type) async {
    _edit((f) => f.copyWith(type: type, price: ''));
    final term = switch (type) {
      OrderType.limit => 'ordre-limite',
      OrderType.stop => 'ordre-stop',
      OrderType.market => null,
    };
    if (term == null) return null;
    final pack = await ref.read(contentPackProvider(actionsEtfIsland).future);
    if (!pack.glossary.containsKey(term)) return null;
    final seen = await ref.read(glossaryRepositoryProvider).watch().first;
    return seen.containsKey(term) ? null : term;
  }

  void setMode(SizeMode mode) => _edit((f) => f.copyWith(mode: mode));
  void setAmount(String text) => _edit((f) => f.copyWith(amount: text));
  void setQuantity(String text) => _edit((f) => f.copyWith(quantity: text));
  void setPrice(String text) => _edit((f) => f.copyWith(price: text));
  void setReason(String text) => _edit((f) => f.copyWith(reason: text));

  /// A quick amount chip: a € amount (or the most the cash allows), a number
  /// of shares, or half or all of what can be sold.
  void quick(QuickChoice choice) {
    final c = state.value?.context;
    if (c == null) return;
    String number(Decimal v) => v.toString().replaceAll('.', ',');
    _edit(
      (f) => switch (choice) {
        QuickAmount(:final euros) => f.copyWith(
          mode: SizeMode.amount,
          amount: number(Decimal.fromInt(euros)),
        ),
        QuickMax() => f.copyWith(
          mode: SizeMode.amount,
          amount: number(
            maxBuyAmount(
              c.availableCash,
              assetCurrency: c.asset.currency,
              rules: c.rules,
            ).amount,
          ),
        ),
        QuickShares(:final shares) => f.copyWith(
          mode: SizeMode.quantity,
          quantity: number(Decimal.fromInt(shares)),
        ),
        QuickHalf() => f.copyWith(
          mode: SizeMode.quantity,
          quantity: number(
            halfOf(
              c.availableQuantity,
              fractional: c.rules.fractionalShares,
            ).toDecimal(),
          ),
        ),
        QuickAll() => f.copyWith(
          mode: SizeMode.quantity,
          quantity: number(c.availableQuantity.toDecimal()),
        ),
      },
    );
  }

  /// Places the order once valid (BRIEF §4.6). Live, a market order with
  /// its market open fills at the quote now; any other order waits. A trip
  /// order waits for the trip to move on, its reason in the journal.
  Future<OrderOutcome?> submit() async {
    final current = state.value;
    if (current == null) return null;
    final submitted = _derive(
      current.context,
      current.form.copyWith(submitted: true),
    );
    state = AsyncData(submitted);
    final order = submitted.order;
    if (!submitted.canSubmit || order == null) return null;
    final c = submitted.context;
    final wallets = ref.read(walletRepositoryProvider);
    try {
      final OrderOutcome outcome;
      if (c.isTrip) {
        await wallets.placeTripOrder(
          c.walletId,
          order,
          simDate: c.asOf,
          reason: submitted.form.reason.trim(),
        );
        outcome = const OrderSent(trip: true);
      } else if (c.marketOpen && order.type == OrderType.market) {
        final match = fillAtQuote(
          order,
          c.price,
          at: ref.read(liveClockProvider).now(),
          rules: c.rules,
          fxRate: c.fxRate,
          spendableCash: c.availableCash,
          heldQuantity: c.availableQuantity,
        );
        switch (match) {
          case Filled(:final fill):
            await wallets.executeOrder(c.walletId, order, fill);
            outcome = OrderExecuted(fill);
          case Cancelled() || Unfilled():
            // Validation checked the same rules: only a race lands here.
            state = AsyncData(
              _derive(c, submitted.form, failure: const ServerFailure()),
            );
            return null;
        }
      } else {
        await wallets.placeOrder(c.walletId, order);
        outcome = OrderSent(
          opensAt: order.type == OrderType.market ? c.nextOpen : null,
        );
      }
      ref
        ..invalidate(walletOverviewProvider(c.walletId))
        ..invalidate(assetOverviewProvider(c.asset.id, c.walletId))
        ..invalidate(walletsListProvider);
      return outcome;
    } on Failure catch (failure) {
      state = AsyncData(_derive(c, submitted.form, failure: failure));
      return null;
    }
  }
}

/// The quick amount chips (decided 2026-10-11): 100 / 500 / 1 000 € and
/// « Max » to buy in euros, 1 / 5 / 10 shares in quantity, « La moitié » and
/// « Tout » to sell.
sealed class QuickChoice {
  const QuickChoice();
}

final class QuickAmount extends QuickChoice {
  const QuickAmount(this.euros);
  final int euros;
}

final class QuickMax extends QuickChoice {
  const QuickMax();
}

final class QuickShares extends QuickChoice {
  const QuickShares(this.shares);
  final int shares;
}

final class QuickHalf extends QuickChoice {
  const QuickHalf();
}

final class QuickAll extends QuickChoice {
  const QuickAll();
}

/// The chips the sheet offers for [side] and [mode].
List<QuickChoice> quickChoices(Side side, SizeMode mode) =>
    switch ((side, mode)) {
      (Side.buy, SizeMode.amount) => const [
        QuickAmount(100),
        QuickAmount(500),
        QuickAmount(1000),
        QuickMax(),
      ],
      (Side.buy, SizeMode.quantity) => const [
        QuickShares(1),
        QuickShares(5),
        QuickShares(10),
      ],
      (Side.sell, _) => const [QuickHalf(), QuickAll()],
    };

/// The sheet's state for [form] in [c]: the order it reads as (named
/// [orderId]), its problems from `validateOrder`, its estimate and the
/// coach's weights.
TicketState ticketState(
  TicketContext c,
  TicketForm form, {
  required String orderId,
  Failure? failure,
}) {
  final order = _order(c, form, orderId);
  final estimate = order == null
      ? null
      : estimateOrder(
          order,
          referencePrice: c.price,
          fxRate: c.fxRate,
          rules: c.rules,
        );
  return TicketState(
    context: c,
    form: form,
    order: order,
    errors: order == null
        ? [
            ValidationFailure(
              form.mode == SizeMode.amount
                  ? 'amount_not_positive'
                  : 'quantity_not_positive',
            ),
          ]
        : validateOrder(
            order,
            rules: c.rules,
            referencePrice: c.price,
            fxRate: c.fxRate,
            availableCash: c.availableCash,
            availableQuantity: c.availableQuantity,
          ),
    estimate: estimate,
    weight: estimate == null
        ? null
        : weightChange(
            positionValue: c.positionValue,
            walletTotal: c.walletTotal,
            side: form.side,
            notional: estimate.notional,
            fees: estimate.fees,
          ),
    failure: failure,
  );
}

/// The form as an order; null while its size or price cannot be read.
Order? _order(TicketContext c, TicketForm form, String orderId) {
  final OrderSize size;
  switch (form.mode) {
    case SizeMode.amount:
      final amount = parseAmount(form.amount);
      if (amount == null) return null;
      size = AmountSize(Money.book(amount, Currency.eur));
    case SizeMode.quantity:
      final quantity = parseAmount(form.quantity);
      if (quantity == null) return null;
      size = QuantitySize(Quantity.truncate(quantity));
  }
  Price? trigger;
  if (form.type != OrderType.market) {
    final price = parseAmount(form.price);
    trigger = Price(price ?? Decimal.zero, c.asset.currency);
  }
  return Order(
    id: orderId,
    assetId: c.asset.id,
    side: form.side,
    type: form.type,
    size: size,
    limitPrice: form.type == OrderType.limit ? trigger : null,
    stopPrice: form.type == OrderType.stop ? trigger : null,
    createdAt: c.asOf,
  );
}
