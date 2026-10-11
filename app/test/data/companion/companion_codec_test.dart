import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/companion/companion_codec.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Price usd(String s) => Price(d(s), Currency.usd);
DateTime day(int m, int dd) => DateTime.utc(2020, m, dd);

void main() {
  test('a tracker comes back exactly as it was', () {
    final tracker = CompanionTracker.restore(
      peaks: {'apple': usd('80.12345')},
      index: d('0.987654321'),
      indexPeak: d('1.0123'),
      previousValue: d('10234.56'),
      cashHighSince: day(3, 2),
      recentPnl: {
        'apple': [d('-0.1'), d('-0.25')],
      },
      usdRates: [(day(2, 18), d('0.9234')), (day(3, 18), d('0.9101'))],
      followUps: {
        'apple|2020-03-23': FollowUp('apple', usd('57.31'), day(6, 23)),
      },
    );
    final back = decodeTracker(encodeTracker(tracker));
    expect(back.peaks, tracker.peaks);
    expect(back.index, tracker.index);
    expect(back.indexPeak, tracker.indexPeak);
    expect(back.previousValue, tracker.previousValue);
    expect(back.cashHighSince, day(3, 2));
    expect(back.recentPnl['apple'], [d('-0.1'), d('-0.25')]);
    expect(back.usdRates, tracker.usdRates);
    final f = back.followUps['apple|2020-03-23']!;
    expect(
      (f.assetId, f.sellPrice, f.due),
      ('apple', usd('57.31'), day(6, 23)),
    );
  });

  test('an empty tracker, with nulls', () {
    final back = decodeTracker(encodeTracker(CompanionTracker.empty()));
    expect(back.previousValue, isNull);
    expect(back.cashHighSince, isNull);
    expect(back.index, Decimal.one);
  });

  test('moment params: strings, exact decimals, prices', () {
    final params = <String, Object>{
      'assetId': 'apple',
      'drop': d('-0.3456789'),
      'sellPrice': usd('57.31'),
    };
    final back = decodeParams(encodeParams(params));
    expect(back, params);
    expect(() => encodeParams({'n': 3}), throwsArgumentError);
  });
}
