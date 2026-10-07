/// The only source of "now" (CLAUDE.md rule 3). Repositories clamp every read
/// to `now()`, so nothing dated later reaches the domain or the UI.
abstract interface class SimulationClock {
  /// A UTC instant.
  DateTime now();
}

/// The live wallet's clock: the device time.
final class LiveClock implements SimulationClock {
  const LiveClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// A trip's clock, pinned to one simulated day. The day is seen after the
/// close: everything dated that day or earlier is known, nothing later.
final class HistoricalClock implements SimulationClock {
  HistoricalClock(DateTime date)
    : _date = DateTime.utc(date.year, date.month, date.day);

  final DateTime _date;

  /// The simulated date, at 00:00 UTC.
  @override
  DateTime now() => _date;
}
