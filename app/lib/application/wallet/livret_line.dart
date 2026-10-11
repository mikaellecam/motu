import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../domain/livret/livret_interest.dart';
import '../providers.dart';
import '../trip/trip_wizard.dart' show parseAmount;
import 'wallet_providers.dart';
import 'wallets_list.dart';

part 'livret_line.g.dart';

/// A wallet's Livret A line (BRIEF §4.11) on the wallet's day: what it
/// holds, this year's interest, the rate and ceiling in force, and the cash
/// a deposit can come from.
final class LivretLine {
  const LivretLine({
    required this.day,
    required this.balance,
    required this.accrued,
    required this.rate,
    required this.ceiling,
    required this.availableCash,
  });

  /// The day a transfer is booked on: today, or the trip's day.
  final DateTime day;

  /// Deposits, less withdrawals, plus the interest credited so far.
  final Money balance;

  /// This year's interest so far, credited on 31 December.
  final Decimal accrued;

  final Decimal rate;
  final Money ceiling;

  /// The wallet's cash not held back by pending buys.
  final Money availableCash;
}

@riverpod
Future<LivretLine> livretLine(Ref ref, String walletId) async {
  final market = ref.watch(marketRepositoryProvider);
  final wallets = ref.watch(walletRepositoryProvider);
  final overview = await ref.watch(walletOverviewProvider(walletId).future);
  final asOf = overview.asOf.toUtc();
  final day = DateTime.utc(asOf.year, asOf.month, asOf.day);
  final history = await market.livret(asOf: overview.asOf);
  final wallet = await wallets.load(walletId);
  final account = livretAt(
    wallet.livretMovements,
    rates: history.rates,
    asOf: day,
  );
  return LivretLine(
    day: day,
    balance: account.balance,
    accrued: account.accrued,
    rate: rateAt(day, history.rates),
    ceiling: ceilingAt(day, history.ceilings),
    availableCash: overview.availableCash,
  );
}

/// The transfer sheet's state: what was typed, and what is wrong with it.
final class LivretTransferState {
  const LivretTransferState({
    this.amount = '',
    this.errors = const [],
    this.submitted = false,
    this.failure,
  });

  final String amount;

  /// `validateLivretTransfer` codes, once there is input or after a try.
  final List<ValidationFailure> errors;
  final bool submitted;
  final Failure? failure;
}

/// « Verser » ([deposit]) or « Retirer » on [walletId]'s Livret A: instant,
/// no fees, within the ceiling (BRIEF §4.11).
@riverpod
class LivretTransfer extends _$LivretTransfer {
  @override
  LivretTransferState build(String walletId, bool deposit) =>
      const LivretTransferState();

  List<ValidationFailure> _check(String text, LivretLine line) =>
      validateLivretTransfer(
        Money.book(parseAmount(text) ?? Decimal.zero, Currency.eur),
        deposit: deposit,
        livretBalance: line.balance,
        cash: line.availableCash,
        ceiling: line.ceiling,
      );

  void setAmount(String text, LivretLine line) => state = LivretTransferState(
    amount: text,
    errors: text.trim().isEmpty && !state.submitted
        ? const []
        : _check(text, line),
    submitted: state.submitted,
  );

  /// Books the transfer once valid; the amount moved, or null.
  Future<Money?> submit(LivretLine line) async {
    final errors = _check(state.amount, line);
    state = LivretTransferState(
      amount: state.amount,
      errors: errors,
      submitted: true,
    );
    if (errors.isNotEmpty) return null;
    final amount = Money.book(parseAmount(state.amount)!, Currency.eur);
    try {
      await ref
          .read(walletRepositoryProvider)
          .moveToLivret(walletId, line.day, deposit ? amount : -amount);
    } on Failure catch (failure) {
      state = LivretTransferState(
        amount: state.amount,
        submitted: true,
        failure: failure,
      );
      return null;
    }
    ref
      ..invalidate(walletOverviewProvider(walletId))
      ..invalidate(livretLineProvider(walletId))
      ..invalidate(walletsListProvider);
    return amount;
  }
}
