import 'package:decimal/decimal.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import 'dca.dart';
import 'order.dart';

/// The DCA simulator's rules (BRIEF §4.10): what an amount per purchase
/// may be, and the one insight its result shows.

/// What the simulator runs: [amount] of [assetId] every period from
/// [start] to the latest data.
final class DcaParams {
  const DcaParams({
    required this.assetId,
    required this.amount,
    required this.frequency,
    required this.start,
  });

  factory DcaParams.fromJson(Map<String, Object?> json) => DcaParams(
    assetId: json['asset']! as String,
    amount: Money(json['amountCents']! as int, Currency.eur),
    frequency: DcaFrequency.values.byName(json['frequency']! as String),
    start: _day(json['start']! as String),
  );

  final String assetId;
  final Money amount;
  final DcaFrequency frequency;
  final DateTime start;

  Map<String, Object> toJson() => {
    'asset': assetId,
    'amountCents': amount.minorUnits,
    'frequency': frequency.name,
    'start': start.toIso8601String().substring(0, 10),
  };

  @override
  bool operator ==(Object other) =>
      other is DcaParams &&
      other.assetId == assetId &&
      other.amount == amount &&
      other.frequency == frequency &&
      other.start == start;

  @override
  int get hashCode => Object.hash(assetId, amount, frequency, start);
}

/// What a saved simulation gave when it was saved, for its list.
final class DcaSummary {
  const DcaSummary({
    required this.end,
    required this.invested,
    required this.finalValue,
  });

  factory DcaSummary.fromJson(Map<String, Object?> json) => DcaSummary(
    end: _day(json['end']! as String),
    invested: Money(json['investedCents']! as int, Currency.eur),
    finalValue: Decimal.parse(json['finalValue']! as String),
  );

  final DateTime end;
  final Money invested;
  final Decimal finalValue;

  Map<String, Object> toJson() => {
    'end': end.toIso8601String().substring(0, 10),
    'investedCents': invested.minorUnits,
    'finalValue': finalValue.toString(),
  };
}

/// `2025-10-08` as that UTC day (`DateTime.parse` would read a local time).
DateTime _day(String text) {
  final d = DateTime.parse(text);
  return DateTime.utc(d.year, d.month, d.day);
}

/// The most a purchase may be.
const maxDcaAmount = Money(10000000, Currency.eur);

/// Checks the amount per purchase: above zero, at most [maxDcaAmount], and
/// more than [rules]' fixed fee.
///
/// | code                  | params          |
/// |-----------------------|-----------------|
/// | `amount_not_positive` |                 |
/// | `amount_too_large`    | `max`: Money    |
/// | `amount_below_fees`   | `fees`: Money   |
List<ValidationFailure> validateDcaAmount(
  Money amount, {
  required TradingRules rules,
}) => [
  if (!amount.isPositive)
    const ValidationFailure('amount_not_positive')
  else if (amount > maxDcaAmount)
    ValidationFailure('amount_too_large', {'max': maxDcaAmount})
  else if (amount <= rules.fixedFee)
    ValidationFailure('amount_below_fees', {'fees': rules.fixedFee}),
];

/// What the companion says about a result (decided 2026-10-11).
sealed class DcaInsight {
  const DcaInsight();
}

/// It ended below the money put in: [change] is the result over it.
final class DcaLoss extends DcaInsight {
  const DcaLoss(this.change);
  final Decimal change;
}

/// The buys of [year] cost on average [discount] less than the end price,
/// the cheapest year and at least [cheapYearDiscount].
final class DcaCheapYear extends DcaInsight {
  const DcaCheapYear(this.year, this.discount);
  final int year;
  final Decimal discount;
}

/// DCA ended [difference] € above the lump sum ([dcaAhead]) or below it.
final class DcaVersusLumpSum extends DcaInsight {
  const DcaVersusLumpSum({required this.dcaAhead, required this.difference});
  final bool dcaAhead;
  final Decimal difference;
}

/// How far under the end price a year's buys must be to be « cassés ».
final cheapYearDiscount = Decimal.parse('0.15');

/// The insight on [dca] (with [lumpSum], the same total put in at its first
/// purchase), first match wins: a loss; a calendar year whose buys cost on
/// average at least [cheapYearDiscount] less than [endPrice], the cheapest;
/// else which of DCA and the lump sum ended higher. Null when nothing was
/// bought.
DcaInsight? dcaInsight({
  required InvestmentRun dca,
  required InvestmentRun lumpSum,
  required Price endPrice,
}) {
  if (dca.purchases.isEmpty) return null;
  if (dca.finalValue < dca.invested.amount) return DcaLoss(dca.gainRatio!);

  // The average price paid each year: what its buys cost over the shares.
  final cost = <int, Decimal>{};
  final shares = <int, Decimal>{};
  for (final p in dca.purchases) {
    final year = p.date.year;
    cost[year] = (cost[year] ?? Decimal.zero) + p.price.times(p.quantity);
    shares[year] = (shares[year] ?? Decimal.zero) + p.quantity.toDecimal();
  }
  DcaCheapYear? cheapest;
  for (final year in cost.keys.toList()..sort()) {
    if (shares[year]! <= Decimal.zero || endPrice.value <= Decimal.zero) {
      continue;
    }
    final average = ratio(cost[year]!, shares[year]!);
    final discount = Decimal.one - ratio(average, endPrice.value);
    if (discount >= cheapYearDiscount &&
        (cheapest == null || discount > cheapest.discount)) {
      cheapest = DcaCheapYear(year, discount);
    }
  }
  if (cheapest != null) return cheapest;

  final difference = dca.finalValue - lumpSum.finalValue;
  return DcaVersusLumpSum(
    dcaAhead: difference > Decimal.zero,
    difference: difference.abs(),
  );
}
