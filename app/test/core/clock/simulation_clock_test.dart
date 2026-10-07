import 'package:finance_companion/core/clock/simulation_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HistoricalClock is pinned to a calendar date, in UTC', () {
    final clock = HistoricalClock(DateTime(2020, 2, 18, 15, 42));
    expect(clock.now(), DateTime.utc(2020, 2, 18));
    expect(clock.now(), clock.now());
  });

  test('LiveClock reads the device time, in UTC', () {
    final before = DateTime.now().toUtc();
    final now = const LiveClock().now();
    final after = DateTime.now().toUtc();
    expect(now.isUtc, isTrue);
    expect(now.isBefore(before), isFalse);
    expect(now.isAfter(after), isFalse);
  });
}
