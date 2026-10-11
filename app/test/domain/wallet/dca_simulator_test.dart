import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/wallet/dca.dart';
import 'package:finance_companion/domain/wallet/dca_simulator.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(d(s), Currency.eur);

final rules = TradingRules(
  fxFeeRate: d('0.0015'),
  fixedFee: const Money.zero(Currency.eur),
  fractionalShares: true,
);

/// A buy of [qty] shares at [price] $ on 1 [month]/[year].
Purchase buy(int year, int month, String price, String qty) => Purchase(
  date: DateTime.utc(year, month),
  amount: eur('100'),
  fees: eur('0'),
  quantity: Quantity.truncate(d(qty)),
  price: Price(d(price), Currency.usd),
);

InvestmentRun run(List<Purchase> purchases, String invested, String value) =>
    InvestmentRun(
      purchases: purchases,
      invested: eur(invested),
      quantity: const Quantity.zero(),
      finalValue: d(value),
      series: const [],
    );

void main() {
  group('the amount per purchase', () {
    List<String> codes(String amount, {Money? fixedFee}) => [
      for (final e in validateDcaAmount(
        eur(amount),
        rules: fixedFee == null
            ? rules
            : TradingRules(
                fxFeeRate: Decimal.zero,
                fixedFee: fixedFee,
                fractionalShares: true,
              ),
      ))
        e.code,
    ];

    test('above zero, at most 100 000 €', () {
      expect(codes('100'), isEmpty);
      expect(codes('100000'), isEmpty);
      expect(codes('0'), ['amount_not_positive']);
      expect(codes('-5'), ['amount_not_positive']);
      expect(codes('100000.01'), ['amount_too_large']);
    });

    test('more than a fixed fee takes', () {
      expect(codes('2', fixedFee: eur('2')), ['amount_below_fees']);
      expect(codes('2.01', fixedFee: eur('2')), isEmpty);
    });
  });

  group('the insight, first match wins (decided 2026-10-11)', () {
    final end = Price(d('100'), Currency.usd);

    test('ended below the money put in: a loss, whatever else', () {
      final insight = dcaInsight(
        dca: run([buy(2022, 1, '50', '2')], '1200', '1000'),
        lumpSum: run(const [], '1200', '900'),
        endPrice: end,
      );
      expect(insight, isA<DcaLoss>());
      expect((insight as DcaLoss).change, d('-0.166666666666'));
    });

    test('a year bought at least 15 % under the end price: the cheapest', () {
      final insight = dcaInsight(
        dca: run(
          [
            buy(2021, 6, '90', '1'),
            buy(2022, 3, '70', '1'),
            buy(2022, 9, '60', '2'),
            buy(2023, 3, '84', '1'),
          ],
          '400',
          '500',
        ),
        lumpSum: run(const [], '400', '450'),
        endPrice: end,
      );
      // 2022: (70 + 2 × 60) / 3 shares = 63,33 $, 36,67 % under 100 $.
      expect(insight, isA<DcaCheapYear>());
      final cheap = insight as DcaCheapYear;
      expect(cheap.year, 2022);
      expect(cheap.discount.round(scale: 4), d('0.3667'));
    });

    test('no year that cheap: DCA against the lump sum', () {
      final buys = [buy(2023, 1, '95', '1'), buy(2023, 6, '90', '1')];
      final ahead = dcaInsight(
        dca: run(buys, '200', '215'),
        lumpSum: run(const [], '200', '210'),
        endPrice: end,
      );
      expect(ahead, isA<DcaVersusLumpSum>());
      expect((ahead as DcaVersusLumpSum).dcaAhead, isTrue);
      expect(ahead.difference, d('5'));

      final behind = dcaInsight(
        dca: run(buys, '200', '205'),
        lumpSum: run(const [], '200', '230'),
        endPrice: end,
      ) as DcaVersusLumpSum;
      expect(behind.dcaAhead, isFalse);
      expect(behind.difference, d('25'));
    });

    test('nothing bought: no insight', () {
      expect(
        dcaInsight(
          dca: run(const [], '0', '0'),
          lumpSum: run(const [], '0', '0'),
          endPrice: end,
        ),
        isNull,
      );
    });
  });

  test('inputs and summary survive JSON as UTC days', () {
    final params = DcaParams(
      assetId: 'apple',
      amount: eur('150'),
      frequency: DcaFrequency.weekly,
      start: DateTime.utc(2025, 10, 8),
    );
    expect(DcaParams.fromJson(params.toJson()), params);
    final summary = DcaSummary(
      end: DateTime.utc(2026, 10, 7),
      invested: eur('1200'),
      finalValue: d('1234.5678'),
    );
    final back = DcaSummary.fromJson(summary.toJson());
    expect(
      (back.end, back.invested, back.finalValue),
      (DateTime.utc(2026, 10, 7), eur('1200'), d('1234.5678')),
    );
    expect(back.end.isUtc, isTrue);
  });
}
