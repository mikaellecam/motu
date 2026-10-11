import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/wallet/trip_setup.dart';
import 'package:flutter_test/flutter_test.dart';

Money eur(String s) => Money.book(Decimal.parse(s), Currency.eur);
Decimal d(String s) => Decimal.parse(s);

TripSettings settings({
  String cash = '10000',
  String contribution = '0',
  String fx = '0.0015',
  String fee = '0',
  bool fractional = true,
}) => TripSettings(
  startingCash: eur(cash),
  monthlyContribution: eur(contribution),
  fxFeeRate: d(fx),
  fixedFee: eur(fee),
  fractionalShares: fractional,
);

void main() {
  test('the three presets of BRIEF §4.5', () {
    final discovery = presetSettings(Difficulty.decouverte);
    expect(discovery.startingCash, eur('50000'));
    expect(discovery.fxFeeRate, Decimal.zero);
    expect(discovery.fractionalShares, isTrue);

    final realistic = presetSettings(Difficulty.realiste);
    expect(realistic.startingCash, eur('10000'));
    expect(realistic.monthlyContribution, eur('200'));
    expect(realistic.fxFeeRate, d('0.0015'));

    final tight = presetSettings(Difficulty.serre);
    expect(tight.startingCash, eur('2000'));
    expect(tight.fixedFee, eur('1'));
    expect(tight.fractionalShares, isFalse);
    expect(tight.rules.fixedFee, eur('1'));

    for (final difficulty in Difficulty.values) {
      expect(
        validateSettings(presetSettings(difficulty)),
        isEmpty,
        reason: '$difficulty',
      );
    }
  });

  test('ids', () {
    expect(Difficulty.byId('sur-mesure'), Difficulty.surMesure);
    expect(Difficulty.byId('nope'), isNull);
    expect(Difficulty.byId(null), isNull);
  });

  group('« Sur mesure » ranges', () {
    List<String> codes(TripSettings s) => [
      for (final f in validateSettings(s)) f.code,
    ];

    test('the bounds themselves are allowed', () {
      expect(
        codes(settings(cash: '100', contribution: '0', fx: '0', fee: '0')),
        isEmpty,
      );
      expect(
        codes(
          settings(
            cash: '1000000',
            contribution: '10000',
            fx: '0.02',
            fee: '20',
          ),
        ),
        isEmpty,
      );
    });

    test('each range', () {
      expect(codes(settings(cash: '99.99')), ['starting_cash_range']);
      expect(codes(settings(cash: '1000000.01')), ['starting_cash_range']);
      expect(codes(settings(contribution: '-1')), ['contribution_range']);
      expect(codes(settings(contribution: '10000.01')), ['contribution_range']);
      expect(codes(settings(fx: '0.0201')), ['fx_fee_range']);
      expect(codes(settings(fx: '-0.001')), ['fx_fee_range']);
      expect(codes(settings(fee: '20.01')), ['fixed_fee_range']);
    });

    test('a contribution must pay at least one fixed fee', () {
      expect(codes(settings(contribution: '5', fee: '10')), [
        'contribution_below_fee',
      ]);
      expect(codes(settings(contribution: '10', fee: '10')), isEmpty);
      expect(
        codes(settings(contribution: '0', fee: '10')),
        isEmpty,
        reason: 'no contribution',
      );
    });
  });

  test('the cushion: a share of the starting cash, capped at the ceiling', () {
    final ceiling = eur('15300');
    final small = cushion(eur('10000'), 20, ceiling: ceiling);
    expect(small.amount, eur('2000'));
    expect(small.capped, isFalse);
    final big = cushion(eur('80000'), 30, ceiling: ceiling);
    expect(big.amount, eur('15300'));
    expect(big.capped, isTrue);
    expect(cushion(eur('1234.56'), 10, ceiling: ceiling).amount, eur('123.46'));
    expect(cushionShares, [10, 20, 30]);
  });

  test('the name: trimmed, 1 to 30 characters', () {
    expect(tripName('  Crise 2008 '), 'Crise 2008');
    expect(tripName('   '), isNull);
    expect(tripName('a' * 30), 'a' * 30);
    expect(tripName('a' * 31), isNull);
    expect(tripName('Crise financière'), 'Crise financière');
  });

  test('stops: the spec thresholds behind each switch', () {
    final defaults = stopsFrom(
      portfolio: true,
      position: false,
      orderFilled: true,
      contribution: false,
    );
    expect(defaults.drawdown, d('0.15'));
    expect(defaults.positionLoss, isNull);
    expect(defaults.orderFilled, isTrue);
    expect(defaults.contribution, isFalse);
    final all = stopsFrom(
      portfolio: false,
      position: true,
      orderFilled: false,
      contribution: true,
    );
    expect(all.drawdown, isNull);
    expect(all.positionLoss, d('0.20'));
    expect(all.contribution, isTrue);
  });
}
