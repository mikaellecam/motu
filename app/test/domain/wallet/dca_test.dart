import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/livret/livret_interest.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/domain/market/price_bar.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String amount) => Money.book(d(amount), Currency.eur);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);

PriceBar bar(DateTime date, String close, [Currency c = Currency.eur]) =>
    PriceBar(
      date: date,
      open: d(close),
      high: d(close),
      low: d(close),
      close: d(close),
      volume: 0,
      currency: c,
    );

final noFees = TradingRules(
  fxFeeRate: d('0.0015'),
  fixedFee: const Money.zero(Currency.eur),
  fractionalShares: true,
);

Decimal one(DateTime _) => Decimal.one;

void main() {
  group('dcaSchedule', () {
    final calendar = MarketCalendar({
      Exchange.euronext: {day(2026, 4, 3), day(2026, 4, 6)},
    });

    test(
      'monthly on the start day, clamped to short months, rolled forward',
      () {
        expect(
          dcaSchedule(
            start: day(2025, 1, 31),
            end: day(2025, 6, 30),
            frequency: DcaFrequency.monthly,
            calendar: calendar,
            exchange: Exchange.euronext,
          ),
          [
            day(2025, 1, 31),
            day(2025, 2, 28),
            day(2025, 3, 31),
            day(2025, 4, 30),
            day(2025, 6, 2), // Saturday 31 May → Monday
            day(2025, 6, 30),
          ],
        );
      },
    );

    test('a holiday rolls to the next trading day', () {
      // 6 April 2026 is Easter Monday on Euronext.
      expect(
        dcaSchedule(
          start: day(2026, 3, 6),
          end: day(2026, 5, 6),
          frequency: DcaFrequency.monthly,
          calendar: calendar,
          exchange: Exchange.euronext,
        ),
        [day(2026, 3, 6), day(2026, 4, 7), day(2026, 5, 6)],
      );
    });

    test('weekly on the start weekday', () {
      expect(
        dcaSchedule(
          start: day(2026, 3, 18),
          end: day(2026, 4, 8),
          frequency: DcaFrequency.weekly,
          calendar: calendar,
          exchange: Exchange.euronext,
        ),
        [day(2026, 3, 18), day(2026, 3, 25), day(2026, 4, 1), day(2026, 4, 8)],
      );
    });

    test('a date that rolls past the end is dropped', () {
      // Saturday 30 May → Monday 1 June, after the end.
      expect(
        dcaSchedule(
          start: day(2026, 4, 30),
          end: day(2026, 5, 31),
          frequency: DcaFrequency.monthly,
          calendar: calendar,
          exchange: Exchange.euronext,
        ),
        [day(2026, 4, 30)],
      );
    });

    test('a start after the end gives nothing', () {
      expect(
        dcaSchedule(
          start: day(2026, 5, 1),
          end: day(2026, 4, 1),
          frequency: DcaFrequency.weekly,
          calendar: calendar,
          exchange: Exchange.euronext,
        ),
        isEmpty,
      );
    });
  });

  // October 2026, New York on summer time: the Nasdaq opens at 13:30 UTC;
  // Paris too: Euronext opens at 07:00 UTC. Thanksgiving closes New York on
  // Thursday 26 November.
  group('firstPurchaseDay', () {
    final calendar = MarketCalendar({
      Exchange.nasdaq: {day(2026, 11, 26)},
      Exchange.euronext: {day(2026, 4, 3), day(2026, 4, 6)},
    });
    DateTime first(
      DateTime walletDay, {
      DateTime? placedAt,
      Exchange exchange = Exchange.nasdaq,
    }) => firstPurchaseDay(
      calendar: calendar,
      exchange: exchange,
      walletDay: walletDay,
      placedAt: placedAt,
    );

    test('set up before the open: that session', () {
      expect(
        first(day(2026, 10, 5), placedAt: DateTime.utc(2026, 10, 6, 12)),
        day(2026, 10, 6),
      );
    });

    test('set up during a session: its prices are known, the next one', () {
      expect(
        first(day(2026, 10, 5), placedAt: DateTime.utc(2026, 10, 6, 15)),
        day(2026, 10, 7),
      );
      // At the open itself, the opening price is known.
      expect(
        first(day(2026, 10, 5), placedAt: DateTime.utc(2026, 10, 6, 13, 30)),
        day(2026, 10, 7),
      );
    });

    test('set up after the close: the next session', () {
      expect(
        first(day(2026, 10, 6), placedAt: DateTime.utc(2026, 10, 6, 21)),
        day(2026, 10, 7),
      );
      // 22:00 in New York is already Wednesday in UTC: Wednesday's open.
      expect(
        first(day(2026, 10, 6), placedAt: DateTime.utc(2026, 10, 7, 2)),
        day(2026, 10, 7),
      );
    });

    test('a weekend or a holiday rolls to the next session', () {
      expect(
        first(day(2026, 10, 9), placedAt: DateTime.utc(2026, 10, 10, 12)),
        day(2026, 10, 12),
      );
      expect(
        first(day(2026, 11, 25), placedAt: DateTime.utc(2026, 11, 25, 22)),
        day(2026, 11, 27),
      );
    });

    test('each exchange opens at its own time', () {
      // 08:00 in Paris, before Euronext opens; 10:00, after.
      expect(
        first(
          day(2026, 10, 5),
          placedAt: DateTime.utc(2026, 10, 6, 6),
          exchange: Exchange.euronext,
        ),
        day(2026, 10, 6),
      );
      expect(
        first(
          day(2026, 10, 5),
          placedAt: DateTime.utc(2026, 10, 6, 8),
          exchange: Exchange.euronext,
        ),
        day(2026, 10, 7),
      );
    });

    test('never on a day the wallet already booked', () {
      // A live wallet created on Tuesday morning has Tuesday as its first
      // day: it books only the sessions after it.
      expect(
        first(day(2026, 10, 6), placedAt: DateTime.utc(2026, 10, 6, 12)),
        day(2026, 10, 7),
      );
    });

    test('a trip: the session after its day', () {
      expect(first(day(2026, 10, 9)), day(2026, 10, 12));
      expect(first(day(2026, 11, 25)), day(2026, 11, 27));
      // Easter: Euronext closed on Friday 3 and Monday 6 April.
      expect(
        first(day(2026, 4, 2), exchange: Exchange.euronext),
        day(2026, 4, 7),
      );
    });
  });

  group('nextPurchaseDay', () {
    final calendar = MarketCalendar({
      Exchange.nasdaq: {day(2026, 11, 26)},
    });
    DcaPlan plan(DateTime start, DcaFrequency frequency) => DcaPlan(
      id: 'p',
      assetId: 'apple',
      amount: eur('100'),
      frequency: frequency,
      start: start,
    );
    DateTime next(DcaPlan plan, DateTime after) => nextPurchaseDay(
      plan,
      after: after,
      calendar: calendar,
      exchange: Exchange.nasdaq,
    );

    test('before the first purchase: the first purchase', () {
      final p = plan(day(2026, 10, 7), DcaFrequency.monthly);
      expect(next(p, day(2026, 10, 5)), day(2026, 10, 7));
      expect(next(p, day(2026, 10, 6)), day(2026, 10, 7));
    });

    test('then the schedule, as the simulator follows it', () {
      final monthly = plan(day(2026, 10, 7), DcaFrequency.monthly);
      // Saturday 7 November rolls to Monday 9.
      expect(next(monthly, day(2026, 10, 7)), day(2026, 11, 9));
      expect(next(monthly, day(2026, 11, 9)), day(2026, 12, 7));
      final weekly = plan(day(2026, 10, 7), DcaFrequency.weekly);
      expect(next(weekly, day(2026, 10, 7)), day(2026, 10, 14));
      // Thanksgiving: Thursday 26 November rolls to Friday 27.
      final thursdays = plan(day(2026, 11, 19), DcaFrequency.weekly);
      expect(next(thursdays, day(2026, 11, 19)), day(2026, 11, 27));
    });

    test('a month-end start keeps to the last day of shorter months', () {
      final p = plan(day(2026, 3, 31), DcaFrequency.monthly);
      expect(next(p, day(2026, 3, 31)), day(2026, 4, 30));
      // Sunday 31 May rolls to Monday 1 June.
      expect(next(p, day(2026, 4, 30)), day(2026, 6, 1));
    });

    test('a plan years old', () {
      final p = plan(day(2020, 1, 6), DcaFrequency.weekly);
      expect(next(p, day(2026, 10, 6)), day(2026, 10, 12));
    });
  });

  group('investFlows', () {
    // A V-shaped market: 10 → 5 → 10.
    final bars = [
      bar(day(2025, 1, 6), '10'),
      bar(day(2025, 2, 6), '5'),
      bar(day(2025, 3, 6), '10'),
    ];
    final monthly = [for (final b in bars) Flow(b.date, eur('100'))];

    test('DCA buys more when the price is low', () {
      final run = investFlows(
        monthly,
        bars: bars,
        fxRate: one,
        rules: noFees,
        end: day(2025, 3, 6),
      );
      expect(run.purchases.map((p) => p.quantity.toDecimal()), [
        d('10'),
        d('20'),
        d('10'),
      ]);
      expect(run.invested, eur('300'));
      expect(run.quantity.toDecimal(), d('40'));
      expect(run.finalValue, d('400'));
      expect(run.gain, d('100'));
      expect(run.gainRatio, d('0.333333333333'));
    });

    test('lump sum: the same total on the first day', () {
      final run = investFlows(
        [Flow(day(2025, 1, 6), eur('300'))],
        bars: bars,
        fxRate: one,
        rules: noFees,
        end: day(2025, 3, 6),
      );
      expect(run.purchases, hasLength(1));
      expect(run.finalValue, d('300'));
      expect(run.gain, Decimal.zero);
    });

    test('the series pairs each day\'s value with the money put in so far', () {
      final run = investFlows(
        monthly,
        bars: bars,
        fxRate: one,
        rules: noFees,
        end: day(2025, 3, 6),
      );
      expect(run.series.map((p) => p.date), bars.map((b) => b.date));
      expect(run.series.map((p) => p.value), [d('100'), d('150'), d('400')]);
      expect(run.series.map((p) => p.invested), [
        eur('100'),
        eur('200'),
        eur('300'),
      ]);
    });

    test('a flow on a day without a bar buys at the next bar', () {
      final run = investFlows(
        [Flow(day(2025, 1, 4), eur('100'))],
        bars: bars,
        fxRate: one,
        rules: noFees,
        end: day(2025, 3, 6),
      );
      expect(run.purchases.single.date, day(2025, 1, 6));
    });

    test('flows after the end, or after the last bar, are not invested', () {
      final run = investFlows(
        [Flow(day(2025, 1, 6), eur('100')), Flow(day(2025, 3, 7), eur('100'))],
        bars: bars,
        fxRate: one,
        rules: noFees,
        end: day(2025, 3, 10),
      );
      expect(run.purchases, hasLength(1));
      expect(run.invested, eur('100'));
    });

    test('fees come out of each amount (BRIEF §7.12)', () {
      final rules = TradingRules(
        fxFeeRate: Decimal.zero,
        fixedFee: eur('1'),
        fractionalShares: true,
      );
      final run = investFlows(
        [Flow(day(2025, 1, 6), eur('100'))],
        bars: bars,
        fxRate: one,
        rules: rules,
        end: day(2025, 1, 6),
      );
      expect(run.purchases.single.fees, eur('1'));
      expect(run.purchases.single.quantity.toDecimal(), d('9.9'));
      expect(run.invested, eur('100'));
    });

    test(
      'a USD asset: FX fee inside the amount, value converted at each date',
      () {
        final usdBars = [
          bar(day(2025, 1, 6), '100', Currency.usd),
          bar(day(2025, 2, 6), '110', Currency.usd),
        ];
        Decimal fx(DateTime date) => date.month == 1 ? d('0.9') : d('0.95');
        final run = investFlows(
          [Flow(day(2025, 1, 6), eur('100'))],
          bars: usdBars,
          fxRate: fx,
          rules: noFees,
          end: day(2025, 2, 6),
        );
        final purchase = run.purchases.single;
        // notional + 0,15 % of it = 100 € → 99,85 € of shares, 0,15 € of fees.
        expect(purchase.fees, eur('0.15'));
        expect(purchase.quantity.toDecimal(), d('1.109444'));
        // 1,109444 × 110 × 0,95.
        expect(run.finalValue, d('115.936898'));
      },
    );

    test('an amount that does not cover the fees is an error', () {
      final rules = TradingRules(
        fxFeeRate: Decimal.zero,
        fixedFee: eur('1'),
        fractionalShares: true,
      );
      expect(
        () => investFlows(
          [Flow(day(2025, 1, 6), eur('1'))],
          bars: bars,
          fxRate: one,
          rules: rules,
          end: day(2025, 1, 6),
        ),
        throwsArgumentError,
      );
    });

    test('whole-share rules are not supported here', () {
      final rules = TradingRules(
        fxFeeRate: Decimal.zero,
        fixedFee: eur('0'),
        fractionalShares: false,
      );
      expect(
        () => investFlows(
          monthly,
          bars: bars,
          fxRate: one,
          rules: rules,
          end: day(2025, 3, 6),
        ),
        throwsArgumentError,
      );
    });

    test('no flow: nothing invested, no ratio', () {
      final run = investFlows(
        const [],
        bars: bars,
        fxRate: one,
        rules: noFees,
        end: day(2025, 3, 6),
      );
      expect(run.invested, eur('0'));
      expect(run.finalValue, Decimal.zero);
      expect(run.gainRatio, isNull);
      expect(run.series, isEmpty);
    });
  });

  group('livretFlows', () {
    final rates = [LivretRate(day(2000, 1, 1), d('0.03'))];
    final ceilings = [
      LivretCeiling(day(2000, 1, 1), eur('15300')),
      LivretCeiling(day(2012, 10, 1), eur('19125')),
      LivretCeiling(day(2013, 1, 1), eur('22950')),
    ];

    test('the same flows earn Livret interest', () {
      final run = livretFlows(
        [Flow(day(2025, 1, 10), eur('1000'))],
        rates: rates,
        ceilings: ceilings,
        dates: [day(2025, 1, 10), day(2025, 2, 1), day(2025, 3, 1)],
      );
      // Jan 16–31 and Feb 1–15 and Feb 16–28: 3 × 1,25 €.
      expect(run.finalValue, d('1003.75'));
      expect(run.invested, eur('1000'));
      expect(run.capped, isFalse);
      expect(run.series.map((p) => p.value), [
        d('1000'),
        d('1001.25'),
        d('1003.75'),
      ]);
    });

    test('money above the ceiling of the day stays as cash', () {
      final run = livretFlows(
        [Flow(day(2012, 6, 1), eur('20000'))],
        rates: rates,
        ceilings: ceilings,
        dates: [day(2012, 6, 1)],
      );
      expect(run.capped, isTrue);
      expect(run.uninvested, eur('4700'));
      expect(run.finalValue, d('20000'));
    });

    test('cash kept out goes in when the ceiling rises', () {
      // 4 700 € stay out under 15 300 €. 3 825 € go in on 1 October 2012
      // (19 125 €), the last 875 € on 1 January 2013 (22 950 €).
      List<Flow> flows() => [Flow(day(2012, 6, 1), eur('20000'))];
      final partial = livretFlows(
        flows(),
        rates: rates,
        ceilings: ceilings,
        dates: [day(2012, 6, 1), day(2012, 12, 1)],
      );
      expect(partial.uninvested, eur('875'));

      final dates = [day(2012, 6, 1), day(2013, 1, 1)];
      final run = livretFlows(
        flows(),
        rates: rates,
        ceilings: ceilings,
        dates: dates,
      );
      final flat = livretFlows(
        flows(),
        rates: rates,
        ceilings: [ceilings.first],
        dates: dates,
      );
      expect(run.uninvested, eur('0'));
      expect(run.capped, isFalse);
      expect(run.invested, eur('20000'));
      // The 3 825 € earn from 16 October: five fortnights at 3 %, 23,906 €,
      // credited in cents on 31 December.
      expect(run.finalValue - flat.finalValue, d('23.91'));
    });

    test('the ceiling of each date applies', () {
      final run = livretFlows(
        [Flow(day(2014, 6, 2), eur('20000'))],
        rates: rates,
        ceilings: ceilings,
        dates: [day(2014, 6, 2)],
      );
      expect(run.capped, isFalse);
    });

    test('no flow: an empty run', () {
      final run = livretFlows(
        const [],
        rates: rates,
        ceilings: ceilings,
        dates: [day(2025, 1, 1)],
      );
      expect(run.finalValue, Decimal.zero);
      expect(run.series.single.value, Decimal.zero);
    });

    test('no date to value: an empty series', () {
      final run = livretFlows(
        [Flow(day(2025, 1, 10), eur('10'))],
        rates: rates,
        ceilings: ceilings,
        dates: const [],
      );
      expect(run.series, isEmpty);
      expect(run.finalValue, Decimal.zero);
    });

    test('a date without a known ceiling is an error', () {
      expect(
        () => livretFlows(
          [Flow(day(1999, 6, 1), eur('10'))],
          rates: rates,
          ceilings: ceilings,
          dates: [day(1999, 6, 1)],
        ),
        throwsArgumentError,
      );
    });
  });
}
