import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/application/wallet/wallets_list.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:finance_companion/presentation/features/wallets/wallets_screen.dart';
import 'package:flutter/material.dart';

import 'screenshot.dart';

// The live wallet, three trips (one running, one stopped automatically, one
// over) and Mars 2020 to replay once its lesson is done (artboard Wallets-A).
// Values are illustrative.

Money eur(String s) => Money.book(Decimal.parse(s), Currency.eur);

WalletSummary trip(
  String id,
  String name,
  String difficulty,
  DateTime simDate,
  WalletStatus status, {
  DateTime? start,
}) => WalletSummary(
  id: id,
  kind: WalletKind.trip,
  name: name,
  status: status,
  startDate: start ?? simDate,
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
    'live': valued('50000', '51534.60'),
    'covid': valued('10000', '9712.40'),
    'lehman': valued('10000', '9412.30'),
    'bubble': valued('2000', '1236.00'),
  };
  final islands = {
    'live': [
      ('world', '1', '1'),
      ('apple', '0.5', '0.5'),
      ('asml', '0.3', '0.3'),
      ('coca-cola', '0.25', '0'),
    ],
    'covid': [('world', '1', '1'), ('sp500', '0.6', '0.6')],
    'lehman': [('sp500', '1', '1'), ('coca-cola', '0.7', '0.7')],
    'bubble': const <(String, String, String)>[],
  };
  screenshot(
    'm4-7-wallets',
    const WalletsScreen(),
    size: const Size(390, 980),
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
              'Covid 2020',
              'realiste',
              DateTime.utc(2020, 2, 24),
              WalletStatus.active,
            ),
            trip(
              'lehman',
              'Crise 2008',
              'realiste',
              DateTime.utc(2008, 10, 1),
              WalletStatus.stopped,
            ),
            trip(
              'bubble',
              'Bulle internet',
              'serre',
              DateTime.utc(2003, 3, 11),
              WalletStatus.finished,
              start: DateTime.utc(2000, 3, 10),
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
      // Each wallet's own city: the live one with a buy still waiting.
      walletIslandProvider.overrideWith(
        (ref, args) async => [
          for (final (asset, height, built) in islands[args.$1]!)
            IslandBuilding(
              asset,
              height: Decimal.parse(height),
              built: Decimal.parse(built),
            ),
        ],
      ),
    ],
  );
}
