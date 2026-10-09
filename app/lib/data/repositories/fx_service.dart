import 'package:decimal/decimal.dart';

import '../../core/clock/simulation_clock.dart';
import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../local/daos/market_dao.dart';
import '../local/database.dart';
import '../remote/frankfurter_api.dart';
import 'guard.dart';

/// Exchange rates, the only way money changes currency (CLAUDE.md rule 5).
/// ECB reference rates come from Frankfurter and are cached in drift; a
/// published rate never changes (BRIEF §6.2, ADR-005).
///
/// The first need of a pair caches its whole history since the data floor in
/// one request (about 200 KB). After that the cache has no holes: any day up
/// to the last cached rate is answered without the network, weekends and
/// ECB holidays included, and only the days after it are ever fetched.
class FxService {
  FxService(
    AppDatabase db,
    this._api, {
    SimulationClock wallClock = const LiveClock(),
  }) : _dao = db.marketDao,
       _wall = wallClock;

  final MarketDao _dao;
  final FrankfurterApi _api;
  final SimulationClock _wall;

  /// The first day of market history (ADR-004).
  static final dataFloor = DateTime.utc(2000, 1, 3);

  /// How long a check for a newer rate holds: the ECB publishes once per
  /// business day, around 16:00 in Frankfurt.
  static const recheck = Duration(minutes: 15);

  final _checkedAt = <(Currency, Currency), DateTime>{};

  /// Units of [to] per unit of [from] on [asOf]'s day: the last rate
  /// published on or before it. Offline, the last cached one. Throws
  /// [DataUnavailableFailure] before the first published rate.
  Future<Decimal> rate(Currency from, Currency to, {required DateTime asOf}) =>
      guardStorage(() async {
        if (from == to) return Decimal.one;
        final utc = asOf.toUtc();
        final day = DateTime.utc(utc.year, utc.month, utc.day);
        await _sync(from, to, upTo: day);
        final row = await _dao.rateOnOrBefore(from, to, day);
        return row?.rate ?? (throw DataUnavailableFailure(asOf));
      });

  /// Fetches the rates the cache lacks up to today, when [upTo] is past the
  /// last cached one.
  Future<void> _sync(
    Currency from,
    Currency to, {
    required DateTime upTo,
  }) async {
    final last = (await _dao.rateOnOrBefore(from, to, _far))?.date;
    if (last != null && !last.isBefore(upTo)) return;
    final now = _wall.now();
    final checked = _checkedAt[(from, to)];
    if (last != null && checked != null && now.difference(checked) < recheck) {
      return;
    }
    final start = last?.add(const Duration(days: 1)) ?? dataFloor;
    final today = DateTime.utc(now.year, now.month, now.day);
    if (start.isAfter(today)) return;
    try {
      final rates = await _api.rates(from, to, start, today);
      await _dao.upsertRates([
        for (final r in rates)
          FxRatesCompanion.insert(
            base: from,
            quote: to,
            date: r.date,
            rate: r.rate,
          ),
      ]);
      _checkedAt[(from, to)] = now;
    } on Failure {
      if (last == null) rethrow;
    }
  }

  static final _far = DateTime.utc(9999);
}
