import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/wallet/dca_plans.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The plan sheet on a fixed context with the real checks; saving only
/// records.
class FakePlanSetup extends PlanSetup {
  FakePlanSetup(this.fixed);
  final PlanContext fixed;
  final saved = <DcaPlan>[];

  @override
  Future<PlanSetupState> build(
    String assetId,
    String walletId, {
    Money? amount,
    DcaFrequency frequency = DcaFrequency.monthly,
  }) async => planSetupState(
    fixed,
    PlanForm(
      amount: amount?.amount.toString().replaceAll('.', ',') ?? '',
      frequency: frequency,
    ),
  );

  @override
  Future<DcaPlan?> submit() async {
    final s = planSetupState(
      fixed,
      state.value!.form.copyWith(submitted: true),
    );
    state = AsyncData(s);
    if (!s.canSubmit) return null;
    final plan = DcaPlan(
      id: 'p${saved.length + 1}',
      assetId: fixed.asset.id,
      amount: s.amount!,
      frequency: s.form.frequency,
      start: fixed.firstPurchase,
    );
    saved.add(plan);
    return plan;
  }
}

/// [asset] in the live wallet's rules, Thursday 8 October 2026 with the
/// market open: the first purchase is on Friday 9.
PlanContext planContext(Asset asset, {Money? fixedFee}) => PlanContext(
  asset: asset,
  walletId: 'live',
  finished: false,
  rules: TradingRules(
    fxFeeRate: Decimal.parse('0.0015'),
    fixedFee: fixedFee ?? const Money.zero(Currency.eur),
    fractionalShares: true,
  ),
  calendar: MarketCalendar(const {}),
  walletDay: DateTime.utc(2026, 10, 7),
  realTime: true,
  firstPurchase: DateTime.utc(2026, 10, 9),
);
