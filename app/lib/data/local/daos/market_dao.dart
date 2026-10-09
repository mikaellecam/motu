import 'package:drift/drift.dart';

import '../../../core/money/money.dart';
import '../../../domain/market/market_calendar.dart';
import '../database.dart';
import '../tables.dart';

part 'market_dao.g.dart';

/// The cache of network data (ADR-002).
@DriftAccessor(
  tables: [
    Assets,
    PriceBars,
    Quotes,
    FxRates,
    LivretRates,
    LivretCeilings,
    HistorySync,
    ExchangeHolidays,
    CalendarYears,
    ContentPacks,
  ],
)
class MarketDao extends DatabaseAccessor<AppDatabase> with _$MarketDaoMixin {
  MarketDao(super.attachedDatabase);

  Future<void> upsertAssets(List<AssetsCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(assets, rows));

  Future<AssetRow?> asset(String id) =>
      (select(assets)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<List<AssetRow>> allAssets() =>
      (select(assets)..orderBy([(a) => OrderingTerm(expression: a.id)])).get();

  /// Stores bars; a bar on a cached date replaces it.
  Future<void> upsertBars(List<PriceBarsCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(priceBars, rows));

  /// [assetId]'s bars from [from] to [to], both included, oldest first.
  Future<List<PriceBarRow>> bars(
    String assetId, {
    required DateTime from,
    required DateTime to,
  }) =>
      (select(priceBars)
            ..where(
              (b) =>
                  b.assetId.equals(assetId) & b.date.isBetweenValues(from, to),
            )
            ..orderBy([(b) => OrderingTerm(expression: b.date)]))
          .get();

  /// Drops an asset's bars and sync state, before refetching its whole
  /// history after a split.
  Future<void> deleteHistory(String assetId) => transaction(() async {
    await (delete(priceBars)..where((b) => b.assetId.equals(assetId))).go();
    await (delete(historySync)..where((s) => s.assetId.equals(assetId))).go();
  });

  Future<HistorySyncRow?> sync(String assetId) => (select(
    historySync,
  )..where((s) => s.assetId.equals(assetId))).getSingleOrNull();

  Future<void> saveSync(HistorySyncCompanion row) =>
      into(historySync).insertOnConflictUpdate(row);

  Future<QuoteRow?> quote(String assetId) => (select(
    quotes,
  )..where((q) => q.assetId.equals(assetId))).getSingleOrNull();

  Future<void> saveQuote(QuotesCompanion row) =>
      into(quotes).insertOnConflictUpdate(row);

  /// When prices were last fetched: the latest quote or history fetch.
  Future<DateTime?> lastPriceFetch() async {
    final quoted = quotes.fetchedAt.max();
    final synced = historySync.fetchedAt.max();
    final times = [
      await (selectOnly(
        quotes,
      )..addColumns([quoted])).map((r) => r.read(quoted)).getSingle(),
      await (selectOnly(
        historySync,
      )..addColumns([synced])).map((r) => r.read(synced)).getSingle(),
    ].nonNulls;
    return times.isEmpty ? null : times.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  Future<void> upsertRates(List<FxRatesCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(fxRates, rows));

  /// The latest rate dated on or before [date] (BRIEF §6.2: a date without a
  /// published rate uses the previous one).
  Future<FxRateRow?> rateOnOrBefore(
    Currency base,
    Currency quote,
    DateTime date,
  ) =>
      (select(fxRates)
            ..where(
              (r) =>
                  r.base.equalsValue(base) &
                  r.quote.equalsValue(quote) &
                  r.date.isSmallerOrEqualValue(date),
            )
            ..orderBy([
              (r) => OrderingTerm(expression: r.date, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// Rates from [from] to [to], both included, oldest first.
  Future<List<FxRateRow>> rates(
    Currency base,
    Currency quote, {
    required DateTime from,
    required DateTime to,
  }) =>
      (select(fxRates)
            ..where(
              (r) =>
                  r.base.equalsValue(base) &
                  r.quote.equalsValue(quote) &
                  r.date.isBetweenValues(from, to),
            )
            ..orderBy([(r) => OrderingTerm(expression: r.date)]))
          .get();

  /// Replaces the Livret A history: small, dated data from the backend.
  Future<void> replaceLivret(
    List<LivretRatesCompanion> rates,
    List<LivretCeilingsCompanion> ceilings,
  ) => transaction(() async {
    await delete(livretRates).go();
    await delete(livretCeilings).go();
    await batch((b) {
      b.insertAll(livretRates, rates);
      b.insertAll(livretCeilings, ceilings);
    });
  });

  Future<List<LivretRateRow>> allLivretRates() => (select(
    livretRates,
  )..orderBy([(r) => OrderingTerm(expression: r.validFrom)])).get();

  Future<List<LivretCeilingRow>> allLivretCeilings() => (select(
    livretCeilings,
  )..orderBy([(c) => OrderingTerm(expression: c.validFrom)])).get();

  /// Stores an exchange's holidays of [year] and marks the year as cached.
  Future<void> saveHolidays(
    Exchange exchange,
    int year,
    List<DateTime> dates, {
    required DateTime fetchedAt,
  }) => transaction(() async {
    await batch((b) {
      b.insertAllOnConflictUpdate(exchangeHolidays, [
        for (final date in dates)
          ExchangeHolidaysCompanion.insert(exchange: exchange, date: date),
      ]);
      b.insertAllOnConflictUpdate(calendarYears, [
        CalendarYearsCompanion.insert(
          exchange: exchange,
          year: year,
          fetchedAt: fetchedAt,
        ),
      ]);
    });
  });

  Future<List<ExchangeHolidayRow>> holidays(Exchange exchange) => (select(
    exchangeHolidays,
  )..where((h) => h.exchange.equalsValue(exchange))).get();

  /// The cached years of [exchange], with when each was fetched.
  Future<Map<int, DateTime>> cachedCalendarYears(Exchange exchange) async => {
    for (final row in await (select(
      calendarYears,
    )..where((y) => y.exchange.equalsValue(exchange))).get())
      row.year: row.fetchedAt,
  };

  Future<ContentPackRow?> contentPack(String islandId) => (select(
    contentPacks,
  )..where((p) => p.islandId.equals(islandId))).getSingleOrNull();

  Future<void> saveContentPack(ContentPacksCompanion row) =>
      into(contentPacks).insertOnConflictUpdate(row);

  /// Empties every cache table. User tables are not touched (ADR-002).
  Future<void> clearCache() => transaction(() async {
    for (final table in <TableInfo>[
      assets,
      priceBars,
      quotes,
      fxRates,
      livretRates,
      livretCeilings,
      historySync,
      exchangeHolidays,
      calendarYears,
      contentPacks,
    ]) {
      await delete(table).go();
    }
  });
}
