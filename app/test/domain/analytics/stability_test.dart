import 'package:decimal/decimal.dart';
import 'package:finance_companion/domain/analytics/risk.dart';
import 'package:finance_companion/domain/analytics/stability.dart';
import 'package:finance_companion/domain/analytics/volatility.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);

/// Weekday closes from [from] to [to].
List<(DateTime, Decimal)> weekdays(
  DateTime from,
  DateTime to,
  Decimal Function(DateTime) close,
) => [
  for (var t = from; !t.isAfter(to); t = t.add(const Duration(days: 1)))
    if (t.weekday <= 5) (t, close(t)),
];

/// 100, 101, 100, 101…: it moves every day.
Decimal zigzag(DateTime t) => t.day.isEven ? d('100') : d('101');

void main() {
  final asOf = DateTime.utc(2026, 10, 23, 15); // a Friday
  final flat = weekdays(day(2019, 1, 1), day(2026, 10, 23), (_) => d('100'));

  PastStability? score(
    List<(DateTime, Decimal)> closes, {
    AssetType type = AssetType.stock,
    DateTime? listed,
    DateTime? at,
  }) => pastStability(
    closes: closes,
    type: type,
    listed: listed ?? day(2000, 1, 3),
    asOf: at ?? asOf,
  );

  group('scales', () {
    test('movements: 40 at 0 %, 1 point less per point of volatility', () {
      expect(movementPoints(Decimal.zero), 40);
      expect(movementPoints(d('0.2482')), 15); // 15,18
      expect(movementPoints(d('0.155')), 24); // 24,5: to the even point
      expect(movementPoints(d('0.145')), 26); // 25,5
      expect(movementPoints(d('0.40')), 0);
      expect(movementPoints(d('0.85')), 0, reason: 'never below 0');
    });

    test('worst fall: 30 without one, 1 point less per 2 % fallen', () {
      expect(fallPoints(Decimal.zero), 30);
      expect(fallPoints(d('-0.34')), 13);
      expect(fallPoints(d('-0.27')), 16); // 16,5
      expect(fallPoints(d('-0.25')), 18); // 17,5
      expect(fallPoints(d('-0.60')), 0);
      expect(fallPoints(d('-0.80')), 0, reason: 'never below 0');
    });

    test('history: 1,5 point a full year, 15 from ten years', () {
      expect(historyPoints(0), 0);
      expect(historyPoints(1), 2); // 1,5
      expect(historyPoints(3), 4); // 4,5
      expect(historyPoints(4), 6);
      expect(historyPoints(10), 15);
      expect(historyPoints(45), 15);
    });
  });

  group('pastStability', () {
    test('a flat price: no movement, no fall', () {
      final s = score(flat)!;
      expect(s.volatility, Decimal.zero);
      expect(s.band, 1);
      expect(s.movementPoints, 40);
      expect(s.worstFall.depth, Decimal.zero);
      expect(s.worstFall.peakDate, isNull);
      expect(s.fallPoints, 30);
    });

    test('a stock gets no basket point, an ETF all of them', () {
      final stock = score(flat)!;
      expect((stock.type, stock.basketPoints), (AssetType.stock, 0));
      expect(stock.total, 85);
      final etf = score(flat, type: AssetType.etf)!;
      expect((etf.type, etf.basketPoints), (AssetType.etf, 15));
      expect(etf.total, 100);
    });

    test('movements: the volatility of the last year of closes', () {
      // Calm until a year ago, then a price moving every day.
      final closes = weekdays(
        day(2019, 1, 1),
        day(2026, 10, 23),
        (t) => t.isAfter(day(2025, 10, 23)) ? zigzag(t) : d('100'),
      );
      final s = score(closes)!;
      final lastYear = annualisedVolatility([
        for (final (t, close) in closes)
          if (t.isAfter(day(2025, 10, 23))) close,
      ])!;
      expect(s.volatility, lastYear);
      expect(s.band, riskBand(lastYear));
      expect(s.movementPoints, movementPoints(lastYear));
      expect(s.movementPoints, lessThan(40));
    });

    test('worst fall: the deepest over five years, with its dates', () {
      final closes = weekdays(day(2019, 1, 1), day(2026, 10, 23), (t) {
        // −50 % in 2021, more than five years back: left out.
        if (t.isAfter(day(2021, 3, 1)) && t.isBefore(day(2021, 6, 1))) {
          return d('50');
        }
        if (t.isBefore(day(2022, 2, 18))) return d('100');
        // A peak at 150, then −34 % until late March 2022.
        if (t.isAfter(day(2022, 2, 18)) && t.isBefore(day(2022, 3, 24))) {
          return d('99');
        }
        return d('150');
      });
      final s = score(closes)!;
      expect(s.worstFall.depth, d('-0.34'));
      expect(s.worstFall.peakDate, day(2022, 2, 18));
      expect(s.worstFall.troughDate, day(2022, 2, 21));
      expect(s.fallPoints, 13);
    });

    test('the five years open on the last close before them', () {
      // 23 October 2021 is a Saturday: the window opens on Friday the 22nd,
      // the peak of a fall that ends on the Monday.
      final closes = weekdays(
        day(2019, 1, 1),
        day(2026, 10, 23),
        (t) => t.isAfter(day(2021, 10, 22)) && t.isBefore(day(2021, 11, 1))
            ? d('90')
            : d('100'),
      );
      final s = score(closes)!;
      expect(s.worstFall.depth, d('-0.1'));
      expect(s.worstFall.peakDate, day(2021, 10, 22));
    });

    test('history: full years from the listing to the day', () {
      expect(score(flat, listed: day(1980, 12, 12))!.historyYears, 45);
      expect(score(flat, listed: day(1980, 12, 12))!.historyPoints, 15);
      expect(score(flat, listed: day(1980, 12, 12))!.since, day(1980, 12, 12));
      // One day before the tenth anniversary.
      final nine = score(flat, listed: day(2016, 10, 24))!;
      expect((nine.historyYears, nine.historyPoints), (9, 14)); // 13,5
      final ten = score(flat, listed: day(2016, 10, 23))!;
      expect((ten.historyYears, ten.historyPoints), (10, 15));
    });

    test('less than five years: what exists, and fewer history points', () {
      final closes = weekdays(
        day(2023, 6, 1),
        day(2026, 10, 23),
        (t) => t.year == 2023 && t.month == 9 ? d('80') : d('100'),
      );
      final s = score(closes, listed: day(2023, 6, 1))!;
      expect(s.worstFall.depth, d('-0.2'));
      expect(s.worstFall.troughDate, day(2023, 9, 1));
      expect(s.fallPoints, 20);
      expect((s.historyYears, s.historyPoints), (3, 4));
      expect(s.total, 40 + 20 + 0 + 4);
    });

    test('the total is the sum of the four parts', () {
      final closes = weekdays(
        day(2019, 1, 1),
        day(2026, 10, 23),
        (t) => t.year == 2024 && t.month == 4 ? d('75') : zigzag(t),
      );
      final s = score(closes, type: AssetType.etf, listed: day(2008, 3, 28))!;
      expect(
        s.total,
        s.movementPoints + s.fallPoints + s.basketPoints + s.historyPoints,
      );
      expect(s.total, inInclusiveRange(0, 100));
    });

    test('as of its day: nothing after it counts (a trip)', () {
      final crash = [
        ...flat,
        ...weekdays(day(2026, 10, 26), day(2026, 12, 31), (_) => d('10')),
      ];
      final s = score(crash)!;
      expect(s.worstFall.depth, Decimal.zero);
      expect(s.movementPoints, 40);
    });

    test('a day without a session: the closes before it', () {
      final sunday = score(flat, at: DateTime.utc(2026, 10, 25, 12))!;
      expect(sunday.total, score(flat)!.total);
    });

    test('less than a year of closes: no score', () {
      final young = weekdays(day(2025, 11, 3), day(2026, 10, 23), zigzag);
      expect(score(young, listed: day(2025, 11, 3)), isNull);
    });

    test('a year back but under 20 closes in it: no score', () {
      final sparse = [
        (day(2025, 1, 2), d('100')),
        for (var m = 1; m <= 10; m++) (day(2026, m, 15), d('100')),
      ];
      expect(score(sparse), isNull);
    });

    test('empty history or a single close: no score', () {
      expect(score(const []), isNull);
      expect(score([(day(2026, 10, 23), d('100'))]), isNull);
    });

    test('a day before every close: no score', () {
      expect(score(flat, at: day(2018, 6, 1)), isNull);
    });

    test('a close of zero or less is refused', () {
      final broken = [
        ...weekdays(day(2019, 1, 1), day(2026, 10, 22), (_) => d('100')),
        (day(2026, 10, 23), Decimal.zero),
      ];
      expect(() => score(broken), throwsArgumentError);
    });
  });
}
