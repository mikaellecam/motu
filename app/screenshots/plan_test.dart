import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/wallet/dca_plans.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/presentation/features/dca/plan_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// « Investir chaque mois » on Apple in the live wallet, Thursday 8 October
// 2026 at 17:00 in Paris: the Nasdaq session is running, so the first
// purchase is on Friday 9.

final _context = PlanContext(
  asset: Asset(
    id: 'apple',
    symbol: 'AAPL',
    name: 'Apple',
    type: AssetType.stock,
    exchange: Exchange.nasdaq,
    currency: Currency.usd,
    region: 'us',
    listingDate: DateTime.utc(1980, 12, 12),
  ),
  walletId: 'live',
  finished: false,
  rules: TradingRules(
    fxFeeRate: Decimal.parse('0.0015'),
    fixedFee: const Money.zero(Currency.eur),
    fractionalShares: true,
  ),
  calendar: MarketCalendar(const {}),
  walletDay: DateTime.utc(2026, 10, 7),
  realTime: true,
  firstPurchase: DateTime.utc(2026, 10, 9),
);

class _Setup extends PlanSetup {
  @override
  Future<PlanSetupState> build(
    String assetId,
    String walletId, {
    Money? amount,
    DcaFrequency frequency = DcaFrequency.monthly,
  }) async => planSetupState(_context, PlanForm(frequency: frequency));
}

class _Host extends StatelessWidget {
  const _Host();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () =>
            showPlanSheet(context, assetId: 'apple', walletId: 'live'),
        child: const SizedBox.square(dimension: 44),
      ),
    ),
  );
}

void main() {
  screenshot(
    'm9-41-plan-sheet',
    const _Host(),
    size: const Size(390, 900),
    overrides: [planSetupProvider.overrideWith2((_) => _Setup())],
    act: (tester) async {
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '100');
      await tester.pumpAndSettle();
    },
  );
}
