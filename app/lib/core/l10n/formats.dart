import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

import '../money/money.dart';

/// Number, money and date formatting at the presentation edge, for `fr`
/// (default) and `en`.
///
/// French rules (BRIEF §10.3): decimal comma, narrow no-break space as
/// thousands separator, no-break space before the currency symbol and the
/// percent sign. Every locale uses the true minus sign (U+2212), and `signed`
/// adds `+` to positive values so gains and losses never rely on color alone.
class Formats {
  Formats(String languageCode) : _locale = languageCode == 'fr' ? 'fr' : 'en';

  final String _locale;
  bool get _fr => _locale == 'fr';

  static const _nnbsp = '\u202F';
  static const _nbsp = '\u00A0';
  static const _minus = '\u2212';

  /// A booked amount: `51 534,60 €`, `€51,534.60`.
  String money(Money value, {bool signed = false}) =>
      _withCurrency(value.amount, value.currency, signed);

  /// A computed, unbooked amount (a valuation, a P&L), rounded half-even to
  /// cents for display.
  String amount(Decimal value, Currency currency, {bool signed = false}) =>
      _withCurrency(value, currency, signed);

  /// A quote-currency price, rounded half-even to cents: `177,57 $`.
  String price(Price price) =>
      _withCurrency(price.value, price.currency, false);

  /// A share count with its own decimals, up to six: `12`, `1,5`,
  /// `1 250,123456`.
  String quantity(Quantity quantity) {
    final value = quantity.toDecimal();
    return _number(value, value.scale, false);
  }

  /// The plural form a count takes in copy (`one` or `other`), for ICU
  /// `select`: French uses the singular below 2 (`1,5 action`), English only
  /// for exactly 1.
  String countForm(Decimal count) => _fr
      ? (count.abs() < Decimal.fromInt(2) ? 'one' : 'other')
      : (count == Decimal.one ? 'one' : 'other');

  /// `yes` when French elides « de » before [word] (« d'Apple », « d'Hermès »),
  /// `other` otherwise, for ICU `select`. A mute h is assumed: the catalogue
  /// has no aspirated one.
  String elision(String word) {
    if (word.isEmpty) return 'other';
    return 'aàâäeéèêëiîïoôöuùûüyh'.contains(word[0].toLowerCase())
        ? 'yes'
        : 'other';
  }

  /// [ratio] 0.0288 → `2,88 %` (`+2,88 %` when [signed]).
  String percent(Decimal ratio, {bool signed = false, int decimals = 2}) {
    final number = _number(ratio.shift(2), decimals, signed);
    return _fr ? '$number$_nnbsp%' : '$number%';
  }

  /// `7 octobre 2026`, `October 7, 2026`. Needs the intl date data, which
  /// Flutter's localization delegates load (tests call
  /// `initializeDateFormatting`).
  String date(DateTime d) {
    final text = DateFormat.yMMMMd(_locale).format(d);
    // French writes the first of the month as an ordinal: « 1er octobre ».
    return _fr && d.day == 1 ? text.replaceFirst('1', '1er') : text;
  }

  /// `15 h 30`, `3:30 PM`.
  String time(DateTime d) => _fr
      ? '${d.hour}${_nbsp}h$_nbsp${d.minute.toString().padLeft(2, '0')}'
      : DateFormat.jm(_locale).format(d);

  String _withCurrency(Decimal amount, Currency currency, bool signed) {
    final symbol = switch (currency) {
      Currency.eur => '€',
      Currency.usd => r'$',
    };
    final number = _number(amount, 2, signed);
    if (_fr) return '$number$_nbsp$symbol';
    // English puts the symbol after the sign: −€2.50, +€2.50.
    final sign = number.startsWith(_minus) || number.startsWith('+')
        ? number[0]
        : '';
    return '$sign$symbol${number.substring(sign.length)}';
  }

  String _number(Decimal value, int decimals, bool signed) {
    final rounded = roundHalfEven(value, decimals);
    final digits = rounded.abs().toStringAsFixed(decimals);
    final [whole, ...fraction] = digits.split('.');
    final group = _fr ? _nnbsp : ',';
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+$)'),
      (m) => group,
    );
    final body = fraction.isEmpty
        ? grouped
        : '$grouped${_fr ? ',' : '.'}${fraction.first}';
    final sign = rounded < Decimal.zero
        ? _minus
        : signed && rounded > Decimal.zero
        ? '+'
        : '';
    return '$sign$body';
  }
}
