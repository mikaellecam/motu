import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/companion/events.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:finance_companion/domain/learning/profile_rules.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int n) => DateTime.utc(2026, 1, 1).add(Duration(days: n));

final medium = MomentThresholds(concentration: d('0.40'));

HoldingFacts holding(
  String asset,
  String price, {
  String weight = '0.1',
  String? pnl = '0',
  Currency currency = Currency.eur,
}) => HoldingFacts(
  assetId: asset,
  price: Price(d(price), currency),
  weight: d(weight),
  pnlRatio: pnl == null ? null : d(pnl),
);

DaySnapshot snap(
  int n, {
  String value = '1000',
  String flow = '0',
  String cashWeight = '0',
  List<HoldingFacts> holdings = const [],
  List<SellFact> sells = const [],
  String? usdRate,
  Map<String, String> prices = const {},
}) => DaySnapshot(
  date: day(n),
  value: d(value),
  flow: d(flow),
  cashWeight: d(cashWeight),
  holdings: holdings,
  sells: sells,
  usdRate: usdRate == null ? null : d(usdRate),
  priceOf: (asset) =>
      prices[asset] == null ? null : Price(d(prices[asset]!), Currency.eur),
);

/// Observes [days] in order, logging every moment as the app would.
List<Moment> run(
  List<DaySnapshot> days, {
  List<CompanionLogEntry> log = const [],
  MomentThresholds? thresholds,
}) {
  var tracker = CompanionTracker.empty();
  final entries = [...log];
  final moments = <Moment>[];
  for (final snapshot in days) {
    final (next, fired) = tracker.observe(
      snapshot,
      log: entries,
      thresholds: thresholds ?? medium,
    );
    tracker = next;
    moments.addAll(fired);
    entries.addAll(fired.map((m) => m.logEntry));
  }
  return moments;
}

Iterable<(CompanionRule, DateTime)> fired(List<Moment> moments) =>
    moments.map((m) => (m.rule, m.date));

