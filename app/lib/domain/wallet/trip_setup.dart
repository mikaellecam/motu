import 'package:decimal/decimal.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import 'order.dart';
import 'trip_engine.dart';

/// Trip difficulties (BRIEF §4.5, step 2), with their stored ids.
enum Difficulty {
  decouverte('decouverte'),
  realiste('realiste'),
  serre('serre'),
  surMesure('sur-mesure');

  const Difficulty(this.id);
  final String id;

  static Difficulty? byId(String? id) =>
      values.where((d) => d.id == id).firstOrNull;
}

/// A trip's money settings.
final class TripSettings {
  const TripSettings({
    required this.startingCash,
    required this.monthlyContribution,
    required this.fxFeeRate,
    required this.fixedFee,
    required this.fractionalShares,
  });

  final Money startingCash;
  final Money monthlyContribution;

  /// 0.0015 for 0.15 %.
  final Decimal fxFeeRate;
  final Money fixedFee;
  final bool fractionalShares;

  TradingRules get rules => TradingRules(
    fxFeeRate: fxFeeRate,
    fixedFee: fixedFee,
    fractionalShares: fractionalShares,
  );
}

Money _eur(int euros) => Money(euros * 100, Currency.eur);

/// The settings of a difficulty. « Sur mesure » starts from Réaliste's.
TripSettings presetSettings(Difficulty difficulty) => switch (difficulty) {
  Difficulty.decouverte => TripSettings(
    startingCash: _eur(50000),
    monthlyContribution: _eur(0),
    fxFeeRate: Decimal.zero,
    fixedFee: _eur(0),
    fractionalShares: true,
  ),
  Difficulty.realiste || Difficulty.surMesure => TripSettings(
    startingCash: _eur(10000),
    monthlyContribution: _eur(200),
    fxFeeRate: Decimal.parse('0.0015'),
    fixedFee: _eur(0),
    fractionalShares: true,
  ),
  Difficulty.serre => TripSettings(
    startingCash: _eur(2000),
    monthlyContribution: _eur(0),
    fxFeeRate: Decimal.parse('0.0015'),
    fixedFee: _eur(1),
    fractionalShares: false,
  ),
};

/// The ranges of « Sur mesure »; empty when [s] fits them.
///
/// | code                    | when                                       |
/// |-------------------------|--------------------------------------------|
/// | `starting_cash_range`   | outside 100 € – 1 000 000 €                |
/// | `contribution_range`    | outside 0 – 10 000 € a month               |
/// | `contribution_below_fee`| a contribution smaller than the fixed fee  |
/// | `fx_fee_range`          | outside 0 – 2 %                            |
/// | `fixed_fee_range`       | outside 0 – 20 € per order                 |
List<ValidationFailure> validateSettings(TripSettings s) {
  bool within(Money m, int lo, int hi) =>
      m.minorUnits >= lo * 100 && m.minorUnits <= hi * 100;
  return [
    if (!within(s.startingCash, 100, 1000000))
      const ValidationFailure('starting_cash_range'),
    if (!within(s.monthlyContribution, 0, 10000))
      const ValidationFailure('contribution_range'),
    // A contribution goes into the market through orders: it must at least
    // pay one order's fixed fee.
    if (s.monthlyContribution.isPositive && s.monthlyContribution < s.fixedFee)
      const ValidationFailure('contribution_below_fee'),
    if (s.fxFeeRate < Decimal.zero || s.fxFeeRate > Decimal.parse('0.02'))
      const ValidationFailure('fx_fee_range'),
    if (!within(s.fixedFee, 0, 20)) const ValidationFailure('fixed_fee_range'),
  ];
}

/// The cushion shares of the starting cash offered (decided 2026-10-11).
const cushionShares = [10, 20, 30];

/// The safety cushion moved to the Livret at the start: [percent] of the
/// starting cash, capped at the Livret [ceiling] of the start date.
final class Cushion {
  const Cushion(this.amount, {required this.capped});
  final Money amount;
  final bool capped;
}

Cushion cushion(Money startingCash, int percent, {required Money ceiling}) {
  final wanted = Money.book(
    startingCash.amount * Decimal.fromInt(percent).shift(-2),
    Currency.eur,
  );
  return wanted > ceiling
      ? Cushion(ceiling, capped: true)
      : Cushion(wanted, capped: false);
}

/// The trip name, trimmed, when it has 1 to 30 characters; null otherwise.
String? tripName(String input) {
  final name = input.trim();
  return name.isEmpty || name.runes.length > 30 ? null : name;
}

/// The automatic stops a trip offers, with the spec's thresholds (decided
/// 2026-10-11: switches only).
final defaultDrawdownStop = Decimal.parse('0.15');
final defaultPositionStop = Decimal.parse('0.20');

StopConditions stopsFrom({
  required bool portfolio,
  required bool position,
  required bool orderFilled,
  required bool contribution,
}) => StopConditions(
  drawdown: portfolio ? defaultDrawdownStop : null,
  positionLoss: position ? defaultPositionStop : null,
  orderFilled: orderFilled,
  contribution: contribution,
);
