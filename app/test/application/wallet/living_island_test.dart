import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/wallet/living_island.dart';
import 'package:finance_companion/application/wallet/wallet_overview.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/wallet/island_buildings.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int m, int dd) => DateTime.utc(2026, m, dd);

Asset stock(String id) => Asset(
  id: id,
  symbol: id.toUpperCase(),
  name: id,
  type: AssetType.stock,
  exchange: Exchange.nasdaq,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(1990),
);

Fill fill(String id, String qty) => Fill(
  assetId: id,
  side: Side.buy,
  date: day(10, 1),
  quantity: Quantity.truncate(d(qty)),
  price: Price(d('100'), Currency.usd),
  fxRate: Decimal.one,
  fees: const Money.zero(Currency.eur),
);

Order order(String id, String asset, Side side, OrderSize size) => Order(
  id: id,
  assetId: asset,
  side: side,
  type: OrderType.market,
  size: size,
  createdAt: day(10, 7),
);

void main() {
  test(
    'the live wallet\'s positions, raised by its pending buys only',
    () async {
      // Prices at 100 $ = 100 € (rate 1, no fees): world 2 000 €, apple 500 €;
      // a 500 € buy of Apple waits, so does a sale of the world ETF.
      final fills = [fill('world', '20'), fill('apple', '5')];
      final overview = buildOverview(
        wallet: WalletState(
          id: WalletRepository.liveWalletId,
          kind: WalletKind.live,
          name: 'live',
          startDate: day(10, 1),
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
          cash: const Money(1000000, Currency.eur),
          fills: fills,
          positions: positionsFrom(fills),
          pendingOrders: [
            order(
              'o1',
              'apple',
              Side.buy,
              AmountSize(const Money(50000, Currency.eur)),
            ),
            order('o2', 'world', Side.sell, QuantitySize(Quantity.whole(5))),
          ],
          values: [
            DailyValue(
              date: day(10, 1),
              value: const Money(1250000, Currency.eur),
              flow: const Money(1250000, Currency.eur),
            ),
          ],
          livretMovements: const [],
          plans: const [],
        ),
        asOf: DateTime.utc(2026, 10, 8, 15),
        assets: {'world': stock('world'), 'apple': stock('apple')},
        prices: {
          for (final id in ['world', 'apple'])
            id: ObservedPrice(
              PriceAsOf(
                Price(d('100'), Currency.usd),
                day(10, 7),
                stale: false,
              ),
              DateTime.utc(2026, 10, 7, 20),
            ),
        },
        fxRates: {Currency.usd: Decimal.one},
        livret: Decimal.zero,
      );
      final container = ProviderContainer(
        overrides: [
          walletOverviewProvider.overrideWith((ref, id) async {
            expect(id, WalletRepository.liveWalletId);
            return overview;
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(livingIslandProvider.future), [
        IslandBuilding('world', height: Decimal.one, built: Decimal.one),
        IslandBuilding('apple', height: d('0.5'), built: d('0.5')),
      ]);
    },
  );
}
