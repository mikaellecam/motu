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
