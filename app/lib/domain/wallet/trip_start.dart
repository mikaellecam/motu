/// Rules for the start date of a trip (BRIEF §4.5, wizard step 1).
library;

/// The first day of market history (ADR-004).
final dataFloor = DateTime.utc(2000, 1, 3);

/// The outcome of checking a start date.
sealed class StartCheck {
  const StartCheck();
}

/// A valid start: [date] is a trip day. [rolledFrom] is the day the user
/// asked for when it had no session and the start moved to the next one.
final class StartOk extends StartCheck {
  const StartOk(this.date, {this.rolledFrom});
  final DateTime date;
  final DateTime? rolledFrom;
}

/// Not a date, or not one that exists (31/02).
final class StartUnreadable extends StartCheck {
  const StartUnreadable();
}

/// Before the first day of market data.
final class StartBeforeFloor extends StartCheck {
  const StartBeforeFloor(this.floor);
  final DateTime floor;
}

/// Less than 30 days ago: a trip needs history ahead of it.
final class StartTooRecent extends StartCheck {
  const StartTooRecent(this.latest);
  final DateTime latest;
}

/// The latest start allowed on [today]: 30 days earlier.
DateTime latestStart(DateTime today) =>
    _day(today).subtract(const Duration(days: 30));

/// Reads `JJ/MM/AAAA`; null when it is not a real day.
DateTime? parseDay(String input) {
  final match = RegExp(r'^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$')
      .firstMatch(input);
  if (match == null) return null;
  final [d, m, y] = [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
  final date = DateTime.utc(y, m, d);
  // DateTime rolls 31/02 over to March: such a day does not exist.
  return date.day == d && date.month == m && date.year == y ? date : null;
}

/// Checks a start [date]: it must lie between [floor] and 30 days before
/// [today]; a day without a session moves to the next trip day, which must
/// still be in range.
StartCheck checkStart(
  DateTime? date, {
  required DateTime today,
  required DateTime floor,
  required bool Function(DateTime day) isTripDay,
}) {
  if (date == null) return const StartUnreadable();
  final day = _day(date);
  if (day.isBefore(floor)) return StartBeforeFloor(floor);
  final latest = latestStart(today);
  var start = day;
  // Past the latest start the answer is "too recent" anyway: the walk stops
  // there, even with no session at all.
  while (!isTripDay(start) && !start.isAfter(latest)) {
    start = DateTime.utc(start.year, start.month, start.day + 1);
  }
  if (start.isAfter(latest)) return StartTooRecent(latest);
  return StartOk(start, rolledFrom: start == day ? null : day);
}

/// « Il y a N ans »: the same day [years] back, or the trip day before it.
DateTime yearsAgo(
  int years, {
  required DateTime today,
  required bool Function(DateTime day) isTripDay,
}) {
  final t = _day(today);
  var day = DateTime.utc(
    t.year - years,
    t.month,
    t.month == 2 && t.day == 29 ? 28 : t.day,
  );
  // The longest market closure since 2000 lasted 6 days (September 2001).
  for (var i = 0; i < 14 && !isTripDay(day); i++) {
    day = DateTime.utc(day.year, day.month, day.day - 1);
  }
  return day;
}

DateTime _day(DateTime t) {
  final utc = t.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
