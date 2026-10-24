import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/explorer/explorer.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/market/quote.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';

Decimal d(String s) => Decimal.parse(s);

Asset asset(String id, String name, String symbol, AssetType type) => Asset(
  id: id,
  symbol: symbol,
  name: name,
  type: type,
  exchange: Exchange.nasdaq,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(2000),
);

/// Weekday closes from [from] to [to], rising by 0,1 a day from [start].
List<PriceBar> bars(DateTime from, DateTime to, {String start = '100'}) {
  var close = d(start);
  return [
    for (var t = from; !t.isAfter(to); t = t.add(const Duration(days: 1)))
      if (t.weekday <= 5)
        PriceBar(
          date: t,
          open: close,
          high: close,
          low: close,
          close: close += d('0.1'),
          volume: 1,
          currency: Currency.usd,
        ),
  ];
}

void main() {
  final apple = asset('apple', 'Apple', 'AAPL', AssetType.stock);
  final asOf = DateTime.utc(2026, 10, 8, 12);

  group('row', () {
    // Every weekday from 1 September 2025 to 7 October 2026.
    final history = bars(DateTime.utc(2025, 9, 1), DateTime.utc(2026, 10, 7));

    test('price, 1-year change and risk band', () {
      final row = explorerRow(apple, bars: history, asOf: asOf);
      expect(row.price, Price(history.last.close, Currency.usd));
      // A year before 8 October 2026 is a Wednesday with a close.
      final ref = history.lastWhere(
        (b) => !b.date.isAfter(DateTime.utc(2025, 10, 8)),
      );
      expect(ref.date, DateTime.utc(2025, 10, 8));
      expect(row.yearChange, ratio(history.last.close - ref.close, ref.close));
      // A steady climb barely moves: lowest band.
      expect(row.riskBand, 1);
    });

    test('a live quote is the price the change is measured to', () {
      final row = explorerRow(
        apple,
        bars: history,
        quote: Quote(Price(d('200'), Currency.usd), asOf, marketOpen: true),
        asOf: asOf,
      );
      expect(row.price!.value, d('200'));
      expect(row.yearChange! > d('0.5'), isTrue);
    });

    test('a year back on a weekend takes the Friday before', () {
      // 2026-10-11 is a Sunday; a year earlier, 2025-10-11, a Saturday.
      final row = explorerRow(
        apple,
        bars: history,
        asOf: DateTime.utc(2026, 10, 11),
      );
      final friday = history.firstWhere(
        (b) => b.date == DateTime.utc(2025, 10, 10),
      );
      expect(
        row.yearChange,
        ratio(history.last.close - friday.close, friday.close),
      );
    });

    test(
      'listed less than a year ago, or too few days: no change, no band',
      () {
        final young = bars(
          DateTime.utc(2026, 9, 21),
          DateTime.utc(2026, 10, 7),
        );
        final row = explorerRow(apple, bars: young, asOf: asOf);
        expect(row.price, isNotNull);
        expect(row.yearChange, isNull);
        expect(row.riskBand, isNull, reason: '12 closes, under 20 returns');
      },
    );

    test('no bars and no quote: nothing known', () {
      final row = explorerRow(apple, bars: const [], asOf: asOf);
      expect(row.price, isNull);
      expect(row.yearChange, isNull);
      expect(row.riskBand, isNull);
    });

    test('bars after asOf are never read', () {
      final trip = explorerRow(
        apple,
        bars: history,
        asOf: DateTime.utc(2026, 3, 2),
      );
      expect(
        trip.price!.value,
        history
            .lastWhere((b) => !b.date.isAfter(DateTime.utc(2026, 3, 2)))
            .close,
      );
    });
  });

  group('search and filters', () {
    ExplorerRow row(String id, String name, String symbol, AssetType type) =>
        ExplorerRow(
          asset: asset(id, name, symbol, type),
          price: null,
          yearChange: null,
          riskBand: null,
        );
    final rows = [
      row('world', 'ETF Monde', 'ACWI', AssetType.etf),
      row('hermes', 'Hermès', 'HESAY', AssetType.stock),
      row('loreal', "L'Oréal", 'LRLCY', AssetType.stock),
      row('coca-cola', 'Coca-Cola', 'KO', AssetType.stock),
      row('nvidia', 'Nvidia', 'NVDA', AssetType.stock),
    ];
    List<String> ids(
      String query, [
      ExplorerFilter filter = ExplorerFilter.all,
      Set<String> favorites = const {},
    ]) => [
      for (final r in filterRows(
        rows,
        query: query,
        filter: filter,
        favorites: favorites,
      ))
        r.asset.id,
    ];

    test('name or ticker, ignoring case, accents and punctuation', () {
      expect(ids(''), hasLength(5));
      expect(ids('hermes'), ['hermes']);
      expect(ids('loreal'), ['loreal']);
      expect(ids(" l'oré "), ['loreal']);
      expect(ids('coca cola'), ['coca-cola']);
      expect(ids('nvda'), ['nvidia']);
      expect(ids('monde'), ['world']);
      expect(ids('zzz'), isEmpty);
    });

    test('ETFs, stocks, favorites', () {
      expect(ids('', ExplorerFilter.etfs), ['world']);
      expect(ids('', ExplorerFilter.stocks), hasLength(4));
      expect(ids('', ExplorerFilter.favorites, {'nvidia', 'world'}), [
        'world',
        'nvidia',
      ]);
      expect(ids('nv', ExplorerFilter.favorites, {'world'}), isEmpty);
    });

    /// Each group as « type: ids ».
    List<String> groups(List<ExplorerRow> rows) => [
      for (final (type, group) in groupRows(rows))
        '${type.name}: ${group.map((r) => r.asset.id).join(' ')}',
    ];

    test('ETFs then stocks, each in the given order', () {
      expect(groups(rows), [
        'etf: world',
        'stock: hermes loreal coca-cola nvidia',
      ]);
      // ETFs come first even listed after the stocks.
      expect(groups(rows.reversed.toList()), [
        'etf: world',
        'stock: nvidia coca-cola loreal hermes',
      ]);
    });

    test('a group with nothing left is not there', () {
      final hermes = filterRows(
        rows,
        query: 'hermes',
        filter: ExplorerFilter.all,
        favorites: const {},
      );
      expect(groups(hermes), ['stock: hermes']);
      expect(groups([rows.first]), ['etf: world']);
      expect(groupRows(const []), isEmpty);
    });
  });

  group('rows provider', () {
    late AppDatabase db;
    late FakeBackend backend;
    late WallClock wall;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      backend = FakeBackend();
      wall = WallClock(DateTime.utc(2026, 10, 8, 12));
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          liveClockProvider.overrideWithValue(wall),
          marketRepositoryProvider.overrideWithValue(
            MarketRepository(
              db,
              BackendApi('http://backend.test', adapter: backend),
              wallClock: wall,
            ),
          ),
        ],
      );
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('live: one quote request for the catalogue, sorted by name', () async {
      backend.quotes['apple'] = {
        'assetId': 'apple',
        'price': '102.5',
        'currency': 'USD',
        'asOf': '2026-10-07T20:00:00Z',
        'marketOpen': false,
      };
      final rows = await container.read(explorerRowsProvider(null).future);
      expect([for (final r in rows) r.asset.id], ['apple', 'meta']);
      expect(rows.first.price!.value, d('102.5'));
      expect(rows.last.price, isNull, reason: 'no quote and no bars');
      expect(backend.to('/v1/quotes'), hasLength(1));
    });

    test('a trip: listed later is hidden, values as of its day', () async {
      final wallets = WalletRepository(db);
      await wallets.createWallet(
        id: 'trip',
        kind: WalletKind.trip,
        name: '2010',
        startDate: DateTime.utc(2010, 6, 1),
        startingCash: const Money(1000000, Currency.eur),
        params: WalletParams(
          rules: TradingRules(
            fxFeeRate: Decimal.zero,
            fixedFee: const Money.zero(Currency.eur),
            fractionalShares: true,
          ),
          monthlyContribution: const Money.zero(Currency.eur),
          stops: const StopConditions(),
        ),
        createdAt: wall.now(),
      );
      final rows = await container.read(explorerRowsProvider('trip').future);
      expect(
        [for (final r in rows) r.asset.id],
        ['apple'],
        reason: 'Meta listed in 2012',
      );
      expect(rows.single.price, isNull, reason: 'no 2010 bars in the fake');
      expect(backend.to('/v1/quotes'), isEmpty);
    });

    test('offline with nothing cached: the failure', () async {
      backend.offline = true;
      await expectLater(
        container.read(explorerRowsProvider(null).future),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}