void main() {
  group('first_loss: once', () {
    test('fires the first time a position is below −5 %', () {
      final moments = run([
        snap(0, holdings: [holding('cw8', '96', pnl: '-0.04')]),
        snap(1, holdings: [holding('cw8', '94', pnl: '-0.06')]),
        snap(2, holdings: [holding('mc', '80', pnl: '-0.2')]),
      ]);
      expect(fired(moments), [(CompanionRule.firstLoss, day(1))]);
      expect(moments.single.params, {'assetId': 'cw8'});
    });

    test('two losing positions the same day: one moment', () {
      final moments = run([
        snap(
          0,
          holdings: [
            holding('cw8', '90', pnl: '-0.1'),
            holding('mc', '80', pnl: '-0.2'),
          ],
        ),
      ]);
      expect(fired(moments), [(CompanionRule.firstLoss, day(0))]);
    });

    test('never again once logged', () {
      final moments = run(
        [
          snap(0, holdings: [holding('cw8', '90', pnl: '-0.1')]),
        ],
        log: [
          CompanionLogEntry(CompanionRule.firstLoss, '', DateTime.utc(2020)),
        ],
      );
      expect(moments, isEmpty);
    });

    test('a position without a P&L ratio is ignored', () {
      expect(
        run([
          snap(0, holdings: [holding('gift', '10', pnl: null)]),
        ]),
        isEmpty,
      );
    });
  });

  group(
    'position_drop: −15 % from the peak since purchase, 30 days per position',
    () {
      List<DaySnapshot> path(String asset, List<(int, String)> prices) => [
        for (final (n, price) in prices)
          snap(n, holdings: [holding(asset, price)]),
      ];

      test('fires on the drop, then waits 30 days', () {
        final moments = run(
          path('cw8', [
            (0, '100'),
            (1, '110'),
            (2, '93'), // 93 / 110 − 1 = −15.5 %
            (3, '90'),
            (31, '90'),
            (32, '90'),
          ]),
        );
        expect(fired(moments), [
          (CompanionRule.positionDrop, day(2)),
          (CompanionRule.positionDrop, day(32)),
        ]);
        expect(moments.first.key, 'cw8');
        expect(moments.first.params['drop'], d('-0.154545454545'));
      });

      test('each position has its own cooldown', () {
        final moments = run([
          snap(0, holdings: [holding('a', '100'), holding('b', '100')]),
          snap(1, holdings: [holding('a', '80'), holding('b', '100')]),
          snap(2, holdings: [holding('a', '80'), holding('b', '80')]),
        ]);
        expect(moments.map((m) => m.key), ['a', 'b']);
      });

      test('the peak restarts when the position is bought again', () {
        final moments = run([
          snap(0, holdings: [holding('cw8', '200')]),
          snap(1), // sold
          snap(2, holdings: [holding('cw8', '100')]),
          snap(3, holdings: [holding('cw8', '90')]),
        ]);
        expect(moments, isEmpty);
      });
    },
  );

  group('portfolio_drawdown: −10 % from the peak, 30 days', () {
    test('fires from the peak of performance', () {
      final moments = run([
        snap(0, value: '1000', flow: '1000'),
        snap(1, value: '1100'),
        snap(2, value: '990'), // −10 %
        snap(3, value: '950'),
      ]);
      expect(fired(moments), [(CompanionRule.portfolioDrawdown, day(2))]);
      expect(moments.single.params['drawdown'], d('-0.1'));
    });

    test('a contribution does not hide a fall', () {
      // −10 % on 1 000 €, the same day 200 € arrive: 1 100 € in value.
      final moments = run([
        snap(0, value: '1000', flow: '1000'),
        snap(1, value: '1100', flow: '200'),
      ]);
      expect(fired(moments), [(CompanionRule.portfolioDrawdown, day(1))]);
    });

    test('an empty wallet has no performance to fall from', () {
      expect(run([snap(0, value: '0'), snap(1, value: '0')]), isEmpty);
    });
  });

  group('concentration: one position above the threshold, 14 days', () {
    test('40 % for medium comfort', () {
      final moments = run([
        snap(0, holdings: [holding('cw8', '100', weight: '0.40')]),
        snap(1, holdings: [holding('cw8', '100', weight: '0.41')]),
        snap(10, holdings: [holding('cw8', '100', weight: '0.5')]),
        snap(15, holdings: [holding('cw8', '100', weight: '0.5')]),
      ]);
      expect(fired(moments), [
        (CompanionRule.concentration, day(1)),
        (CompanionRule.concentration, day(15)),
      ]);
      expect(moments.first.params, {'assetId': 'cw8', 'weight': d('0.41')});
    });

    test('30 % for low comfort', () {
      final low = MomentThresholds(concentration: d('0.30'));
      final moments = run([
        snap(0, holdings: [holding('cw8', '100', weight: '0.35')]),
      ], thresholds: low);
      expect(fired(moments), [(CompanionRule.concentration, day(0))]);
    });
  });

  group('idle_cash: above 25 % for more than 30 days, 30 days', () {
    test('fires after 30 days in a row, then waits', () {
      final moments = run([
        for (var n = 0; n <= 70; n++) snap(n, cashWeight: '0.3'),
      ]);
      expect(fired(moments), [
        (CompanionRule.idleCash, day(31)),
        (CompanionRule.idleCash, day(61)),
      ]);
    });

    test('a day below the threshold restarts the count', () {
      final moments = run([
        for (var n = 0; n <= 40; n++)
          snap(n, cashWeight: n == 20 ? '0.1' : '0.3'),
      ]);
      expect(moments, isEmpty);
    });
  });

  group('panic_sell: a sell soon after −15 %, revisited 3 months later', () {
    // These positions also trigger first_loss; it already happened.
    final firstLossDone = [
      CompanionLogEntry(CompanionRule.firstLoss, '', DateTime.utc(2020)),
    ];

    test('fires on the sell, then the follow-up three months later', () {
      final moments = run(log: firstLossDone, [
        snap(0, holdings: [holding('cw8', '84', pnl: '-0.16')]),
        snap(
          3,
          holdings: [holding('cw8', '86', pnl: '-0.14')],
          sells: [SellFact('cw8', Price(d('86'), Currency.eur))],
        ),
        snap(40),
        snap(92, prices: {'cw8': '100'}), // 3 April
        snap(93, prices: {'cw8': '100'}), // 4 April: sold on 4 January
        snap(200, prices: {'cw8': '100'}),
      ]);
      expect(fired(moments), [
        (CompanionRule.panicSell, day(3)),
        (CompanionRule.panicSellFollowUp, day(93)),
      ]);
      expect(moments[0].key, 'cw8|2026-01-04');
      expect(moments[1].key, 'cw8|2026-01-04');
      expect(moments[1].params, {
        'assetId': 'cw8',
        'sellPrice': Price(d('86'), Currency.eur),
        'priceNow': Price(d('100'), Currency.eur),
        'change': d('0.162790697674'),
      });
    });

    test('a sell more than 10 observations after the fall is not panic', () {
      final moments = run(log: firstLossDone, [
        snap(0, holdings: [holding('cw8', '84', pnl: '-0.16')]),
        for (var n = 1; n <= 10; n++)
          snap(n, holdings: [holding('cw8', '95', pnl: '-0.05')]),
        snap(11, sells: [SellFact('cw8', Price(d('95'), Currency.eur))]),
      ]);
      expect(moments.where((m) => m.rule == CompanionRule.panicSell), isEmpty);
    });

    test('the follow-up waits for a price', () {
      final moments = run(log: firstLossDone, [
        snap(
          0,
          holdings: [holding('cw8', '84', pnl: '-0.16')],
          sells: [SellFact('cw8', Price(d('84'), Currency.eur))],
        ),
        snap(100),
        snap(101, prices: {'cw8': '80'}),
      ]);
      expect(fired(moments).last, (CompanionRule.panicSellFollowUp, day(101)));
    });
  });

  group(
    'fx_swing: EUR/USD over 3 % in a month with over 20 % in USD, 30 days',
    () {
      List<DaySnapshot> month(String exposure) => [
        snap(0, usdRate: '0.90'),
        snap(20, usdRate: '0.95'),
        snap(
          31,
          usdRate: '0.93',
          holdings: [
            holding('aapl', '200', weight: exposure, currency: Currency.usd),
          ],
        ),
      ];

      test('fires when both hold', () {
        final moments = run(month('0.25'));
        expect(fired(moments), [(CompanionRule.fxSwing, day(31))]);
        expect(moments.single.params['move'], d('0.033333333333'));
      });

      test('not with little USD exposure', () {
        expect(run(month('0.15')), isEmpty);
      });

      test('not without a month of history', () {
        expect(
          run([snap(0, usdRate: '0.90'), snap(20, usdRate: '0.95')]),
          isEmpty,
        );
      });
    },
  );

  test('every rule links to glossary terms', () {
    for (final rule in CompanionRule.values) {
      expect(rule.glossary, isNotEmpty, reason: rule.id);
    }
  });

  test('the same rule and key fire once per day', () {
    final tracker = CompanionTracker.empty();
    final (_, moments) = tracker.observe(
      snap(
        0,
        holdings: [
          holding('a', '100', weight: '0.5'),
          holding('b', '100', weight: '0.45'),
        ],
      ),
      log: const [],
      thresholds: medium,
    );
    expect(
      moments.where((m) => m.rule == CompanionRule.concentration),
      hasLength(1),
    );
  });
}
