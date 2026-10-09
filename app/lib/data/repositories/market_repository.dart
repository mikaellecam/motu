import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/cache_status.dart';
import '../../core/clock/simulation_clock.dart';
import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../domain/livret/livret_interest.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/market_calendar.dart';
import '../../domain/market/price_bar.dart';
import '../../domain/market/quote.dart';
import '../local/daos/market_dao.dart';
import '../local/database.dart';
import '../remote/backend_api.dart';
import '../remote/dto.dart';
import 'guard.dart';

/// Market data for the domain: catalogue, daily history, live quotes and
/// exchange calendars (BRIEF §5.2, §6.2, §6.3). Serves the cache when it is
/// current, fetches only what is missing, and falls back to the cache when
/// the network fails; a failure surfaces only when nothing is cached.
///
/// Every read is cut at `asOf`: nothing dated after its day is returned
/// (CLAUDE.md rule 3). Cache ages run on the device clock, never on a trip's.
class MarketRepository {
  /// [online] reports the device's connection (`deviceOnline` in the app).
  MarketRepository(
    AppDatabase db,
    this._api, {
    SimulationClock wallClock = const LiveClock(),
    Stream<bool>? online,
  }) : _dao = db.marketDao,
       _wall = wallClock {
    _onlineSub = online?.listen((value) {
      _online = value;
      _changes.add(null);
    });
    _dao.lastPriceFetch().then((t) {
      if (t != null) _pricesAt(t);
    }, onError: (_) {});
  }

  final MarketDao _dao;
  final BackendApi _api;
  final SimulationClock _wall;

  StreamSubscription<bool>? _onlineSub;
  final _changes = StreamController<void>.broadcast(sync: true);
  bool _online = true;
  bool _priceFetchFailed = false;
  DateTime? _lastUpdated;

  /// Whether the prices served are current: [Offline] without a connection,
  /// [Stale] when the last price fetch failed and the cache stood in,
  /// [Fresh] otherwise. Emits the current status, then each change.
  Stream<CacheStatus> status() => Stream<CacheStatus>.multi((out) {
    final sub = _changes.stream.listen((_) => out.add(_status));
    out.onCancel = sub.cancel;
    out.add(_status);
  }).distinct();

  CacheStatus get _status => !_online
      ? Offline(_lastUpdated)
      : _priceFetchFailed
      ? Stale(_lastUpdated!)
      : const Fresh();

  /// Prices held in the cache date from [t] at the latest.
  void _pricesAt(DateTime t) {
    final last = _lastUpdated;
    if (last == null || t.isAfter(last)) _lastUpdated = t;
    _changes.add(null);
  }

  void _priceFetch({required bool ok, required DateTime cachedAt}) {
    _priceFetchFailed = !ok;
    _pricesAt(cachedAt);
  }

  Future<void> dispose() async {
    await _onlineSub?.cancel();
    await _changes.close();
  }

  /// How long a fetched history counts as up to date: the backend adds each
  /// session's close some time after it.
  static const historyRecheck = Duration(minutes: 15);

  /// A quote's life while its market is open; closed, it lasts until the
  /// next open.
  static const quoteTtl = Duration(minutes: 15);

  /// The catalogue and the calendar of the current year are checked once a
  /// day.
  static const dailyCheck = Duration(days: 1);

  DateTime? _assetsCheckedAt;
  DateTime? _livretCheckedAt;

  /// The Livret A rate and ceiling histories known on [asOf]'s day, checked
  /// once a day (BRIEF §6.2, §4.11).
  Future<({List<LivretRate> rates, List<LivretCeiling> ceilings})> livret({
    required DateTime asOf,
  }) => guardStorage(() async {
    final checked = _livretCheckedAt;
    if (checked == null || _wall.now().difference(checked) >= dailyCheck) {
      try {
        final dto = await _api.livret();
        await _dao.replaceLivret(
          [
            for (final r in dto.rates)
              LivretRatesCompanion.insert(
                validFrom: r.validFrom,
                annualRate: r.annualRate,
              ),
          ],
          [
            for (final c in dto.ceilings)
              LivretCeilingsCompanion.insert(
                validFrom: c.validFrom,
                amountCents: c.amountCents,
              ),
          ],
        );
        _livretCheckedAt = _wall.now();
      } on Failure {
        if ((await _dao.allLivretRates()).isEmpty) rethrow;
      }
    }
    final last = _day(asOf);
    return (
      rates: [
        for (final r in await _dao.allLivretRates())
          if (!r.validFrom.isAfter(last)) LivretRate(r.validFrom, r.annualRate),
      ],
      ceilings: [
        for (final c in await _dao.allLivretCeilings())
          if (!c.validFrom.isAfter(last))
            LivretCeiling(c.validFrom, Money(c.amountCents, Currency.eur)),
      ],
    );
  });

