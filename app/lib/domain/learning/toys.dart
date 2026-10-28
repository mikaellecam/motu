import 'dart:math' as math;

import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import 'content.dart';

/// A `toy` node (BRIEF §4.3): sliders on a formula chart.
final class Toy {
  const Toy({
    required this.formula,
    required this.controls,
    required this.intro,
    required this.explanation,
    this.returnFrom,
  });

  final ToyFormula formula;

  /// The formula's inputs, each a slider.
  final List<ToyControl> controls;
  final Localized intro;
  final Localized explanation;

  /// Where the yearly return starts: a real past average (decided
  /// 2026-10-11). Null leaves the `return` control at its default.
  final PastReturn? returnFrom;
}

/// The formulas a toy can draw, and the controls each one reads.
enum ToyFormula {
  /// Two fee levels on the same money: `amount`, `years`, `return`,
  /// `fee_low`, `fee_high`.
  fees('fees', ['amount', 'years', 'return', 'fee_low', 'fee_high']),

  /// A start and a monthly amount growing: `amount`, `monthly`, `years`,
  /// `return`.
  compound('compound', ['amount', 'monthly', 'years', 'return']),

  /// A safety cushion filling up: `spending` (a month), `months` of it,
  /// `saving` each month (M12-3).
  cushion('cushion', ['spending', 'months', 'saving']),

  /// A loan repaid in equal payments: `amount`, `months`, yearly `rate`.
  loan('loan', ['amount', 'months', 'rate']);

  const ToyFormula(this.json, this.inputs);
  final String json;
  final List<String> inputs;
}

/// A slider: its range, step and starting value.
final class ToyControl {
  const ToyControl({
    required this.id,
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    required this.initial,
  });

  final String id;
  final Localized label;
  final Decimal min;
  final Decimal max;
  final Decimal step;
  final Decimal initial;
}

/// A dataset whose average yearly return seeds the `return` control, and
/// what to call it (« l'ETF Monde »).
final class PastReturn {
  const PastReturn(this.dataset, this.label);
  final String dataset;
  final Localized label;
}

/// The yearly rate that joins the first and last [points]: `(last /
/// first)^(1 / years) − 1`, years counted in days / 365.25. Null with fewer
/// than two points, no time between them, or a first price of zero.
Decimal? averageYearlyReturn(List<(DateTime, Decimal)> points) {
  if (points.length < 2) return null;
  final (start, first) = points.first;
  final (end, last) = points.last;
  final days = end.difference(start).inDays;
  if (days <= 0 || first <= Decimal.zero) return null;
  final growth = ratio(last, first).toDouble();
  // A rate, not money: a fractional power needs floating point.
  final rate = math.pow(growth, 365.25 / days) - 1;
  return Decimal.parse(rate.toStringAsFixed(6));
}

/// Two fee levels over [years]: each year the money grows by
/// [yearlyReturn], then the fee takes its share.
final class FeesResult {
  const FeesResult(this.low, this.high);

  /// One value a year, from the start.
  final List<Decimal> low;
  final List<Decimal> high;

  /// What the higher fee cost by the end.
  Decimal get gap => low.last - high.last;
}

FeesResult feesToy({
  required Decimal amount,
  required int years,
  required Decimal yearlyReturn,
  required Decimal lowFee,
  required Decimal highFee,
}) {
  if (amount < Decimal.zero || years < 0) {
    throw ArgumentError('No negative amount or duration');
  }
  List<Decimal> curve(Decimal fee) {
    final factor = (Decimal.one + yearlyReturn) * (Decimal.one - fee);
    final values = [amount];
    for (var y = 0; y < years; y++) {
      values.add((values.last * factor).truncate(scale: ratioScale));
    }
    return values;
  }

  return FeesResult(curve(lowFee), curve(highFee));
}

/// A start and a monthly amount over [years]: each year what is there grows
/// by [yearlyReturn], then the year's twelve amounts come in.
final class CompoundResult {
  const CompoundResult(this.moneyIn, this.value);

  /// One value a year, from the start.
  final List<Decimal> moneyIn;
  final List<Decimal> value;

  /// What growth added by the end.
  Decimal get growth => value.last - moneyIn.last;
}

