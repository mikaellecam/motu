import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/l10n/formats.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const nnbsp = '\u202F'; // thousands separator, before %
const nbsp = '\u00A0'; // before the currency symbol, inside "15 h 30"
const minus = '\u2212';

Decimal d(String s) => Decimal.parse(s);

void main() {
  final fr = Formats('fr');
  final en = Formats('en');

  group('money', () {
    final cases = <(Formats, int, Currency, bool, String)>[
      (fr, 5153460, Currency.eur, false, '51${nnbsp}534,60$nbsp€'),
      (fr, 153460, Currency.eur, true, '+1${nnbsp}534,60$nbsp€'),
      (fr, -153460, Currency.eur, true, '${minus}1${nnbsp}534,60$nbsp€'),
      (fr, -250, Currency.eur, false, '${minus}2,50$nbsp€'),
      (fr, 0, Currency.eur, true, '0,00$nbsp€'),
      (fr, 5, Currency.eur, false, '0,05$nbsp€'),
      (fr, 99999, Currency.eur, false, '999,99$nbsp€'),
      (fr, 100000, Currency.eur, false, '1${nnbsp}000,00$nbsp€'),
      (
        fr,
        1000000000,
        Currency.eur,
        false,
        '10${nnbsp}000${nnbsp}000,00$nbsp€',
      ),
      (fr, 17757, Currency.usd, false, '177,57$nbsp\$'),
      (en, 5153460, Currency.eur, false, '€51,534.60'),
      (en, 153460, Currency.eur, true, '+€1,534.60'),
      (en, -250, Currency.eur, false, '$minus€2.50'),
      (en, 17757, Currency.usd, false, '\$177.57'),
    ];
    for (final (f, minor, currency, signed, expected) in cases) {
      test('$minor ${currency.code} signed=$signed → $expected', () {
        expect(f.money(Money(minor, currency), signed: signed), expected);
      });
    }
  });

  group('percent', () {
    final cases = <(Formats, String, bool, int, String)>[
      (fr, '-0.0288', true, 2, '${minus}2,88$nnbsp%'),
      (fr, '0.0288', true, 2, '+2,88$nnbsp%'),
      (fr, '0.0288', false, 2, '2,88$nnbsp%'),
      (fr, '0', true, 2, '0,00$nnbsp%'),
      (fr, '-0.00001', true, 2, '0,00$nnbsp%'), // rounds to zero: no sign
      (fr, '0.5', false, 0, '50$nnbsp%'),
      (fr, '12.5', true, 1, '+1${nnbsp}250,0$nnbsp%'),
      (en, '-0.0288', true, 2, '${minus}2.88%'),
    ];
    for (final (f, ratio, signed, decimals, expected) in cases) {
      test('$ratio signed=$signed → $expected', () {
        expect(
          f.percent(d(ratio), signed: signed, decimals: decimals),
          expected,
        );
      });
    }
  });

  test('quantities keep their own decimals', () {
    expect(fr.quantity(const Quantity.whole(12)), '12');
    expect(fr.quantity(const Quantity.micros(1500000)), '1,5');
    expect(
      fr.quantity(const Quantity.micros(1250123456)),
      '1${nnbsp}250,123456',
    );
    expect(en.quantity(const Quantity.micros(1500000)), '1.5');
    expect(fr.quantity(const Quantity.zero()), '0');
  });

  test('a plain number, grouped, rounded half-even', () {
    expect(fr.number(d('1234.567'), decimals: 1), '1${nnbsp}234,6');
    expect(en.number(d('1234.567'), decimals: 1), '1,234.6');
    expect(fr.number(d('-75.45'), decimals: 1), '\u221275,4');
  });

  test('plural form of a count: French singular below 2, English at 1', () {
    expect(fr.countForm(d('0.5')), 'one');
    expect(fr.countForm(d('1.5')), 'one');
    expect(fr.countForm(d('2')), 'other');
    expect(en.countForm(d('1')), 'one');
    expect(en.countForm(d('1.5')), 'other');
    expect(en.countForm(d('0.5')), 'other');
  });

  test('French elision before a vowel sound', () {
    expect(fr.elision('Apple'), 'yes');
    expect(fr.elision('Hermès'), 'yes');
    expect(fr.elision('iShares MSCI ACWI ETF'), 'yes');
    expect(fr.elision('ÉDF'), 'yes');
    expect(fr.elision('LVMH'), 'other');
    expect(fr.elision(''), 'other');
  });

  test('price rounds half-even to cents at format time', () {
    expect(fr.price(Price(d('177.565'), Currency.usd)), '177,56$nbsp\$');
    expect(fr.price(Price(d('177.575'), Currency.usd)), '177,58$nbsp\$');
    expect(fr.price(Price(d('0.004'), Currency.eur)), '0,00$nbsp€');
  });

  test('unbooked amounts round half-even at format time', () {
    expect(
      fr.amount(d('1534.605'), Currency.eur, signed: true),
      '+1${nnbsp}534,60$nbsp€',
    );
    expect(
      fr.amount(d('-1534.615'), Currency.eur, signed: true),
      '${minus}1${nnbsp}534,62$nbsp€',
    );
    expect(en.amount(d('-0.004'), Currency.eur, signed: true), '€0.00');
  });

  test('unsupported locales fall back to English', () {
    expect(Formats('de').money(const Money(150, Currency.eur)), '€1.50');
  });

  group('dates', () {
    setUpAll(() async {
      await initializeDateFormatting('fr');
      await initializeDateFormatting('en');
    });

    test('long date', () {
      expect(fr.date(DateTime(2026, 10, 7)), '7 octobre 2026');
      expect(en.date(DateTime(2026, 10, 7)), 'October 7, 2026');
      expect(fr.date(DateTime(2008, 10, 1)), '1er octobre 2008');
      expect(fr.date(DateTime(2026, 1, 11)), '11 janvier 2026');
      expect(en.date(DateTime(2008, 10, 1)), 'October 1, 2008');
    });

    test('time', () {
      expect(fr.time(DateTime(2026, 10, 7, 15, 30)), '15${nbsp}h${nbsp}30');
      expect(fr.time(DateTime(2026, 10, 7, 9, 5)), '9${nbsp}h${nbsp}05');
      expect(
        en.time(DateTime(2026, 10, 7, 15, 30)),
        matches(RegExp(r'^3:30\sPM$')),
      );
    });
  });
}