  /// The catalogue, without the assets listed after [asOf].
  Future<List<Asset>> assets({required DateTime asOf}) =>
      guardStorage(() async {
        await _refreshAssets();
        final last = _day(asOf);
        return [
          for (final row in await _dao.allAssets())
            if (!row.listingDate.isAfter(last)) _toAsset(row),
        ];
      });

  /// Daily bars of [assetId] from [from] to [to] included, oldest first, cut
  /// at [asOf]'s day. Offline, the cached bars, which may end earlier.
  Future<List<PriceBar>> history(
    String assetId, {
    required DateTime from,
    required DateTime to,
    required DateTime asOf,
  }) => guardStorage(() async {
    final asset = await _assetRow(assetId);
    final first = _day(from);
    final last = _day(to).isBefore(_day(asOf)) ? _day(to) : _day(asOf);
    if (last.isBefore(first)) return const [];
    await _syncHistory(assetId, upTo: last);
    return [
      for (final r in await _dao.bars(assetId, from: first, to: last))
        PriceBar(
          date: r.date,
          open: r.open,
          high: r.high,
          low: r.low,
          close: r.close,
          volume: r.volume,
          currency: asset.currency,
        ),
    ];
  });

  /// The live price of [assetId]. Null when the backend has none, or when it
  /// was observed after [asOf]'s day: trips price from [history].
  Future<Quote?> latest(String assetId, {required DateTime asOf}) async =>
      (await latestAll([assetId], asOf: asOf))[assetId];

  /// The live prices of [assetIds], those whose cached quote expired fetched
  /// in one request. An asset is missing when the backend has no price for
  /// it, or when its price was observed after [asOf]'s day. Offline, the
  /// cached quotes; the failure surfaces only when none is cached.
  Future<Map<String, Quote>> latestAll(
    Iterable<String> assetIds, {
    required DateTime asOf,
  }) => guardStorage(() async {
    final rows = <String, QuoteRow>{};
    final expired = <String>[];
    for (final id in assetIds.toSet()) {
      final asset = await _assetRow(id);
      final row = await _dao.quote(id);
      if (row != null) rows[id] = row;
      if (row == null || !await _isFresh(row, asset.exchange)) expired.add(id);
    }
    if (expired.isNotEmpty) {
      try {
        for (final q in await _api.quotes(expired)) {
          await _dao.saveQuote(
            QuotesCompanion.insert(
              assetId: q.assetId,
              price: q.price,
              currency: q.currency,
              asOf: q.asOf,
              fetchedAt: _wall.now(),
              marketOpen: q.marketOpen,
            ),
          );
        }
        for (final id in expired) {
          final row = await _dao.quote(id);
          if (row != null) rows[id] = row;
        }
        _priceFetch(ok: true, cachedAt: _wall.now());
      } on Failure {
        if (rows.isEmpty) rethrow;
        _priceFetch(
          ok: false,
          cachedAt: rows.values
              .map((r) => r.fetchedAt)
              .reduce((a, b) => a.isBefore(b) ? a : b),
        );
      }
    }
    return {
      for (final MapEntry(key: id, value: row) in rows.entries)
        if (!_day(row.asOf).isAfter(_day(asOf)))
          id: Quote(
            Price(row.price, row.currency),
            row.asOf,
            marketOpen: row.marketOpen,
          ),
    };
  });

  /// The holidays of [exchanges] from [fromYear] to [toYear]. Past years are
  /// fetched once; the current year and later are checked once a day, since
  /// an unscheduled closure may be added. A year the backend does not serve
  /// has weekends only.
  Future<MarketCalendar> calendar(
    Set<Exchange> exchanges, {
    required int fromYear,
    required int toYear,
  }) => guardStorage(() async {
    final now = _wall.now();
    for (final exchange in exchanges) {
      final cached = await _dao.cachedCalendarYears(exchange);
      for (var year = fromYear; year <= toYear; year++) {
        final fetchedAt = cached[year];
        if (fetchedAt != null &&
            (year < now.year || now.difference(fetchedAt) < dailyCheck)) {
          continue;
        }
        try {
          final dto = await _api.calendar(exchange, year);
          await _dao.saveHolidays(exchange, year, dto.holidays, fetchedAt: now);
        } on NotFoundFailure {
          // Outside the years the backend serves.
        } on Failure {
          if (fetchedAt == null) rethrow;
        }
      }
    }
    return MarketCalendar({
      for (final exchange in exchanges)
        exchange: {for (final h in await _dao.holidays(exchange)) h.date},
    });
  });

