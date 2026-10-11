import 'package:decimal/decimal.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';

/// Livret A rules (BRIEF §4.11, §7.13). The rate history and the ceiling are
/// data from the backend, never constants of the app.

/// An annual rate, valid from a date until the next one.
final class LivretRate {
  const LivretRate(this.validFrom, this.annualRate);
  final DateTime validFrom;

  /// 0.017 for 1.7 %.
  final Decimal annualRate;
}

/// The deposit ceiling, valid from a date until the next one (15 300 € before
/// October 2012, 22 950 € since 2013).
final class LivretCeiling {
  const LivretCeiling(this.validFrom, this.amount);
  final DateTime validFrom;
  final Money amount;
}

/// The ceiling valid on [date].
Money ceilingAt(DateTime date, List<LivretCeiling> ceilings) =>
    _validOn(date, ceilings, (c) => c.validFrom, 'ceiling').amount;

/// Cash moved into (positive) or out of (negative) the Livret on a day.
final class LivretMovement {
  const LivretMovement(this.date, this.amount);
  final DateTime date;
  final Money amount;
}

/// Interest is counted by fortnight ("quinzaine"): 1st–15th, 16th–end.
DateTime quinzaineStart(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day <= 15 ? 1 : 16);

/// Last day of the fortnight containing [date].
DateTime quinzaineEnd(DateTime date) => date.day <= 15
    ? DateTime.utc(date.year, date.month, 15)
    // Day 0 of next month is the last day of this one.
    : DateTime.utc(date.year, date.month + 1, 0);

/// A Livret at the end of a day, ready for the next.
///
/// - Deposits earn from the start of the next fortnight.
/// - Withdrawals stop earning from the start of the fortnight they happen in.
/// - Each fortnight earns `eligible × annual rate / 24`, at the rate valid on
///   its first day.
/// - The year's interest is credited and capitalised on 31 December (booked
///   to the cent); until then it is [accrued].
///
/// A fortnight closes when the clock moves past its last day, so a movement
/// on that last day still belongs to it.
final class LivretAccount {
  const LivretAccount._({
    required this.balance,
    required this.accrued,
    required this.credited,
    required this.quinzaine,
    required this.eligible,
  });

  /// An empty account on [date].
  LivretAccount.empty(DateTime date)
    : this._(
        balance: const Money.zero(Currency.eur),
        accrued: Decimal.zero,
        credited: const Money.zero(Currency.eur),
        quinzaine: quinzaineStart(date),
        eligible: const Money.zero(Currency.eur),
      );

  /// Deposits − withdrawals + credited interest.
  final Money balance;

  /// Interest of closed fortnights this year, not credited yet. Shown
  /// separately, counted in the wallet value.
  final Decimal accrued;

  /// All interest credited so far.
  final Money credited;

  /// First day of the fortnight in progress.
  final DateTime quinzaine;

  /// What earns in the fortnight in progress: the balance at its start,
  /// minus withdrawals since.
  final Money eligible;

  /// Records [movement], dated in the fortnight in progress: [advanceTo] its
  /// date first.
  LivretAccount apply(LivretMovement movement) {
    if (quinzaineStart(movement.date) != quinzaine) {
      throw ArgumentError('Advance to ${movement.date} before applying it');
    }
    return LivretAccount._(
      balance: balance + movement.amount,
      accrued: accrued,
      credited: credited,
      quinzaine: quinzaine,
      eligible: movement.amount.isNegative
          ? eligible + movement.amount
          : eligible,
    );
  }

  /// Closes every fortnight that ended before [date].
  LivretAccount advanceTo(DateTime date, List<LivretRate> rates) {
    final today = DateTime.utc(date.year, date.month, date.day);
    var account = this;
    while (quinzaineEnd(account.quinzaine).isBefore(today)) {
      account = account._close(rates);
    }
    return account;
  }

  LivretAccount _close(List<LivretRate> rates) {
    var accrued = this.accrued;
    // Money put in and taken out within one fortnight earns nothing; it never
    // costs interest either.
    if (eligible.isPositive) {
      accrued += ratio(
        eligible.amount * rateAt(quinzaine, rates),
        Decimal.fromInt(24),
      );
    }
    var balance = this.balance;
    var credited = this.credited;
    final end = quinzaineEnd(quinzaine);
    if (end.month == DateTime.december && end.day == 31) {
      final credit = Money.book(accrued, Currency.eur);
      balance += credit;
      credited += credit;
      accrued = Decimal.zero;
    }
    return LivretAccount._(
      balance: balance,
      accrued: accrued,
      credited: credited,
      quinzaine: end.add(const Duration(days: 1)),
      // Deposits of the closed fortnight and credited interest earn from now.
      eligible: balance,
    );
  }
}

/// The annual rate valid on [date].
Decimal rateAt(DateTime date, List<LivretRate> rates) =>
    _validOn(date, rates, (r) => r.validFrom, 'rate').annualRate;

/// The entry of a dated history in force on [date]: the latest that starts on
/// or before it.
T _validOn<T>(
  DateTime date,
  List<T> history,
  DateTime Function(T) validFrom,
  String what,
) {
  T? current;
  for (final entry in history) {
    if (!validFrom(entry).isAfter(date) &&
        (current == null || validFrom(entry).isAfter(validFrom(current)))) {
      current = entry;
    }
  }
  if (current == null) throw ArgumentError('No Livret $what known on $date');
  return current;
}

/// The Livret built from [movements] (in date order) as of [asOf]. Movements
/// after [asOf] are not seen.
LivretAccount livretAt(
  List<LivretMovement> movements, {
  required List<LivretRate> rates,
  required DateTime asOf,
}) {
  if (movements.isEmpty) return LivretAccount.empty(asOf);
  var account = LivretAccount.empty(movements.first.date);
  for (var i = 0; i < movements.length; i++) {
    final movement = movements[i];
    if (i > 0 && movement.date.isBefore(movements[i - 1].date)) {
      throw ArgumentError('Livret movements out of date order');
    }
    if (movement.date.isAfter(asOf)) break;
    account = account.advanceTo(movement.date, rates).apply(movement);
  }
  return account.advanceTo(asOf, rates);
}

/// Checks a transfer between wallet cash and the Livret (instant, no fees).
///
/// | code                         | params           |
/// |------------------------------|------------------|
/// | `amount_not_positive`        |                  |
/// | `insufficient_cash`          | `cash`: Money    |
/// | `livret_ceiling`             | `room`: Money    |
/// | `livret_insufficient_balance`| `balance`: Money |
///
/// Deposits stop at [ceiling]; capitalised interest may push the balance
/// above it, and then no deposit fits.
List<ValidationFailure> validateLivretTransfer(
  Money amount, {
  required bool deposit,
  required Money livretBalance,
  required Money cash,
  required Money ceiling,
}) {
  if (!amount.isPositive) {
    return [const ValidationFailure('amount_not_positive')];
  }
  if (!deposit) {
    return [
      if (amount > livretBalance)
        ValidationFailure('livret_insufficient_balance', {
          'balance': livretBalance,
        }),
    ];
  }
  final room = livretBalance < ceiling
      ? ceiling - livretBalance
      : const Money.zero(Currency.eur);
  return [
    if (amount > cash) ValidationFailure('insufficient_cash', {'cash': cash}),
    if (amount > room) ValidationFailure('livret_ceiling', {'room': room}),
  ];
}
