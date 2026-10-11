import 'package:finance_companion/domain/wallet/trip_start.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

/// Weekdays trade, except 2008-09-17 (a made-up holiday).
bool tripDay(DateTime d) => d.weekday <= 5 && d != day(2008, 9, 17);

void main() {
  final floor = day(2000, 1, 3);
  final today = day(2026, 10, 11);
  StartCheck check(DateTime? d) =>
      checkStart(d, today: today, floor: floor, isTripDay: tripDay);

  group('parse JJ/MM/AAAA', () {
    test('real days', () {
      expect(parseDay('15/09/2008'), day(2008, 9, 15));
      expect(parseDay(' 1/2/2020 '), day(2020, 2, 1));
      expect(parseDay('29/02/2020'), day(2020, 2, 29));
    });
    test('not a day', () {
      for (final input in [
        '',
        '2008-09-15',
        '31/02/2020',
        '29/02/2021',
        '15/13/2008',
        '00/01/2008',
        'abc',
        '15/09/08',
      ]) {
        expect(parseDay(input), isNull, reason: input);
      }
    });
  });

  group('check', () {
    test('a trip day starts as is', () {
      final ok = check(day(2008, 9, 15)) as StartOk;
      expect(ok.date, day(2008, 9, 15));
      expect(ok.rolledFrom, isNull);
    });

    test('a weekend or a holiday rolls forward, and says so', () {
      final weekend = check(day(2008, 9, 13)) as StartOk;
      expect(weekend.date, day(2008, 9, 15));
      expect(weekend.rolledFrom, day(2008, 9, 13));
      expect((check(day(2008, 9, 17)) as StartOk).date, day(2008, 9, 18));
    });

    test('the data floor is the first possible day; before it, no prices', () {
      expect((check(floor) as StartOk).date, floor);
      final before = check(day(1929, 10, 24)) as StartBeforeFloor;
      expect(before.floor, floor);
      expect(check(day(2000, 1, 2)), isA<StartBeforeFloor>());
    });

    test('at least 30 days back, including after a roll', () {
      expect(latestStart(today), day(2026, 9, 11));
      expect((check(day(2026, 9, 11)) as StartOk).date, day(2026, 9, 11));
      expect(
        (check(day(2026, 9, 12)) as StartTooRecent).latest,
        day(2026, 9, 11),
      );
      // Saturday 2026-09-05 rolls to Monday 2026-09-07: still fine.
      expect((check(day(2026, 9, 5)) as StartOk).date, day(2026, 9, 7));
      // A future day fails too.
      expect(check(day(2027, 1, 1)), isA<StartTooRecent>());
    });

    test('no session at all: too recent, never an endless walk', () {
      expect(
        checkStart(
          day(2008, 9, 15),
          today: today,
          floor: floor,
          isTripDay: (_) => false,
        ),
        isA<StartTooRecent>(),
      );
      expect(
        yearsAgo(1, today: today, isTripDay: (_) => false),
        isA<DateTime>(),
      );
    });

    test('nothing readable', () {
      expect(check(null), isA<StartUnreadable>());
    });
  });

  test('years ago: the same day, or the trip day before it', () {
    // 2025-10-11 is a Saturday: Friday 10.
    expect(yearsAgo(1, today: today, isTripDay: tripDay), day(2025, 10, 10));
    expect(yearsAgo(5, today: today, isTripDay: tripDay), day(2021, 10, 11));
    expect(
      yearsAgo(10, today: day(2018, 9, 17), isTripDay: tripDay),
      day(2008, 9, 16),
      reason: 'holiday',
    );
    expect(
      yearsAgo(1, today: day(2028, 2, 29), isTripDay: tripDay),
      day(2027, 2, 26),
      reason: '28/02/2027 is a Sunday',
    );
  });

  test('fast-forward: after the trip day, up to yesterday', () {
    final from = day(2008, 10, 3);
    ForwardCheck check(DateTime? d) =>
        checkForward(d, from: from, today: today);
    expect((check(day(2009, 3, 9)) as ForwardOk).target, day(2009, 3, 9));
    expect((check(from) as ForwardNotAfter).from, from);
    expect(check(day(2008, 9, 1)), isA<ForwardNotAfter>());
    expect((check(today) as ForwardTooLate).latest, day(2026, 10, 10));
    expect(check(day(2026, 10, 10)), isA<ForwardOk>());
    expect(check(null), isA<ForwardUnreadable>());
  });
}
