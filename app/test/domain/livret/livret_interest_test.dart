import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/livret/livret_interest.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String amount) => Money.book(d(amount), Currency.eur);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);
LivretMovement move(DateTime date, String amount) =>
    LivretMovement(date, eur(amount));

/// 3 %: one fortnight of 1 000 € earns exactly 1,25 €.
final threePercent = [LivretRate(day(2020, 1, 1), d('0.03'))];

LivretAccount at(
  List<LivretMovement> movements,
  DateTime asOf, {
  List<LivretRate>? rates,
}) => livretAt(movements, rates: rates ?? threePercent, asOf: asOf);

void main() {
  group('fortnights (quinzaines)', () {
    test('1st–15th and 16th–end of month', () {
      expect(quinzaineStart(day(2025, 2, 15)), day(2025, 2, 1));
      expect(quinzaineStart(day(2025, 2, 16)), day(2025, 2, 16));
      expect(quinzaineEnd(day(2025, 2, 3)), day(2025, 2, 15));
      expect(quinzaineEnd(day(2025, 2, 20)), day(2025, 2, 28));
      expect(quinzaineEnd(day(2024, 2, 20)), day(2024, 2, 29));
      expect(quinzaineEnd(day(2025, 12, 31)), day(2025, 12, 31));
    });
  });

  group('deposits earn from the next fortnight', () {
    test('a deposit on the 15th earns from the 16th', () {
      final movements = [move(day(2025, 1, 15), '1000')];
      expect(at(movements, day(2025, 1, 31)).accrued, Decimal.zero);
      expect(at(movements, day(2025, 2, 1)).accrued, d('1.25'));
    });

    test('a deposit on the 16th earns from the 1st of next month', () {
      final movements = [move(day(2025, 1, 16), '1000')];
      expect(at(movements, day(2025, 2, 1)).accrued, Decimal.zero);
      expect(at(movements, day(2025, 2, 16)).accrued, d('1.25'));
    });

    test('a deposit on the 1st waits for the 16th', () {
      final movements = [move(day(2025, 1, 1), '1000')];
      expect(at(movements, day(2025, 1, 16)).accrued, Decimal.zero);
      expect(at(movements, day(2025, 2, 1)).accrued, d('1.25'));
    });

    test('the balance moves at once; only interest waits', () {
      expect(
        at([move(day(2025, 1, 16), '1000')], day(2025, 1, 16)).balance,
        eur('1000'),
      );
    });
  });

  group('withdrawals stop earning from the start of their fortnight', () {
    final deposit = move(day(2025, 1, 10), '1000');

    test('a withdrawal mid-fortnight takes that whole fortnight', () {
      // Jan 16–31: 1 000 → 1,25. Feb 1–15: 1 000 → 1,25. Feb 16–28: 600 → 0,75.
      final a = at([deposit, move(day(2025, 2, 20), '-400')], day(2025, 3, 1));
      expect(a.accrued, d('3.25'));
      expect(a.balance, eur('600'));
    });

    test('on the 16th or the 28th: the same fortnight', () {
      for (final date in [day(2025, 2, 16), day(2025, 2, 28)]) {
        expect(
          at([deposit, move(date, '-400')], day(2025, 3, 1)).accrued,
          d('3.25'),
        );
      }
    });

    test('on the 15th: the first fortnight of the month', () {
      // Feb 1–15 and Feb 16–28 both at 600 → 0,75 each.
      expect(
        at([deposit, move(day(2025, 2, 15), '-400')], day(2025, 3, 1)).accrued,
        d('2.75'),
      );
    });

    test(
      'money in and out within one fortnight earns nothing, never negative',
      () {
        final a = at([
          move(day(2025, 3, 20), '500'),
          move(day(2025, 3, 25), '-500'),
        ], day(2025, 5, 1));
        expect(a.accrued, Decimal.zero);
        expect(a.balance, eur('0'));
      },
    );
  });

  test('a rate change applies from the fortnight that starts on its date', () {
    final rates = [
      LivretRate(day(2020, 1, 1), d('0.03')),
      LivretRate(day(2025, 2, 1), d('0.024')),
    ];
    // Jan 16–31 at 3 % → 1,25; Feb 1–15 and Feb 16–28 at 2,4 % → 1,00 each.
    expect(
      at(
        [move(day(2025, 1, 10), '1000')],
        day(2025, 3, 1),
        rates: rates,
      ).accrued,
      d('3.25'),
    );
  });

  group('31 December', () {
    final deposit = move(day(2025, 1, 10), '2400');

    test('the year\'s interest is credited and capitalised', () {
      // 23 fortnights (Jan 16 → Dec 31) × 3,00 €.
      final dec31 = at([deposit], day(2025, 12, 31));
      expect(dec31.accrued, d('66'));
      expect(dec31.balance, eur('2400'));

      final jan1 = at([deposit], day(2026, 1, 1));
      expect(jan1.accrued, Decimal.zero);
      expect(jan1.balance, eur('2469'));
      expect(jan1.credited, eur('69'));
    });

    test('credited interest earns from 1 January', () {
      // 2 469 × 3 % / 24.
      expect(at([deposit], day(2026, 1, 16)).accrued, d('3.08625'));
    });

    test('the credit is booked half-even to the cent', () {
      // 23 × 1 × 3 % / 24 = 0,02875 € → 0,03 €.
      expect(
        at([move(day(2025, 1, 10), '1')], day(2026, 1, 1)).balance,
        eur('1.03'),
      );
    });
  });

  group('edge cases', () {
    test('no movement: an empty account', () {
      final a = at(const [], day(2025, 6, 1));
      expect(a.balance, eur('0'));
      expect(a.accrued, Decimal.zero);
    });

    test('movements after asOf are not seen', () {
      final a = at([
        move(day(2025, 1, 10), '1000'),
        move(day(2025, 6, 1), '5000'),
      ], day(2025, 2, 1));
      expect(a.balance, eur('1000'));
    });

    test('a fortnight without a known rate is an error', () {
      expect(
        () => at([move(day(2019, 1, 10), '1000')], day(2019, 3, 1)),
        throwsArgumentError,
      );
    });

    test('movements must be in date order', () {
      expect(
        () => at([
          move(day(2025, 2, 1), '1'),
          move(day(2025, 1, 1), '1'),
        ], day(2025, 3, 1)),
        throwsArgumentError,
      );
    });

    test('a movement must be applied in its own fortnight', () {
      final account = LivretAccount.empty(day(2025, 1, 1));
      expect(
        () => account.apply(move(day(2025, 1, 20), '100')),
        throwsArgumentError,
      );
    });

    test('day-by-day advancing matches computing from scratch', () {
      final movements = [
        move(day(2025, 1, 10), '1000'),
        move(day(2025, 2, 15), '-300'),
        move(day(2025, 7, 3), '500'),
        move(day(2025, 12, 31), '-100'),
      ];
      var account = LivretAccount.empty(day(2025, 1, 1));
      var next = 0;
      for (
        var date = day(2025, 1, 1);
        !date.isAfter(day(2026, 2, 1));
        date = date.add(const Duration(days: 1))
      ) {
        account = account.advanceTo(date, threePercent);
        while (next < movements.length && movements[next].date == date) {
          account = account.apply(movements[next++]);
        }
      }
      final scratch = at(movements, day(2026, 2, 1));
      expect(account.balance, scratch.balance);
      expect(account.accrued, scratch.accrued);
    });
  });

  group('validateLivretTransfer', () {
    final ceiling = eur('22950');
    List<String> codes(
      String amount, {
      required bool deposit,
      String balance = '0',
      String cash = '100000',
    }) => [
      for (final f in validateLivretTransfer(
        eur(amount),
        deposit: deposit,
        livretBalance: eur(balance),
        cash: eur(cash),
        ceiling: ceiling,
      ))
        f.code,
    ];

    test('valid transfers', () {
      expect(codes('1000', deposit: true), isEmpty);
      expect(codes('22950', deposit: true), isEmpty);
      expect(codes('500', deposit: false, balance: '500'), isEmpty);
    });

    test('non-positive amounts', () {
      expect(codes('0', deposit: true), ['amount_not_positive']);
      expect(codes('-5', deposit: false), ['amount_not_positive']);
    });

    test('deposits stop at the ceiling, with the room left', () {
      final failures = validateLivretTransfer(
        eur('1000'),
        deposit: true,
        livretBalance: eur('22000'),
        cash: eur('5000'),
        ceiling: ceiling,
      );
      expect(failures.single.code, 'livret_ceiling');
      expect(failures.single.params, {'room': eur('950')});
    });

    test('capitalised interest may pass the ceiling; then no room is left', () {
      final failures = validateLivretTransfer(
        eur('1'),
        deposit: true,
        livretBalance: eur('23010.50'),
        cash: eur('5000'),
        ceiling: ceiling,
      );
      expect(failures.single.params, {'room': eur('0')});
    });

    test('a deposit needs the cash; a withdrawal needs the balance', () {
      expect(codes('600', deposit: true, cash: '500'), ['insufficient_cash']);
      final failures = validateLivretTransfer(
        eur('600'),
        deposit: false,
        livretBalance: eur('500'),
        cash: eur('0'),
        ceiling: ceiling,
      );
      expect(failures.single.code, 'livret_insufficient_balance');
      expect(failures.single.params, {'balance': eur('500')});
    });
  });
}
