import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/clock/simulation_clock.dart';
import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/market_calendar.dart';
import '../../domain/wallet/dca.dart';
import '../../domain/wallet/dca_simulator.dart' show validateDcaAmount;
import '../../domain/wallet/order.dart';
import '../../domain/wallet/position.dart' show Side;
import '../../domain/wallet/wallet.dart';
import '../asset/asset_page.dart' show assetOverviewProvider;
import '../providers.dart';
import '../trip/trip_wizard.dart' show parseAmount;
import 'wallet_providers.dart';

part 'dca_plans.g.dart';

/// The plan sheet (M9-41): « Investir chaque mois » sets up a DCA plan for
/// an asset in a wallet, which the trip engine runs (BRIEF §4.5, step 2).

typedef AssetOverviewPrice = (Price, Decimal);

/// What the sheet knows when it opens.
final class PlanContext {
  const PlanContext({
    required this.asset,
    required this.walletId,
    required this.finished,
    required this.rules,
    required this.calendar,
    required this.walletDay,
    required this.realTime,
    required this.firstPurchase,
    this.sharePrice,
    this.fxRate,
  });

  final Asset asset;
  final String walletId;

  /// A finished trip takes no plan.
  final bool finished;
  final TradingRules rules;

  /// [asset]'s exchange, from the wallet's day on.
  final MarketCalendar calendar;

  /// The last day the wallet booked: the live wallet's last session valued,
  /// a trip's day.
  final DateTime walletDay;

  /// The live wallet, or a trip at today: a plan goes by the real time.
  final bool realTime;

  /// The first purchase of a plan set up as the sheet opened.
  final DateTime firstPurchase;

  /// A wallet of whole shares: the asset's latest price and its rate to the
  /// euro, so an amount that buys no share is refused, as an order's is.
  /// Null when shares can be split, or when the price cannot be read.
  final Price? sharePrice;
  final Decimal? fxRate;

  /// The first purchase of a plan set up at [now] (`firstPurchaseDay`).
  DateTime firstPurchaseAt(DateTime now) => firstPurchaseDay(
    calendar: calendar,
    exchange: asset.exchange,
    walletDay: walletDay,
    placedAt: realTime ? now : null,
  );
}

/// The plan as written in the sheet.
final class PlanForm {
  const PlanForm({
    this.amount = '',
    this.frequency = DcaFrequency.monthly,
    this.submitted = false,
  });

  final String amount;
  final DcaFrequency frequency;

  /// The button was pressed: every error shows.
  final bool submitted;

  PlanForm copyWith({
    String? amount,
    DcaFrequency? frequency,
    bool? submitted,
  }) => PlanForm(
    amount: amount ?? this.amount,
    frequency: frequency ?? this.frequency,
    submitted: submitted ?? this.submitted,
  );
}

/// Everything the sheet shows.
final class PlanSetupState {
  const PlanSetupState({
    required this.context,
    required this.form,
    required this.amount,
    required this.errors,
    this.failure,
  });

  final PlanContext context;
  final PlanForm form;

  /// The amount per purchase; null while it cannot be read.
  final Money? amount;

  /// From `validateDcaAmount`.
  final List<ValidationFailure> errors;
  final Failure? failure;

  bool get showErrors => form.submitted || form.amount.trim().isNotEmpty;

  bool get canSubmit => !context.finished && amount != null && errors.isEmpty;
}

/// The quick amount chips, in euros.
const planQuickAmounts = [50, 100, 200];

PlanSetupState planSetupState(
  PlanContext c,
  PlanForm form, {
  Failure? failure,
}) {
  final parsed = parseAmount(form.amount);
  final amount = parsed == null ? null : Money.book(parsed, Currency.eur);
  return PlanSetupState(
    context: c,
    form: form,
    amount: amount,
    errors: switch (validateDcaAmount(
      amount ?? const Money.zero(Currency.eur),
      rules: c.rules,
    )) {
      final errors when errors.isNotEmpty => errors,
      _ => [
        if ((c.sharePrice, c.fxRate) case (final price?, final rate?)
            when quantityAt(
              Order(
                id: '',
                assetId: c.asset.id,
                side: Side.buy,
                type: OrderType.market,
                size: AmountSize(amount!),
                createdAt: c.walletDay,
              ),
              price,
              rate,
              c.rules,
            ).isZero)
          ValidationFailure('amount_below_one_share', {'price': price}),
      ],
    },
    failure: failure,
  );
}

