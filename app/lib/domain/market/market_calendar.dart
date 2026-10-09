import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Exchanges with their time zone and regular session, in local time
/// (BRIEF §4.6). Local hours plus the IANA zone give the right Paris time on
/// every date, including the weeks when Europe and the US change clocks on
/// different Sundays.
enum Exchange {
  euronext('Europe/Paris', (9, 0), (17, 30)),
  nyse('America/New_York', (9, 30), (16, 0)),
  nasdaq('America/New_York', (9, 30), (16, 0)),

  /// Over-the-counter US listings (ADRs of European companies, ADR-004):
  /// New York hours and holidays.
  otc('America/New_York', (9, 30), (16, 0));

  const Exchange(this.timeZone, this.opens, this.closes);

  final String timeZone;
  final (int, int) opens;
  final (int, int) closes;
}

// The tz database is compiled-in data, not I/O. Top-level finals are lazy:
// it loads on first use.
final Map<Exchange, tz.Location> _locations = () {
  tzdata.initializeTimeZones();
  return {for (final e in Exchange.values) e: tz.getLocation(e.timeZone)};
}();

tz.Location _location(Exchange exchange) => _locations[exchange]!;

/// Trading days and market hours. Dates are `DateTime.utc(y, m, d)`; any time
/// of day is ignored. Instants are UTC `DateTime`s.
///
/// Holidays are injected per exchange (from the backend calendar). A year
/// with no injected data has weekends only. Early closes are not modelled.
// ponytail: regular sessions only; add early-close days if the backend
// calendar starts serving them.
class MarketCalendar {
  MarketCalendar(Map<Exchange, Set<DateTime>> holidays)
    : _holidays = {
        for (final MapEntry(:key, :value) in holidays.entries)
          key: {for (final date in value) _day(date)},
      };

  final Map<Exchange, Set<DateTime>> _holidays;

  static DateTime _day(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  bool isTradingDay(Exchange exchange, DateTime date) {
    final day = _day(date);
    return day.weekday != DateTime.saturday &&
        day.weekday != DateTime.sunday &&
        !(_holidays[exchange]?.contains(day) ?? false);
  }

  /// The first trading day strictly after [date].
  DateTime nextTradingDay(Exchange exchange, DateTime date) =>
      onOrAfter(exchange, _day(date).add(const Duration(days: 1)));

  /// The last trading day strictly before [date].
  DateTime previousTradingDay(Exchange exchange, DateTime date) =>
      onOrBefore(exchange, _day(date).subtract(const Duration(days: 1)));

  /// [date] if it trades, else the next trading day.
  DateTime onOrAfter(Exchange exchange, DateTime date) {
    var day = _day(date);
    while (!isTradingDay(exchange, day)) {
      day = day.add(const Duration(days: 1));
    }
    return day;
  }

  /// [date] if it trades, else the previous trading day.
  DateTime onOrBefore(Exchange exchange, DateTime date) {
    var day = _day(date);
    while (!isTradingDay(exchange, day)) {
      day = day.subtract(const Duration(days: 1));
    }
    return day;
  }

  /// Whether a regular session is running at [instant].
  bool isOpen(Exchange exchange, DateTime instant) {
    final local = tz.TZDateTime.from(instant, _location(exchange));
    if (!isTradingDay(
      exchange,
      DateTime.utc(local.year, local.month, local.day),
    )) {
      return false;
    }
    final open = _at(exchange, local, exchange.opens);
    final close = _at(exchange, local, exchange.closes);
    return !local.isBefore(open) && local.isBefore(close);
  }

  /// The start of the first session that opens strictly after [instant], as
  /// a UTC instant.
  DateTime nextOpen(Exchange exchange, DateTime instant) {
    final local = tz.TZDateTime.from(instant, _location(exchange));
    var day = DateTime.utc(local.year, local.month, local.day);
    while (true) {
      if (isTradingDay(exchange, day)) {
        final open = _at(exchange, day, exchange.opens);
        if (open.isAfter(instant)) return open.toUtc();
      }
      day = day.add(const Duration(days: 1));
    }
  }

  /// When the regular session of [day] closes, as a UTC instant.
  DateTime closeAt(Exchange exchange, DateTime day) =>
      _at(exchange, _day(day), exchange.closes).toUtc();

  /// [time] on the local calendar day of [date], in the exchange's zone.
  static tz.TZDateTime _at(Exchange exchange, DateTime date, (int, int) time) =>
      tz.TZDateTime(
        _location(exchange),
        date.year,
        date.month,
        date.day,
        time.$1,
        time.$2,
      );
}