CompoundResult compoundToy({
  required Decimal amount,
  required Decimal monthly,
  required int years,
  required Decimal yearlyReturn,
}) {
  if (amount < Decimal.zero || monthly < Decimal.zero || years < 0) {
    throw ArgumentError('No negative amount or duration');
  }
  final yearly = monthly * Decimal.fromInt(12);
  final moneyIn = [amount];
  final value = [amount];
  for (var y = 0; y < years; y++) {
    moneyIn.add(moneyIn.last + yearly);
    value.add(
      (value.last * (Decimal.one + yearlyReturn)).truncate(scale: ratioScale) +
          yearly,
    );
  }
  return CompoundResult(moneyIn, value);
}

/// A safety cushion of [months] of spending, filled from nothing by what is
/// put aside each month.
final class CushionResult {
  const CushionResult(this.target, this.saved, this.fullIn);

  final Decimal target;

  /// What is put aside by the end of each month, from 0, up to the month the
  /// cushion is full; a year of it when it never fills.
  final List<Decimal> saved;

  /// The month the cushion is full; null when nothing is put aside.
  final int? fullIn;
}

CushionResult cushionToy({
  required Decimal spending,
  required int months,
  required Decimal saving,
}) {
  if (spending < Decimal.zero || months < 0 || saving < Decimal.zero) {
    throw ArgumentError('No negative amount or duration');
  }
  final target = spending * Decimal.fromInt(months);
  if (target == Decimal.zero) return CushionResult(target, [target], 0);
  if (saving == Decimal.zero) {
    return CushionResult(target, List.filled(13, Decimal.zero), null);
  }
  final saved = [Decimal.zero];
  while (saved.last < target) {
    final next = saved.last + saving;
    saved.add(next > target ? target : next);
  }
  return CushionResult(target, saved, saved.length - 1);
}

/// A loan repaid in [LoanResult.repaid] equal payments, the last one settling
/// what is left: each month the balance earns the monthly rate (the yearly
/// rate / 12, a « taux nominal »), booked to the cent.
final class LoanResult {
  const LoanResult({
    required this.amount,
    required this.payment,
    required this.repaid,
    required this.paidBackIn,
  });

  final Decimal amount;

  /// Each month's payment, to the cent.
  final Decimal payment;

  /// What has been repaid by the end of each month, from 0.
  final List<Decimal> repaid;

  /// The month the amount borrowed is back: what is paid from then on is the
  /// loan's price.
  final int paidBackIn;

  Decimal get total => repaid.last;
  Decimal get cost => total - amount;
}

LoanResult loanToy({
  required Decimal amount,
  required int months,
  required Decimal yearlyRate,
}) {
  if (amount < Decimal.zero || months < 1 || yearlyRate < Decimal.zero) {
    throw ArgumentError('No negative amount or rate, at least one month');
  }
  final rate = ratio(yearlyRate, Decimal.fromInt(12));
  // P·r / (1 − (1 + r)^−n), or P / n at no interest.
  final growth = (Decimal.one + rate)
      .pow(months)
      .toDecimal(scaleOnInfinitePrecision: ratioScale)
      .truncate(scale: ratioScale);
  final payment = roundHalfEven(
    rate == Decimal.zero
        ? ratio(amount, Decimal.fromInt(months))
        : ratio(amount * rate * growth, growth - Decimal.one),
    2,
  );
  var balance = amount;
  final repaid = [Decimal.zero];
  int? paidBackIn = amount == Decimal.zero ? 0 : null;
  for (var month = 1; month <= months; month++) {
    final interest = roundHalfEven(balance * rate, 2);
    final paid = month == months ? balance + interest : payment;
    balance = balance + interest - paid;
    repaid.add(repaid.last + paid);
    if (paidBackIn == null && repaid.last >= amount) paidBackIn = month;
  }
  return LoanResult(
    amount: amount,
    payment: payment,
    repaid: repaid,
    paidBackIn: paidBackIn ?? months,
  );
}

/// A toy is done once every one of its [controls] was moved (BRIEF §4.3).
bool everyControlTouched(List<String> controls, Set<String> touched) =>
    controls.every(touched.contains);