/// Sets up a plan for [assetId] in [walletId]; the simulator opens it with
/// the [amount] and [frequency] it simulated.
@riverpod
class PlanSetup extends _$PlanSetup {
  @override
  Future<PlanSetupState> build(
    String assetId,
    String walletId, {
    Money? amount,
    DcaFrequency frequency = DcaFrequency.monthly,
  }) async {
    final wallets = ref.watch(walletRepositoryProvider);
    final market = ref.watch(marketRepositoryProvider);
    final now = ref.watch(liveClockProvider).now();
    final wallet = await wallets.load(walletId);
    final live = wallet.kind == WalletKind.live;
    final asOf = live ? now : HistoricalClock(wallet.simDate!).now();
    final asset = (await market.assets(asOf: asOf))
        .where((a) => a.id == assetId)
        .firstOrNull;
    if (asset == null) throw const NotFoundFailure();
    // The live wallet's day is the last session it valued; a trip's, its
    // simulated day. A trip at today goes by the real time, as its orders
    // do (BRIEF §4.5).
    final walletDay = live ? wallet.values.last.date : wallet.simDate!;
    final realTime = live || wallet.reachedToday;
    final calendar = await market.calendar(
      {asset.exchange},
      fromYear: walletDay.year,
      toYear: (realTime ? now.toUtc() : walletDay).year + 1,
    );
    // Whole shares only: the latest price, read as the asset page does.
    final whole = !wallet.params.rules.fractionalShares;
    final overview = whole
        ? await ref
              .watch(assetOverviewProvider(assetId, walletId).future)
              .then<AssetOverviewPrice?>((o) => (o.price, o.fxRate))
              .catchError((Object _) => null)
        : null;
    final context = PlanContext(
      asset: asset,
      walletId: walletId,
      finished: wallet.status == WalletStatus.finished,
      rules: wallet.params.rules,
      calendar: calendar,
      walletDay: walletDay,
      realTime: realTime,
      firstPurchase: firstPurchaseDay(
        calendar: calendar,
        exchange: asset.exchange,
        walletDay: walletDay,
        placedAt: realTime ? now : null,
      ),
      sharePrice: overview?.$1,
      fxRate: overview?.$2,
    );
    return planSetupState(
      context,
      PlanForm(
        amount: amount == null ? '' : _number(amount.amount),
        frequency: frequency,
      ),
    );
  }

  void _edit(PlanForm Function(PlanForm form) change) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(planSetupState(current.context, change(current.form)));
  }

  void setAmount(String text) => _edit((f) => f.copyWith(amount: text));
  void quick(int euros) =>
      _edit((f) => f.copyWith(amount: _number(Decimal.fromInt(euros))));
  void setFrequency(DcaFrequency frequency) =>
      _edit((f) => f.copyWith(frequency: frequency));

  bool _saving = false;

  /// Saves the plan once valid; it buys first on the first session that
  /// opens after now (`firstPurchaseDay`), which may be later than the
  /// sheet said if a session opened while it was open.
  Future<DcaPlan?> submit() async {
    final current = state.value;
    if (current == null || _saving) return null;
    final submitted = planSetupState(
      current.context,
      current.form.copyWith(submitted: true),
    );
    state = AsyncData(submitted);
    final amount = submitted.amount;
    if (!submitted.canSubmit || amount == null) return null;
    final c = submitted.context;
    _saving = true;
    try {
      final plan = await ref
          .read(walletRepositoryProvider)
          .addPlan(
            c.walletId,
            assetId: c.asset.id,
            amount: amount,
            frequency: submitted.form.frequency,
            start: c.firstPurchaseAt(ref.read(liveClockProvider).now()),
          );
      // The wallet lists it, and « Avancer jusqu'à… » no longer says a
      // contribution stays as cash.
      ref.invalidate(walletOverviewProvider(c.walletId));
      return plan;
    } on Failure catch (failure) {
      state = AsyncData(planSetupState(c, submitted.form, failure: failure));
      return null;
    } finally {
      _saving = false;
    }
  }
}

/// « Arrêter » on a plan of [walletId]'s « Versements programmés ».
@riverpod
class PlanActions extends _$PlanActions {
  @override
  void build(String walletId) {}

  /// The plan places no more purchases; those it made stay, and one still
  /// pending stays an order the user can cancel (M9-41).
  Future<void> stop(String planId) async {
    await ref.read(walletRepositoryProvider).stopPlan(planId);
    ref.invalidate(walletOverviewProvider(walletId));
  }
}

/// A decimal as typed in the field: a comma, no trailing zeros.
String _number(Decimal value) => value.toString().replaceAll('.', ',');
