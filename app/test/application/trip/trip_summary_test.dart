import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_summary.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/stop_decision.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/fake_frankfurter.dart';

DateTime day(int d) => DateTime.utc(2026, 10, d);
Decimal dec(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(dec(s), Currency.eur);

const _l = Localized('x', 'x');
const volatility = GlossaryTerm(
  id: 'volatilite',
  title: Localized('Volatilité', 'Volatility'),
  short: _l,
  body: _l,
);

Order order(String id, Side side, int qty, int on) => Order(
  id: id,
  assetId: 'apple',
  side: side,
  type: OrderType.market,
  size: QuantitySize(Quantity.whole(qty)),
  createdAt: day(on),
);

Fill fill(Side side, int qty, String price, int on, String fx) => Fill(
  assetId: 'apple',
  side: side,
  date: day(on),
  quantity: Quantity.whole(qty),
  price: Price(dec(price), Currency.usd),
  fxRate: dec(fx),
  fees: const Money.zero(Currency.eur),
);

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late WalletRepository wallets;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final wall = WallClock(DateTime.utc(2026, 10, 8, 12));
    final backend = FakeBackend();
    backend.assets.add({...backend.assets.first, 'id': 'world'});
    backend.closes['world'] = {
      '2026-10-05': '50',
      '2026-10-06': '45',
      '2026-10-07': '48',
    };
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(wall),
        marketRepositoryProvider.overrideWithValue(
          MarketRepository(
            db,
            BackendApi('http://t', adapter: backend),
            wallClock: wall,
          ),
        ),
        fxServiceProvider.overrideWithValue(
          FxService(
            db,
            FrankfurterApi(adapter: FakeFrankfurter()),
            wallClock: wall,
          ),
        ),
        contentPackProvider(actionsEtfIsland).overrideWith(
          (ref) async => const ContentPack(
            id: 'actions-etf',
            version: 1,
            title: _l,
            nodes: [],
            datasets: {},
            glossary: {'volatilite': volatility},
          ),
        ),
      ],
    );
    wallets = WalletRepository(db);
    await wallets.createWallet(
      id: 'trip',
      kind: WalletKind.trip,
      name: 'Octobre',
      startDate: day(5),
      startingCash: eur('10000'),
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: Decimal.zero,
          fixedFee: const Money.zero(Currency.eur),
          fractionalShares: false,
        ),
        monthlyContribution: const Money.zero(Currency.eur),
        stops: StopConditions(drawdown: dec('0.15')),
      ),
      createdAt: day(8),
    );
    // 10 Apple bought on the 5th at 100 $ (0,85251 €/$).
    final buy = order('o1', Side.buy, 10, 5);
    await wallets.placeOrder('trip', buy);
    await wallets.recordFill(
      'trip',
      buy,
      fill(Side.buy, 10, '100', 5, '0.85251'),
    );
    // Moved to the 7th; the companion saw a first loss on the 6th.
    final before = await wallets.tripState('trip', livretRates: const []);
    await wallets.saveAdvance(
      'trip',
      TripAdvance(
        state: before.copyWith(
          date: day(7),
          values: [
            ...before.values,
            DailyValue(date: day(6), value: eur('9000'), flow: eur('0')),
            DailyValue(date: day(7), value: eur('8400'), flow: eur('0')),
          ],
        ),
        events: [
          MomentFired(
            Moment(CompanionRule.firstLoss, 'apple', day(6), const {}),
          ),
        ],
        stop: const [],
        endOfData: false,
      ),
      before: before,
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<TripSummary> summary() =>
      container.read(tripSummaryProvider('trip').future);

  /// A stop on the 6th answered with [decision]; its sell filled on the 7th
  /// at 101 $ (0,8547 €/$).
  Future<void> decide(StopDecision decision) async {
    final sell = order(stopSellId('apple', day(6)), Side.sell, 5, 6);
    await wallets.decide(
      'trip',
      simDate: day(6),
      eventId: 'stop-2026-10-06',
      decision: decision.id,
      sells: [if (decision == StopDecision.sellHalf) sell],
      reason: 'Peur',
    );
    if (decision == StopDecision.sellHalf) {
      await wallets.recordFill(
        'trip',
        sell,
        fill(Side.sell, 5, '101', 7, '0.8547'),
      );
    }
  }

  test('the trip against the same money elsewhere', () async {
    await decide(StopDecision.sellHalf);
    final s = await summary();
    expect((s.name, s.start, s.end), ('Octobre', day(5), day(7)));
    expect(s.moneyIn, eur('10000'));
    expect([for (final o in s.outcomes) o.outcome], Outcome.values);

    // 9 147,49 € + 431,62 € of cash, 5 × 102 $ × 0,8547.
    final you = s.outcomes[0];
    expect(you.value, dec('10015.007'));
    expect(you.twr.round(scale: 6), dec('0.001501'));

    // 10 000 € into the world ETF at 50 $, worth 48 $ on the 7th.
    expect(s.outcomes[1].twr.round(scale: 3), dec('-0.038'));

    // The Livret pays from the next fortnight on.
    expect((s.outcomes[2].value, s.outcomes[2].twr), (dec('10000'), dec('0')));
    expect(s.livretCapped, isFalse);

    // Everything sold on the 6th: 9 000 €, kept as cash.
    final worst = s.outcomes[3];
    expect(
      (worst.date, worst.value, worst.twr),
      (day(6), dec('9000'), dec('-0.1')),
    );
  });

  test('the journal replayed with what happened next', () async {
    await decide(StopDecision.sellHalf);
    final line = (await summary()).journal.single;
    expect((line.entry.decision, line.entry.reason), ('sell_half', 'Peur'));
    expect(line.sold, ['apple']);
    // Sold at 101 $, 102 $ at the end, same rate.
    expect(line.moved!.round(scale: 6), dec('0.009901'));
  });

  test('« Garder »: the portfolio after, and no worst decision', () async {
    await decide(StopDecision.hold);
    final s = await summary();
    expect(s.outcomes.map((o) => o.outcome), isNot(contains(Outcome.worst)));
    final line = s.journal.single;
    expect(line.sold, isEmpty);
    // 9 000 € on the 6th; 9 147,49 € + 10 × 102 $ × 0,8547 now.
    expect(line.moved!.round(scale: 4), dec('0.1133'));
  });

  test('the glossary terms met that the content pack has', () async {
    expect([for (final t in (await summary()).terms) t.id], ['volatilite']);
  });

  test('a trip ended by hand is finished', () async {
    await container.read(tripFinishProvider('trip').notifier).finish();
    expect((await wallets.load('trip')).status, WalletStatus.finished);
  });
}
