import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/trip/trip_summary.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/wallet/trip_summary.dart';
import 'package:finance_companion/presentation/features/trip/summary_screen.dart';
import 'package:flutter/material.dart';

import 'screenshot.dart';

// The « Covid » trip, 18 February to 31 December 2020: 10 000 € then 200 € a
// month. Values are illustrative.

void main() {
  Decimal d(String s) => Decimal.parse(s);
  const none = Localized('', '');
  GlossaryTerm term(String id, String fr) =>
      GlossaryTerm(id: id, title: Localized(fr, fr), short: none, body: none);

  final summary = TripSummary(
    name: 'Covid',
    start: DateTime.utc(2020, 2, 18),
    end: DateTime.utc(2020, 12, 31),
    moneyIn: const Money(1200000, Currency.eur),
    outcomes: [
      OutcomeRow(Outcome.you, value: d('12850.40'), twr: d('0.0712')),
      OutcomeRow(Outcome.world, value: d('13410.15'), twr: d('0.1175')),
      OutcomeRow(Outcome.livret, value: d('12060.52'), twr: d('0.0050')),
      OutcomeRow(
        Outcome.worst,
        value: d('10180'),
        twr: d('-0.1683'),
        date: DateTime.utc(2020, 3, 16),
      ),
    ],
    livretCapped: false,
    journal: [
      ReplayLine(
        JournalEntry(
          date: DateTime.utc(2020, 3, 9),
          decision: 'hold',
          reason: 'Je vise le long terme',
        ),
        moved: d('0.098'),
      ),
      ReplayLine(
        JournalEntry(
          date: DateTime.utc(2020, 3, 16),
          decision: 'sell_half',
          reason: 'Je ne dors plus',
        ),
        sold: const ['Apple', 'LVMH'],
        moved: d('0.61'),
      ),
      ReplayLine(
        JournalEntry(date: DateTime.utc(2020, 6, 1), decision: 'continue'),
      ),
    ],
    terms: [
      term('pire-baisse', 'Pire baisse'),
      term('volatilite', 'Volatilité'),
      term('horizon-de-placement', 'Horizon de placement'),
      term('rebond', 'Rebond'),
    ],
  );

  screenshot(
    'm5-5-trip-summary',
    const TripSummaryScreen(walletId: 'covid'),
    size: const Size(390, 1090),
    overrides: [tripSummaryProvider.overrideWith((ref, id) async => summary)],
  );
}
