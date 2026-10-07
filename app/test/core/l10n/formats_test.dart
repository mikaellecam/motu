import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/l10n/formats.dart';
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
    final cases = <(Formats, int, String, bool, String)>[
      (fr, 5153460, 'EUR', false, '51${nnbsp}534,60$nbsp€'),
      (fr, 153460, 'EUR', true, '+1${nnbsp}534,60$nbsp€'),
      (fr, -153460, 'EUR', true, '${minus}1${nnbsp}534,60$nbsp€'),
      (fr, -250, 'EUR', false, '${minus}2,50$nbsp€'),
      (fr, 0, 'EUR', true, '0,00$nbsp€'),
      (fr, 5, 'EUR', false, '0,05$nbsp€'),
      (fr, 99999, 'EUR', false, '999,99$nbsp€'),
      (fr, 100000, 'EUR', false, '1${nnbsp}000,00$nbsp€'),
      (fr, 1000000000, 'EUR', false, '10${nnbsp}000${nnbsp}000,00$nbsp€'),
      (fr, 17757, 'USD', false, '177,57$nbsp\$'),
      (fr, 1000, 'DKK', false, '10,00${nbsp}DKK'),
      (en, 5153460, 'EUR', false, '€51,534.60'),
      (en, 153460, 'EUR', true, '+€1,534.60'),
      (en, -250, 'EUR', false, '$minus€2.50'),
      (en, 17757, 'USD', false, '\$177.57'),
    ];
    for (final (f, minor, currency, signed, expected) in cases) {
      test('$minor $currency signed=$signed → $expected', () {
        expect(f.money(minor, currency, signed: signed), expected);
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

  test('price rounds half-even to cents', () {
    expect(fr.price(d('177.565'), 'USD'), '177,56$nbsp\$');
    expect(fr.price(d('177.575'), 'USD'), '177,58$nbsp\$');
    expect(fr.price(d('0.004'), 'EUR'), '0,00$nbsp€');
  });

  test('unsupported locales fall back to English', () {
    expect(Formats('de').money(150, 'EUR'), '€1.50');
  });

  group('roundHalfEven', () {
    final cases = <(String, int, String)>[
      ('2.345', 2, '2.34'),
      ('2.355', 2, '2.36'),
      ('-2.345', 2, '-2.34'),
      ('-2.355', 2, '-2.36'),
      ('2.3451', 2, '2.35'),
      ('2.3449', 2, '2.34'),
      ('0.5', 0, '0'),
      ('1.5', 0, '2'),
      ('2.5', 0, '2'),
      ('-0.5', 0, '0'),
      ('-1.5', 0, '-2'),
      ('7', 2, '7'),
    ];
    for (final (value, scale, expected) in cases) {
      test('$value at $scale → $expected', () {
        expect(roundHalfEven(d(value), scale), d(expected));
      });
    }
  });

  group('dates', () {
    setUpAll(() async {
      await initializeDateFormatting('fr');
      await initializeDateFormatting('en');
    });

    test('long date', () {
      expect(fr.date(DateTime(2026, 10, 7)), '7 octobre 2026');
      expect(en.date(DateTime(2026, 10, 7)), 'October 7, 2026');
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
