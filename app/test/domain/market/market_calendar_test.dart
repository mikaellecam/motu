import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

/// Paris wall-clock time as a UTC instant. CET = UTC+1 until the last Sunday
/// of March and from the last Sunday of October; CEST = UTC+2 in between.
DateTime paris(int y, int m, int d, int h, int min, {required bool summer}) =>
    DateTime.utc(y, m, d, h - (summer ? 2 : 1), min);

void main() {
  // Easter 2026: Good Friday 3 April, Easter Monday 6 April. Euronext closes
  // on both, NYSE on Good Friday only. New Year's Day 2027 is a Friday.
  final calendar = MarketCalendar({
    Exchange.euronext: {day(2026, 4, 3), day(2026, 4, 6), day(2027, 1, 1)},
    Exchange.nyse: {day(2026, 4, 3), day(2027, 1, 1)},
  });

  group('trading days', () {
    test('weekends are closed everywhere', () {
      for (final exchange in Exchange.values) {
        expect(calendar.isTradingDay(exchange, day(2026, 10, 10)), isFalse);
        expect(calendar.isTradingDay(exchange, day(2026, 10, 11)), isFalse);
        expect(calendar.isTradingDay(exchange, day(2026, 10, 12)), isTrue);
      }
    });

    test('holidays come from the injected calendar, per exchange', () {
      expect(
        calendar.isTradingDay(Exchange.euronext, day(2026, 4, 6)),
        isFalse,
      );
      expect(calendar.isTradingDay(Exchange.nyse, day(2026, 4, 6)), isTrue);
      // Nasdaq got no holidays: every weekday trades.
      expect(calendar.isTradingDay(Exchange.nasdaq, day(2026, 4, 3)), isTrue);
    });

    test('years outside the injected data have weekends only', () {
      expect(calendar.isTradingDay(Exchange.euronext, day(2031, 1, 1)), isTrue);
    });

    test('the time of day is ignored', () {
      expect(
        calendar.isTradingDay(Exchange.euronext, DateTime.utc(2026, 4, 6, 23)),
        isFalse,
      );
    });

    test('next and previous skip weekends and holidays', () {
      const e = Exchange.euronext;
      expect(calendar.nextTradingDay(e, day(2026, 10, 9)), day(2026, 10, 12));
      expect(calendar.nextTradingDay(e, day(2026, 4, 2)), day(2026, 4, 7));
      expect(calendar.previousTradingDay(e, day(2026, 4, 7)), day(2026, 4, 2));
      expect(
        calendar.previousTradingDay(e, day(2026, 10, 12)),
        day(2026, 10, 9),
      );
      expect(
        calendar.nextTradingDay(Exchange.nyse, day(2026, 4, 2)),
        day(2026, 4, 6),
      );
    });

    test('next crosses the year boundary', () {
      expect(
        calendar.nextTradingDay(Exchange.euronext, day(2026, 12, 31)),
        day(2027, 1, 4),
      );
    });

    test('rolling keeps trading days and moves the others', () {
      const e = Exchange.euronext;
      expect(calendar.onOrAfter(e, day(2026, 10, 12)), day(2026, 10, 12));
      expect(calendar.onOrAfter(e, day(2026, 10, 10)), day(2026, 10, 12));
      expect(calendar.onOrAfter(e, day(2026, 4, 3)), day(2026, 4, 7));
      expect(calendar.onOrBefore(e, day(2026, 10, 12)), day(2026, 10, 12));
      expect(calendar.onOrBefore(e, day(2026, 10, 11)), day(2026, 10, 9));
      expect(calendar.onOrBefore(e, day(2026, 4, 6)), day(2026, 4, 2));
    });
  });

  group('market hours', () {
    test('Euronext trades 09:00 to 17:30 Paris, end excluded', () {
      const e = Exchange.euronext;
      bool openAt(int h, int m) =>
          calendar.isOpen(e, paris(2026, 4, 7, h, m, summer: true));
      expect(openAt(8, 59), isFalse);
      expect(openAt(9, 0), isTrue);
      expect(openAt(17, 29), isTrue);
      expect(openAt(17, 30), isFalse);
    });

    test('Euronext follows Paris across its own DST change', () {
      // 07:30 UTC is 08:30 Paris on Friday 27 March (CET), 09:30 on Monday 30
      // March (CEST).
      const e = Exchange.euronext;
      expect(calendar.isOpen(e, DateTime.utc(2026, 3, 27, 7, 30)), isFalse);
      expect(calendar.isOpen(e, DateTime.utc(2026, 3, 30, 7, 30)), isTrue);
    });

    test('NYSE trades 15:30 to 22:00 Paris in a normal week', () {
      const e = Exchange.nyse;
      bool openAt(int h, int m) =>
          calendar.isOpen(e, paris(2026, 4, 7, h, m, summer: true));
      expect(openAt(14, 30), isFalse);
      expect(openAt(15, 29), isFalse);
      expect(openAt(15, 30), isTrue);
      expect(openAt(21, 59), isTrue);
      expect(openAt(22, 0), isFalse);
    });

    test('late March: US is on summer time, Europe not yet → 14:30 to 21:00 '
        'Paris', () {
      const e = Exchange.nyse;
      bool openAt(int h, int m) =>
          calendar.isOpen(e, paris(2026, 3, 10, h, m, summer: false));
      expect(openAt(14, 29), isFalse);
      expect(openAt(14, 30), isTrue);
      expect(openAt(20, 59), isTrue);
      expect(openAt(21, 0), isFalse);
    });

    test('late October: Europe is back on winter time, US not yet → 14:30 to '
        '21:00 Paris', () {
      const e = Exchange.nasdaq;
      bool openAt(int h, int m) =>
          calendar.isOpen(e, paris(2026, 10, 27, h, m, summer: false));
      expect(openAt(14, 29), isFalse);
      expect(openAt(14, 30), isTrue);
      expect(openAt(21, 0), isFalse);
      // From 2 November both are on winter time again: 15:30 Paris.
      expect(
        calendar.isOpen(e, paris(2026, 11, 3, 14, 30, summer: false)),
        isFalse,
      );
      expect(
        calendar.isOpen(e, paris(2026, 11, 3, 15, 30, summer: false)),
        isTrue,
      );
    });

    test('OTC (ADRs) keeps New York hours', () {
      bool openAt(int h, int m) =>
          calendar.isOpen(Exchange.otc, paris(2026, 4, 7, h, m, summer: true));
      expect(openAt(15, 29), isFalse);
      expect(openAt(15, 30), isTrue);
      expect(openAt(22, 0), isFalse);
    });

    test('closed on weekends and holidays, even within session hours', () {
      expect(
        calendar.isOpen(Exchange.nyse, paris(2026, 4, 3, 16, 0, summer: true)),
        isFalse,
      );
      expect(
        calendar.isOpen(
          Exchange.euronext,
          paris(2026, 10, 10, 10, 0, summer: true),
        ),
        isFalse,
      );
    });

    test('a session is judged on the exchange date, not the UTC date', () {
      // Monday 12 Oct, 15:59 New York = 19:59 UTC: still Monday everywhere.
      // Tuesday 13 Oct 00:30 Paris = Monday 22:30 UTC: NYSE closed (after 16:00).
      expect(
        calendar.isOpen(Exchange.nyse, DateTime.utc(2026, 10, 12, 19, 59)),
        isTrue,
      );
      expect(
        calendar.isOpen(Exchange.nyse, DateTime.utc(2026, 10, 12, 22, 30)),
        isFalse,
      );
    });
  });

  test('closeAt: the session close as an instant, DST on each side', () {
    // 16:00 in New York: 22:00 in Paris most of the year, 21:00 in the week
    // the US is on summer time and Europe is not yet (2026-03-09..28).
    expect(
      calendar.closeAt(Exchange.nyse, day(2026, 10, 7)),
      paris(2026, 10, 7, 22, 0, summer: true),
    );
    expect(
      calendar.closeAt(Exchange.nyse, day(2026, 3, 20)),
      paris(2026, 3, 20, 21, 0, summer: false),
    );
    expect(
      calendar.closeAt(Exchange.euronext, day(2026, 12, 1)),
      paris(2026, 12, 1, 17, 30, summer: false),
    );
  });

  group('early closes', () {
    // New York is on EST (UTC−5) on the day after Thanksgiving, on EDT
    // (UTC−4) on 3 July. Thanksgiving 2026 is a holiday.
    final early = MarketCalendar(
      {
        Exchange.nyse: {day(2026, 11, 26)},
      },
      earlyCloses: {
        Exchange.nyse: {
          day(2025, 7, 3): (13, 0),
          day(2026, 11, 27): (13, 0),
          day(2005, 6, 1): (15, 56),
        },
      },
    );
    const e = Exchange.nyse;

    test('closeAt: 13:00 in New York, DST on each side', () {
      expect(
        early.closeAt(e, day(2026, 11, 27)),
        DateTime.utc(2026, 11, 27, 18),
      );
      expect(early.closeAt(e, day(2025, 7, 3)), DateTime.utc(2025, 7, 3, 17));
      expect(
        early.closeAt(e, day(2005, 6, 1)),
        DateTime.utc(2005, 6, 1, 19, 56),
      );
      // The open does not move.
      expect(
        early.openAt(e, day(2026, 11, 27)),
        DateTime.utc(2026, 11, 27, 14, 30),
      );
    });

    test('a market order at 12:00 finds the market open: it fills now', () {
      expect(early.isOpen(e, DateTime.utc(2026, 11, 27, 17)), isTrue);
      expect(early.isOpen(e, DateTime.utc(2026, 11, 27, 17, 59)), isTrue);
    });

    test('from 13:00 the market is closed: an order waits for Monday', () {
      expect(early.isOpen(e, DateTime.utc(2026, 11, 27, 18)), isFalse);
      expect(early.isOpen(e, DateTime.utc(2026, 11, 27, 20)), isFalse);
      expect(
        early.nextOpen(e, DateTime.utc(2026, 11, 27, 18, 30)),
        DateTime.utc(2026, 11, 30, 14, 30),
      );
      expect(
        early.nextOpen(e, DateTime.utc(2025, 7, 3, 17)),
        DateTime.utc(2025, 7, 4, 13, 30),
        reason: 'no holiday injected for 4 July 2025',
      );
    });

    test('per exchange and per day: the others close at 16:00', () {
      expect(
        early.closeAt(Exchange.nasdaq, day(2026, 11, 27)),
        DateTime.utc(2026, 11, 27, 21),
      );
      expect(
        early.isOpen(Exchange.nasdaq, DateTime.utc(2026, 11, 27, 20)),
        isTrue,
      );
      expect(
        early.closeAt(e, day(2026, 11, 20)),
        DateTime.utc(2026, 11, 20, 21),
      );
      expect(early.isOpen(e, DateTime.utc(2026, 11, 20, 20)), isTrue);
    });

    test('a year with no injected early close closes at 16:00', () {
      // The day after Thanksgiving 2027.
      expect(
        early.closeAt(e, day(2027, 11, 26)),
        DateTime.utc(2027, 11, 26, 21),
      );
      expect(early.isOpen(e, DateTime.utc(2027, 11, 26, 20, 59)), isTrue);
      expect(
        calendar.closeAt(e, day(2026, 11, 27)),
        DateTime.utc(2026, 11, 27, 21),
      );
    });

    test('the time of day of an injected date is ignored', () {
      final c = MarketCalendar(
        const {},
        earlyCloses: {
          e: {DateTime.utc(2026, 12, 24, 15): (13, 0)},
        },
      );
      expect(
        c.closeAt(e, DateTime.utc(2026, 12, 24, 9)),
        DateTime.utc(2026, 12, 24, 18),
      );
    });
  });

  test('openAt: the session open as an instant, DST on each side', () {
    expect(
      calendar.openAt(Exchange.nasdaq, day(2026, 10, 7)),
      paris(2026, 10, 7, 15, 30, summer: true),
    );
    expect(
      calendar.openAt(Exchange.nyse, day(2026, 3, 20)),
      paris(2026, 3, 20, 14, 30, summer: false),
    );
    expect(
      calendar.openAt(Exchange.euronext, day(2026, 12, 1)),
      paris(2026, 12, 1, 9, 0, summer: false),
    );
  });

  test('every instant reads in the device time zone', () {
    // As the screens show them: toLocal() is the device's time, not UTC.
    for (final instant in [
      calendar.openAt(Exchange.nasdaq, day(2026, 10, 7)),
      calendar.closeAt(Exchange.nasdaq, day(2026, 10, 7)),
      calendar.nextOpen(Exchange.nasdaq, day(2026, 10, 7)),
    ]) {
      expect(
        instant.toLocal(),
        DateTime.fromMillisecondsSinceEpoch(instant.millisecondsSinceEpoch),
      );
    }
  });

  group('next open', () {
    test('before the open: today at the open', () {
      expect(
        calendar.nextOpen(
          Exchange.nyse,
          paris(2026, 4, 7, 10, 0, summer: true),
        ),
        paris(2026, 4, 7, 15, 30, summer: true),
      );
    });

    test('during or after the session: the next trading day', () {
      expect(
        calendar.nextOpen(
          Exchange.nyse,
          paris(2026, 4, 7, 16, 0, summer: true),
        ),
        paris(2026, 4, 8, 15, 30, summer: true),
      );
      expect(
        calendar.nextOpen(
          Exchange.euronext,
          paris(2026, 4, 2, 18, 0, summer: true),
        ),
        paris(2026, 4, 7, 9, 0, summer: true),
      );
    });

    test('Friday evening in a DST-mismatch week opens Monday 14:30 Paris', () {
      expect(
        calendar.nextOpen(
          Exchange.nyse,
          paris(2026, 3, 13, 22, 0, summer: false),
        ),
        paris(2026, 3, 16, 14, 30, summer: false),
      );
    });

    test('exactly at the open: that open is not "next"', () {
      final open = paris(2026, 4, 7, 9, 0, summer: true);
      expect(
        calendar.nextOpen(Exchange.euronext, open),
        paris(2026, 4, 8, 9, 0, summer: true),
      );
    });
  });
}
