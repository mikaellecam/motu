import 'dart:async';
import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/trip/trip_stop.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/wallet/stop_decision.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/presentation/features/trip/stop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// The « Crise financière » trip stopped on 6 October 2008: the portfolio
// went below its line, 15 % under the money put in. Values are illustrative.

class _Idle extends StopActions {
  @override
  FutureOr<void> build(String walletId) {}

  @override
  Future<void> decide(StopDecision decision, {String? reason}) async {}
}

void main() {
  final days = [
    for (
      var t = DateTime.utc(2008, 9, 15);
      !t.isAfter(DateTime.utc(2008, 10, 6));
      t = t.add(const Duration(days: 1))
    )
      if (t.weekday <= 5) t,
  ];
  Decimal d(num v) => Decimal.parse(v.toStringAsFixed(2));
  final values = [
    for (var i = 0; i < days.length; i++)
      d(10000 - 1600 * pow(i / (days.length - 1), 1.6) + 90 * sin(i / 1.3)),
  ];
  final view = StopView(
    walletId: 'lehman',
    date: days.last,
    reasons: [
      DrawdownStop(
        value: Money.book(values.last, Currency.eur),
        threshold: const Money(850000, Currency.eur),
      ),
    ],
    assetNames: const {},
    chart: StopChart(days, values, [
      for (final _ in days) Decimal.fromInt(8500),
    ]),
  );
  screenshot(
    'm5-4-stop',
    const StopScreen(walletId: 'lehman'),
    size: const Size(390, 1350),
    overrides: [
      tripStopProvider.overrideWith((ref, id) async => view),
      stopActionsProvider.overrideWith2((_) => _Idle()),
    ],
    act: (tester) async {
      await tester.tap(find.text('Vendre la moitié'));
      await tester.pump();
    },
  );
}
