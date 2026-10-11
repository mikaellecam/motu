import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/analytics/returns.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/position.dart';
import 'package:finance_companion/domain/wallet/stop_decision.dart';
import 'package:finance_companion/domain/wallet/trip_summary.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int day) => DateTime.utc(2020, 3, day);
Decimal dec(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(dec(s), Currency.eur);

DailyValue v(int day, String value, [String flow = '0']) =>
    DailyValue(date: d(day), value: eur(value), flow: eur(flow));

List<(DateTime, Money, Money)> rows(List<DailyValue> series) => [
  for (final p in series) (p.date, p.value, p.flow),
];

Fill sold(
  String asset,
  String qty,
  String price,
  int day, {
  String? orderId,
  Currency currency = Currency.usd,
  String fxRate = '0.9',
}) => Fill(
  assetId: asset,
  side: Side.sell,
  date: d(day),
  quantity: Quantity.truncate(dec(qty)),
  price: Price(dec(price), currency),
  fxRate: dec(fxRate),
  fees: const Money.zero(Currency.eur),
  orderId: orderId,
);

JournalEntry entry(StopDecision decision, int day) =>
    JournalEntry(date: d(day), decision: decision.id);

void main() {
  // 10 000 € in, a fall, a recovery and a 1 000 € contribution on the 9th.
  final series = [
    v(2, '10000', '10000'),
    v(3, '9000'),
    v(4, '8000'),
    v(6, '9500'),
    v(9, '10600', '1000'),
  ];

  group('soldEverythingOn', () {
    test('the value less the fees that day, then cash and later flows', () {
      expect(rows(soldEverythingOn(d(4), series, fees: eur('10'))), [
        (d(2), eur('10000'), eur('10000')),
        (d(3), eur('9000'), eur('0')),
        (d(4), eur('7990'), eur('0')),
        (d(6), eur('7990'), eur('0')),
        (d(9), eur('8990'), eur('1000')),
      ]);
    });

    test('a day without a value sells at the last value before it', () {
      // The 5th is a weekend: the 4th's close.
      expect(
        soldEverythingOn(d(5), series, fees: eur('0')).last.value,
        eur('9000'),
      );
    });

    test('a day after the series sells on its last day', () {
      final out = soldEverythingOn(d(20), series, fees: eur('5'));
      expect(rows(out).last, (d(9), eur('10595'), eur('1000')));
    });

    test('a day before the series changes nothing', () {
      expect(
        rows(soldEverythingOn(d(1), series, fees: eur('5'))),
        rows(series),
      );
    });

    test('an empty series stays empty', () {
      expect(soldEverythingOn(d(4), const [], fees: eur('5')), isEmpty);
    });
  });

  group('worstSell', () {
    test('no sell day: none', () {
      expect(worstSell(series, const {}), isNull);
    });

    test('the sell day whose « all sold » line ends lowest', () {
      final worst = worstSell(series, {d(6): eur('0'), d(4): eur('0')})!;
      // All sold on the 4th ends at 9 000 €, on the 6th at 10 500 €.
      expect(worst.date, d(4));
      expect(worst.series.last.value, eur('9000'));
    });

    test('the fees count', () {
      // Selling on the 3rd ends at 9 000 € − 2 000 € of fees + 1 000 €.
      final worst = worstSell(series, {d(3): eur('2000'), d(4): eur('0')})!;
      expect(worst.date, d(3));
    });

    test('a tie goes to the earliest day', () {
      final flat = [v(2, '100', '100'), v(3, '100'), v(4, '100')];
      final worst = worstSell(flat, {d(4): eur('0'), d(3): eur('0')})!;
      expect(worst.date, d(3));
    });

    test('an empty series: none', () {
      expect(worstSell(const [], {d(4): eur('0')}), isNull);
    });
  });

  group('sellAllFees', () {
    final rules = TradingRules(
      fxFeeRate: dec('0.0025'),
      fixedFee: eur('1'),
      fractionalShares: true,
    );
    Position held(String id, String qty) => Position(
      assetId: id,
      quantity: Quantity.truncate(dec(qty)),
      costBasis: dec('100'),
      realisedPnl: Decimal.zero,
    );

    test('the fixed fee per open position, the FX fee off the euro', () {
      final fees = sellAllFees(
        {
          'apple': held('apple', '10'),
          'cac': held('cac', '2'),
          'gone': held('gone', '0'),
        },
        prices: {
          'apple': Price(dec('100'), Currency.usd),
          'cac': Price(dec('50'), Currency.eur),
        },
        fxRate: (c) => c == Currency.usd ? dec('0.9') : Decimal.one,
        rules: rules,
      );
      // apple: 900 € × 0,25 % + 1 € = 3,25 €; cac: 1 €.
      expect(fees, eur('4.25'));
    });

    test('a position worth less than its fees costs only its value', () {
      final fees = sellAllFees(
        {'penny': held('penny', '1')},
        prices: {'penny': Price(dec('0.5'), Currency.eur)},
        fxRate: (_) => Decimal.one,
        rules: rules,
      );
      expect(fees, eur('0.5'));
    });

    test('no position: nothing', () {
      expect(
        sellAllFees(
          const {},
          prices: const {},
          fxRate: (_) => Decimal.one,
          rules: rules,
        ),
        const Money.zero(Currency.eur),
      );
    });

    test('a missing price is an error', () {
      expect(
        () => sellAllFees(
          {'apple': held('apple', '1')},
          prices: const {},
          fxRate: (_) => Decimal.one,
          rules: rules,
        ),
        throwsArgumentError,
      );
    });
  });

  group('movedAfter', () {
    final fills = [
      // The stop's sell of the 4th, filled on the 6th: 5 × 100 $ × 0,9.
      sold('apple', '5', '100', 6, orderId: stopSellId('apple', d(4))),
      // A sell of the user's own on the same asset.
      sold('apple', '1', '90', 6, orderId: 'mine'),
    ];

    test('a sell: the sold shares from their sale to the end', () {
      expect(
        movedAfter(
          entry(StopDecision.sellHalf, 4),
          series: series,
          fills: fills,
          endPrices: {'apple': dec('99')},
        ),
        // 450 € then, 495 € now.
        dec('0.1'),
      );
    });

    test('several assets sold: their total', () {
      expect(
        movedAfter(
          entry(StopDecision.sellAll, 4),
          series: series,
          fills: [
            ...fills,
            sold(
              'cac',
              '10',
              '55',
              6,
              currency: Currency.eur,
              fxRate: '1',
              orderId: stopSellId('cac', d(4)),
            ),
          ],
          endPrices: {'apple': dec('99'), 'cac': dec('50')},
        ),
        // 450 + 550 € then, 495 + 500 € now.
        dec('-0.005'),
      );
    });

    test('a sell not filled yet: nothing', () {
      expect(
        movedAfter(
          entry(StopDecision.sellAll, 6),
          series: series,
          fills: fills,
          endPrices: {'apple': dec('99')},
        ),
        isNull,
      );
    });

    test('a sold asset without an end price: nothing', () {
      expect(
        movedAfter(
          entry(StopDecision.sellHalf, 4),
          series: series,
          fills: fills,
          endPrices: const {},
        ),
        isNull,
      );
    });

    test('« Garder »: the portfolio from that day, contributions aside', () {
      // 8 000 → 9 500 → 10 600 with 1 000 put in: × 1,1875 × 1,0105… = 1,2.
      expect(
        movedAfter(
          entry(StopDecision.hold, 4),
          series: series,
          fills: fills,
          endPrices: const {},
        )!.round(scale: 9),
        dec('0.2'),
      );
    });

    test('« Garder » on the last day: nothing yet', () {
      expect(
        movedAfter(
          entry(StopDecision.hold, 9),
          series: series,
          fills: fills,
          endPrices: const {},
        ),
        isNull,
      );
    });

    test('« Continuer » and unknown entries: nothing', () {
      for (final decision in ['continue', 'something-else']) {
        expect(
          movedAfter(
            JournalEntry(date: d(4), decision: decision),
            series: series,
            fills: fills,
            endPrices: const {},
          ),
          isNull,
        );
      }
    });
  });

  test('a trip order with a reason: its fill from then to the end', () {
    final buy = JournalEntry(date: d(4), decision: 'buy', eventId: 'o-1');
    final bought = Fill(
      assetId: 'apple',
      side: Side.buy,
      date: d(6),
      quantity: Quantity.whole(5),
      price: Price(dec('100'), Currency.usd),
      fxRate: dec('0.9'),
      fees: const Money.zero(Currency.eur),
      orderId: 'o-1',
    );
    expect(buy.isOrder, isTrue);
    expect(filledBy(buy, [bought]).single, same(bought));
    // 450 € then, 495 € now.
    expect(
      movedAfter(
        buy,
        series: series,
        fills: [bought],
        endPrices: {'apple': dec('99')},
      ),
      dec('0.1'),
    );
    expect(
      movedAfter(buy, series: series, fills: const [], endPrices: const {}),
      isNull,
      reason: 'not filled before the end',
    );
  });

  test('sell decisions: a stop\'s sells, and a trip order to sell', () {
    expect(
      [
        for (final decision in [
          'sell_half',
          'sell_all',
          'sell',
          'buy',
          'hold',
          'continue',
        ])
          JournalEntry(date: d(4), decision: decision).sells,
      ],
      [true, true, true, false, false, false],
    );
  });

  test('isSell: the stop answers that sell', () {
    expect(
      [for (final s in StopDecision.values) entry(s, 4).isSell],
      [false, true, true, false],
    );
  });

  group('termsMet', () {
    test('the moments\' terms, first met first, once each', () {
      expect(
        termsMet([
          CompanionLogEntry(CompanionRule.portfolioDrawdown, '', d(9)),
          CompanionLogEntry(CompanionRule.firstLoss, 'apple', d(3)),
          CompanionLogEntry(CompanionRule.positionDrop, 'apple', d(4)),
        ]),
        [
          'volatilite',
          'horizon-de-placement',
          'pire-baisse',
          'diversification',
        ],
      );
    });

    test('no moment: no term', () {
      expect(termsMet(const []), isEmpty);
    });
  });

  group('asDailyValues', () {
    test('each point\'s flow is the money put in since the previous', () {
      final days = asDailyValues([
        ValuePoint(d(2), dec('1000'), eur('1000')),
        ValuePoint(d(3), dec('1100'), eur('1000')),
        ValuePoint(d(4), dec('1300'), eur('1100')),
      ]);
      expect(rows(days), [
        (d(2), eur('1000'), eur('1000')),
        (d(3), eur('1100'), eur('0')),
        (d(4), eur('1300'), eur('100')),
      ]);
      // × 1,1 × (1 200 / 1 100) = 1,2.
      expect(timeWeightedReturn(days).round(scale: 9), dec('0.2'));
    });

    test('values are booked to the cent', () {
      expect(
        asDailyValues([ValuePoint(d(2), dec('10.005'), eur('10'))])
            .single
            .value,
        eur('10'),
      );
    });

    test('no point: no day', () {
      expect(asDailyValues(const []), isEmpty);
    });
  });
}
