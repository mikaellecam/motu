import 'package:decimal/decimal.dart';

/// Money types (ADR-003). Pure Dart: shared by the domain, data and
/// presentation layers. `double` never appears here.

enum Currency {
  eur('EUR', 2),
  usd('USD', 2);

  const Currency(this.code, this.minorDigits);

  /// ISO 4217 code.
  final String code;

  /// Decimals of the minor unit (cents: 2).
  final int minorDigits;
}

/// Thrown when two amounts in different currencies meet in arithmetic or a
/// comparison. A programming error: convert through `FxService` first.
final class CurrencyMismatchError extends Error {
  CurrencyMismatchError(this.left, this.right);

  final Currency left;
  final Currency right;

  @override
  String toString() =>
      'CurrencyMismatchError: ${left.code} and ${right.code} cannot be mixed';
}

void _sameCurrency(Currency left, Currency right) {
  if (left != right) throw CurrencyMismatchError(left, right);
}

/// An exact amount in integer minor units: cash, ledger entries, fees, booked
/// values.
final class Money implements Comparable<Money> {
  const Money(this.minorUnits, this.currency);

  const Money.zero(this.currency) : minorUnits = 0;

  /// Books a computed [amount] (price × quantity × rate, a fee, interest…) as
  /// money: rounds half-even to the minor unit. The only rounding a value
  /// sees before display.
  factory Money.book(Decimal amount, Currency currency) => Money(
    roundHalfEven(
      amount,
      currency.minorDigits,
    ).shift(currency.minorDigits).toBigInt().toInt(),
    currency,
  );

  final int minorUnits;
  final Currency currency;

  Decimal get amount =>
      Decimal.fromInt(minorUnits).shift(-currency.minorDigits);

  bool get isZero => minorUnits == 0;
  bool get isPositive => minorUnits > 0;
  bool get isNegative => minorUnits < 0;

  Money operator +(Money other) {
    _sameCurrency(currency, other.currency);
    return Money(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _sameCurrency(currency, other.currency);
    return Money(minorUnits - other.minorUnits, currency);
  }

  Money operator -() => Money(-minorUnits, currency);

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  int compareTo(Money other) {
    _sameCurrency(currency, other.currency);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '${currency.code} ${amount.toStringAsFixed(2)}';
}

/// A number of shares, fixed point with 6 decimals, stored as millionths.
final class Quantity implements Comparable<Quantity> {
  const Quantity.micros(this.micros);

  const Quantity.zero() : micros = 0;

  const Quantity.whole(int units) : micros = units * _perUnit;

  /// Keeps 6 decimals and drops the rest, toward zero: a quantity bought for
  /// an amount never costs more than that amount.
  factory Quantity.truncate(Decimal value) =>
      Quantity.micros(value.shift(6).truncate().toBigInt().toInt());

  static const _perUnit = 1000000;

  final int micros;

  Decimal toDecimal() => Decimal.fromInt(micros).shift(-6);

  bool get isZero => micros == 0;
  bool get isPositive => micros > 0;

  /// True when no fraction of a share: required by whole-share wallets.
  bool get isWhole => micros % _perUnit == 0;

  Quantity operator +(Quantity other) => Quantity.micros(micros + other.micros);
  Quantity operator -(Quantity other) => Quantity.micros(micros - other.micros);

  bool operator <(Quantity other) => micros < other.micros;
  bool operator <=(Quantity other) => micros <= other.micros;
  bool operator >(Quantity other) => micros > other.micros;
  bool operator >=(Quantity other) => micros >= other.micros;

  @override
  int compareTo(Quantity other) => micros.compareTo(other.micros);

  @override
  bool operator ==(Object other) => other is Quantity && other.micros == micros;

  @override
  int get hashCode => micros.hashCode;

  @override
  String toString() => 'Quantity(${toDecimal()})';
}

/// A quote or bar price in its quote currency, at full precision.
final class Price implements Comparable<Price> {
  const Price(this.value, this.currency);

  final Decimal value;
  final Currency currency;

  /// Value of [quantity] shares at this price, in [currency], unrounded.
  Decimal times(Quantity quantity) => value * quantity.toDecimal();

  bool operator <(Price other) => compareTo(other) < 0;
  bool operator <=(Price other) => compareTo(other) <= 0;
  bool operator >(Price other) => compareTo(other) > 0;
  bool operator >=(Price other) => compareTo(other) >= 0;

  @override
  int compareTo(Price other) {
    _sameCurrency(currency, other.currency);
    return value.compareTo(other.value);
  }

  @override
  bool operator ==(Object other) =>
      other is Price && other.value == value && other.currency == currency;

  @override
  int get hashCode => Object.hash(value, currency);

  @override
  String toString() => '${currency.code} $value';
}

/// Rounds [value] to [scale] decimals, ties to the even neighbour (banker's
/// rounding): 2.345 → 2.34, 2.355 → 2.36. Used when booking [Money] and when
/// displaying, nowhere else (ADR-003).
Decimal roundHalfEven(Decimal value, int scale) {
  final truncated = value.truncate(scale: scale);
  final remainder = (value - truncated).shift(scale).abs();
  final half = Decimal.parse('0.5');
  if (remainder < half) return truncated;
  final step = Decimal.one.shift(-scale);
  final awayFromZero = value < Decimal.zero
      ? truncated - step
      : truncated + step;
  if (remainder > half) return awayFromZero;
  return truncated.shift(scale).toBigInt().isEven ? truncated : awayFromZero;
}

/// Decimal places kept when a quotient does not terminate (1 / 3). At least
/// the 10 significant digits of BRIEF §7 for any ratio above 1 %, and enough
/// that 40 allocation weights still sum to 1 within 1e-9.
const ratioScale = 12;

/// [numerator] / [denominator]: exact when the quotient terminates, else
/// truncated to [ratioScale] decimals. The caller rules out a zero
/// [denominator] (it decides what an undefined ratio means).
Decimal ratio(Decimal numerator, Decimal denominator) =>
    (numerator / denominator).toDecimal(scaleOnInfinitePrecision: ratioScale);
