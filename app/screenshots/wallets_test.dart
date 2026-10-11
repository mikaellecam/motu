import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/application/wallet/wallets_list.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/presentation/features/wallets/wallets_screen.dart';
import 'package:flutter/material.dart';

import 'screenshot.dart';

// The live wallet, two trips (one stopped automatically) and Mars 2020 to
// replay once its lesson is done. Values are illustrative.

Money eur(String s) => Money.book(Decimal.parse(s), Currency.eur);

WalletSummary trip(
  String id,
  String name,
  String difficulty,
  DateTime simDate,
  WalletStatus status,
) => WalletSummary(
  id: id,
  kind: WalletKind.trip,
  name: name,
  status: status,
  startDate: simDate,
  simDate: simDate,
  difficulty: difficulty,
  createdAt: DateTime.utc(2026, 10, 9),
);

WalletOverview valued(String start, String value) => buildOverview(
  wallet: WalletState(
    id: 'w',
    kind: WalletKind.live,
    name: 'w',
    startDate: DateTime.utc(2026, 10, 1),
    simDate: null,
    status: WalletStatus.active,
    params: WalletParams(
      rules: TradingRules(
        fxFeeRate: Decimal.zero,
        fixedFee: const Money.zero(Currency.eur),
        fractionalShares: true,
      ),
      monthlyContribution: const Money.zero(Currency.eur),
      stops: const StopConditions(),
    ),
    cash: eur(value),
    fills: const [],
    positions: const {},
    pendingOrders: const [],
    values: [
      DailyValue(
        date: DateTime.utc(2026, 10, 1),
        value: eur(start),
        flow: eur(start),
      ),
    ],
    livretMovements: const [],
    plans: const [],
  ),
  asOf: DateTime.utc(2026, 10, 8),
  assets: const {},
  prices: const {},
  fxRates: const {},
  livret: Decimal.zero,
);

void main() {
  final values = {
    'live': valued('50000', '51598.14'),
    'lehman': valued('10000', '9412.30'),
    'covid': valued('50000', '43870.55'),
  };
  screenshot(
    'm4-7-wallets',
    const WalletsScreen(),
    size: const Size(390, 1000),
    overrides: [
      walletsListProvider.overrideWith(
        (ref) async => WalletsList(
          live: WalletSummary(
            id: 'live',
            kind: WalletKind.live,
            name: 'live',
            status: WalletStatus.active,
            startDate: DateTime.utc(2026, 10, 1),
            simDate: null,
            difficulty: null,
            createdAt: DateTime.utc(2026, 10, 1),
          ),
          trips: [
            trip(
              'covid',
              'Covid',
              'decouverte',
              DateTime.utc(2020, 3, 23),
              WalletStatus.active,
            ),
            trip(
              'lehman',
              'Crise 2008',
              'realiste',
              DateTime.utc(2008, 10, 1),
              WalletStatus.stopped,
            ),
          ],
          suggestions: [
            BridgeSuggestion(
              'ae.march-2020',
              const Localized(
                'Mars 2020 : vendre ou tenir ?',
                'March 2020: sell or hold?',
              ),
              TripBridge(DateTime.utc(2020, 2, 18)),
            ),
          ],
        ),
      ),
      walletOverviewProvider.overrideWith((ref, id) async => values[id]!),
    ],
  );
}
