import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/order/order_ticket.dart';
import 'package:finance_companion/application/order/order_tracker.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/presentation/features/order/order_done_screen.dart';
import 'package:flutter/material.dart';

import 'screenshot.dart';

// The live wallet after a buy (M9-34): 2 000 € of Apple sent on Wednesday
// evening, the Nasdaq closed until Thursday 15 h 30; the same buy filled at
// once at the 336,67 $ quote; and a first ETF, which completes « Ton premier
// ETF ». The island greened by the lessons done; values are illustrative.

Asset _asset(String id, String symbol, String name, AssetType type) => Asset(
  id: id,
  symbol: symbol,
  name: name,
  type: type,
  exchange: Exchange.nasdaq,
  currency: Currency.usd,
  region: type == AssetType.etf ? 'world' : 'us',
  listingDate: DateTime.utc(2000),
);

final _apple = _asset('apple', 'AAPL', 'Apple', AssetType.stock);
final _world = _asset('world', 'ACWI', 'iShares MSCI ACWI ETF', AssetType.etf);

Order _buy(Asset asset, int euros, DateTime at) => Order(
  id: 'o',
  assetId: asset.id,
  side: Side.buy,
  type: OrderType.market,
  size: AmountSize(Money(euros * 100, Currency.eur)),
  createdAt: at,
);

Fill _fill(Asset asset, String quantity, String price, String fees) => Fill(
  orderId: 'o',
  assetId: asset.id,
  side: Side.buy,
  date: DateTime.utc(2026, 10, 7),
  quantity: Quantity.truncate(Decimal.parse(quantity)),
  price: Price(Decimal.parse(price), Currency.usd),
  fxRate: Decimal.parse('0.8547'),
  fees: Money.book(Decimal.parse(fees), Currency.eur),
);

class _Tracker extends OrderTracker {
  _Tracker(this.view);
  final OrderView view;

  @override
  Future<OrderView> build(String orderId) async => view;
}

void main() {
  Decimal d(String s) => Decimal.parse(s);
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );
  const lessons = [
    'ae.livret-vs-etf',
    'ae.fees-toy',
    'ae.apple-vs-world-2022',
    'ae.march-2020',
  ];

  void shot(
    String name, {
    required OrderDone done,
    required OrderView view,
    required Map<String, Decimal> held,
    Map<String, Decimal> pending = const {},
    List<String> completed = lessons,
  }) => screenshot(
    name,
    OrderDoneScreen(walletId: WalletRepository.liveWalletId, done: done),
    size: const Size(390, 880),
    overrides: [
      orderTrackerProvider.overrideWith2((_) => _Tracker(view)),
      walletIslandProvider.overrideWith(
        (ref, id) async => islandBuildings(held: held, pending: pending),
      ),
      contentPackProvider(actionsEtfIsland).overrideWith((ref) async => pack),
      lesBasesPack,
      completedNodesProvider.overrideWith(
        (ref) => Stream.value(completed.toSet()),
      ),
    ],
  );

  // Sent at 23 h on Wednesday, Paris time.
  final sentAt = DateTime.utc(2026, 10, 7, 21);
  final opensAt = DateTime.utc(2026, 10, 8, 13, 30);
  shot(
    'm9-34-order-done-pending',
    done: OrderDone(
      OrderSent('o', side: Side.buy, opensAt: opensAt),
      built: false,
    ),
    view: OrderView(
      detail: OrderDetail(
        order: _buy(_apple, 2000, sentAt),
        walletId: WalletRepository.liveWalletId,
        status: OrderStatus.pending,
      ),
      asset: _apple,
      trip: false,
      opensAt: opensAt,
    ),
    held: {'world': d('9400'), 'lvmh': d('1350'), 'airbus': d('900')},
    pending: {'apple': d('2000')},
  );

  // At 17 h on Wednesday, the Nasdaq open.
  final apple = _fill(_apple, '6.940478', '336.67', '3.00');
  shot(
    'm9-34-order-done-filled',
    done: OrderDone(OrderExecuted('o', apple), built: true),
    view: OrderView(
      detail: OrderDetail(
        order: _buy(_apple, 2000, DateTime.utc(2026, 10, 7, 15)),
        walletId: WalletRepository.liveWalletId,
        status: OrderStatus.filled,
        fill: apple,
      ),
      asset: _apple,
      trip: false,
    ),
    held: {
      'world': d('9400'),
      'apple': d('2000'),
      'lvmh': d('1350'),
      'airbus': d('900'),
    },
  );

  final world = _fill(_world, '7.270117', '160.71', '1.50');
  shot(
    'm9-34-order-done-mission',
    done: OrderDone(
      OrderExecuted('o', world, missions: const ['ae.mission-first-etf']),
      built: true,
      missions: const ['ae.mission-first-etf'],
    ),
    view: OrderView(
      detail: OrderDetail(
        order: _buy(_world, 1000, DateTime.utc(2026, 10, 7, 15)),
        walletId: WalletRepository.liveWalletId,
        status: OrderStatus.filled,
        fill: world,
      ),
      asset: _world,
      trip: false,
    ),
    held: {'apple': d('2000'), 'lvmh': d('1350'), 'world': d('1000')},
    completed: [...lessons, 'ae.mission-first-etf'],
  );
}