  Future<void> _refreshAssets({bool force = false}) async {
    final checked = _assetsCheckedAt;
    if (!force &&
        checked != null &&
        _wall.now().difference(checked) < dailyCheck) {
      return;
    }
    try {
      final dtos = await _api.assets();
      await _dao.upsertAssets([
        for (final a in dtos)
          AssetsCompanion.insert(
            id: a.id,
            symbol: a.symbol,
            name: a.name,
            type: a.type,
            exchange: a.exchange,
            currency: a.currency,
            region: a.region,
            listingDate: a.listingDate,
          ),
      ]);
      _assetsCheckedAt = _wall.now();
    } on Failure {
      if ((await _dao.allAssets()).isEmpty) rethrow;
    }
  }

  /// The cached asset, refreshing the catalogue once when it is unknown.
  Future<AssetRow> _assetRow(String id) async {
    var row = await _dao.asset(id);
    if (row == null) {
      await _refreshAssets(force: true);
      row = await _dao.asset(id);
    }
    return row ?? (throw const NotFoundFailure());
  }

  /// Brings the cached history up to [upTo]: the whole history the first
  /// time, then only the days after the last cached one. When the backend
  /// has re-adjusted the asset since (a split or dividend changes every past
  /// close), the cache is replaced by the whole history again.
  Future<void> _syncHistory(String assetId, {required DateTime upTo}) async {
    final sync = await _dao.sync(assetId);
    if (sync != null &&
        (!sync.lastDate.isBefore(upTo) ||
            _wall.now().difference(sync.fetchedAt) < historyRecheck)) {
      return;
    }
    try {
      if (sync == null) {
        await _save(await _api.history(assetId));
      } else {
        final next = await _api.history(
          assetId,
          from: sync.lastDate.add(const Duration(days: 1)),
        );
        if (_sameInstant(next.adjustedAt, sync.adjustedAt)) {
          await _save(next, after: sync);
        } else {
          await _save(await _api.history(assetId));
        }
      }
      _priceFetch(ok: true, cachedAt: _wall.now());
    } on Failure {
      if (sync == null) rethrow;
      _priceFetch(ok: false, cachedAt: sync.fetchedAt);
    }
  }

  /// Stores fetched bars: appended [after] the cached ones, or replacing the
  /// asset's whole history when [after] is null.
  Future<void> _save(HistoryDto history, {HistorySyncRow? after}) =>
      _dao.transaction(() async {
        final bars = history.bars;
        if (after == null) await _dao.deleteHistory(history.assetId);
        if (after == null && bars.isEmpty) return;
        await _dao.upsertBars([
          for (final b in bars)
            PriceBarsCompanion.insert(
              assetId: history.assetId,
              date: b.date,
              open: b.open,
              high: b.high,
              low: b.low,
              close: b.close,
              volume: b.volume,
            ),
        ]);
        await _dao.saveSync(
          HistorySyncCompanion.insert(
            assetId: history.assetId,
            firstDate: after?.firstDate ?? bars.first.date,
            lastDate: bars.isEmpty ? after!.lastDate : bars.last.date,
            fetchedAt: _wall.now(),
            adjustedAt: Value(history.adjustedAt),
          ),
        );
      });

  /// Whether a cached quote is still within its life (BRIEF §6.2). Unknown
  /// holidays (offline, never fetched) count as stale.
  Future<bool> _isFresh(QuoteRow row, Exchange exchange) async {
    final fetched = row.fetchedAt;
    final MarketCalendar markets;
    try {
      markets = await calendar(
        {exchange},
        fromYear: fetched.year,
        toYear: fetched.year + 1,
      );
    } on Failure {
      return false;
    }
    final expires = markets.isOpen(exchange, fetched)
        ? fetched.add(quoteTtl)
        : markets.nextOpen(exchange, fetched);
    return _wall.now().isBefore(expires);
  }

  static Asset _toAsset(AssetRow row) => Asset(
    id: row.id,
    symbol: row.symbol,
    name: row.name,
    type: row.type,
    exchange: row.exchange,
    currency: row.currency,
    region: row.region,
    listingDate: row.listingDate,
  );

  static DateTime _day(DateTime t) {
    final utc = t.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  static bool _sameInstant(DateTime? a, DateTime? b) =>
      a == null ? b == null : b != null && a.isAtSameMomentAs(b);
}
