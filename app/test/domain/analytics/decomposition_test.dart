import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/analytics/decomposition.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Price usd(String v) => Price(d(v), Currency.usd);
Price eur(String v) => Price(d(v), Currency.eur);

Matcher near(String expected) => isA<Decimal>().having(
  (x) => (x - d(expected)).abs(),
  'error',
  lessThan(d('1e-10')),
);

void main() {
  test('EUR asset: no currency component', () {
    final m = decomposeMove(
      assetStart: eur('100'),
      assetEnd: eur('112'),
      benchmarkStart: eur('50'),
      benchmarkEnd: eur('54'),
    )!;
    expect(m.currency, Decimal.zero);
    expect(m.total, d('0.12'));
    expect(m.market, d('0.08'));
    expect(m.specific, d('0.04'));
  });

  test('EUR asset ignores any rate passed', () {
    final m = decomposeMove(
      assetStart: eur('100'),
      assetEnd: eur('100'),
      benchmarkStart: eur('50'),
      benchmarkEnd: eur('50'),
      fxStart: d('0.9'),
      fxEnd: d('1.2'),
    )!;
    expect(m.currency, Decimal.zero);
    expect(m.total, Decimal.zero);
  });

  test('USD asset: −20 % in dollars, dollar +10 %, market −10 %', () {
    final m = decomposeMove(
      assetStart: usd('100'),
      assetEnd: usd('80'),
      benchmarkStart: eur('50'),
      benchmarkEnd: eur('45'),
      fxStart: d('0.90'),
      fxEnd: d('0.99'),
    )!;
    expect(m.local, d('-0.2'));
    expect(m.total, d('-0.12'));
    expect(m.market, d('-0.1'));
    expect(m.currency, d('0.1'));
    // Residual: −0.12 − (−0.10) − 0.10, which carries the −0.02 cross term.
    expect(m.specific, d('-0.12'));
    expect(m.market + m.currency + m.specific, m.total);
  });

  test('USD asset, Apple-like 2022 fixture (reference values from Python)', () {
    final m = decomposeMove(
      assetStart: usd('182.01'),
      assetEnd: usd('129.93'),
      benchmarkStart: eur('435.26'),
      benchmarkEnd: eur('384.39'),
      fxStart: d('0.88066'),
      fxEnd: d('0.93756'),
    )!;
    expect(m.local, near('-0.286138124278885775506840283501'));
    expect(m.currency, near('0.064610632934390116503531442327'));
    expect(m.total, near('-0.240015056660813648495665950763'));
    expect(m.market, near('-0.116872673804163028994164407481'));
    expect(m.specific, near('-0.187753015791040736005032985610'));
  });

  test('undefined from a zero start', () {
    expect(
      decomposeMove(
        assetStart: eur('0'),
        assetEnd: eur('10'),
        benchmarkStart: eur('50'),
        benchmarkEnd: eur('54'),
      ),
      isNull,
    );
    expect(
      decomposeMove(
        assetStart: eur('10'),
        assetEnd: eur('10'),
        benchmarkStart: eur('0'),
        benchmarkEnd: eur('54'),
      ),
      isNull,
    );
    expect(
      decomposeMove(
        assetStart: usd('10'),
        assetEnd: usd('10'),
        benchmarkStart: eur('50'),
        benchmarkEnd: eur('54'),
        fxStart: Decimal.zero,
        fxEnd: d('0.9'),
      ),
      isNull,
    );
  });

  test('a non-EUR asset needs both rates', () {
    expect(
      () => decomposeMove(
        assetStart: usd('10'),
        assetEnd: usd('11'),
        benchmarkStart: eur('50'),
        benchmarkEnd: eur('54'),
      ),
      throwsArgumentError,
    );
  });

  test('start and end must share a currency', () {
    expect(
      () => decomposeMove(
        assetStart: usd('10'),
        assetEnd: eur('11'),
        benchmarkStart: eur('50'),
        benchmarkEnd: eur('54'),
      ),
      throwsA(isA<CurrencyMismatchError>()),
    );
    expect(
      () => decomposeMove(
        assetStart: eur('10'),
        assetEnd: eur('11'),
        benchmarkStart: eur('50'),
        benchmarkEnd: usd('54'),
      ),
      throwsA(isA<CurrencyMismatchError>()),
    );
  });
}
