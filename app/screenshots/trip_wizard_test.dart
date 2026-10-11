import 'package:finance_companion/application/trip/trip_wizard.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/presentation/features/trip_wizard/trip_wizard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// Step 1 on 11 October 2026, with the catalogue's real listing dates
// (backend/internal/catalogue), so the « N actifs sur 29 » counts are real.

const _listed = [
  '2008-03-28', '1993-01-29', '1999-03-10', '2005-03-10', '2009-07-21', //
  '2007-10-11', '2003-09-29', '2006-01-27', '1991-10-25', '2007-01-09',
  '1995-03-15', '1995-09-18', '2010-01-20', '2007-04-18', '2002-07-01',
  '1996-11-18', '1981-07-08', '2011-01-26', '2003-06-05', '1980-12-12',
  '1986-03-13', '1999-01-22', '1997-05-15', '2004-08-19', '2012-05-18',
  '2010-06-29', '1996-05-09', '1983-12-30', '1970-01-02',
];

final _listingDates = [
  for (final d in _listed) DateTime.parse('${d}T00:00:00Z'),
];

WizardDates _dates() {
  final base = WizardDates(
    presets: const [],
    catalogueSize: _listed.length,
    exchanges: const {Exchange.nyse, Exchange.nasdaq, Exchange.otc},
    listingDates: _listingDates,
  );
  PresetOption option(TripPreset preset, DateTime date) =>
      PresetOption(preset, date, base.availableOn(date));
  return WizardDates(
    presets: [
      for (final p in TripPreset.values)
        if (p.fixedDate case final date?) option(p, date),
      option(TripPreset.oneYear, DateTime.utc(2025, 10, 10)),
      option(TripPreset.fiveYears, DateTime.utc(2021, 10, 11)),
      option(TripPreset.tenYears, DateTime.utc(2016, 10, 11)),
    ],
    catalogueSize: base.catalogueSize,
    exchanges: base.exchanges,
    listingDates: _listingDates,
  );
}

void main() {
  final overrides = [
    wizardDatesProvider.overrideWith((ref) async => _dates()),
    // The Livret A ceiling in 2008 (backend/internal/catalogue/livret.go).
    livretCeilingOnProvider.overrideWith(
      (ref, day) async => const Money(1530000, Currency.eur),
    ),
  ];
  Future<void> toStep2(WidgetTester tester) async {
    await tester.tap(find.text('Crise financière'));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    await tester.tap(find.text('Suivant'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  screenshot(
    'm5-1-trip-wizard-dates',
    const TripWizardScreen(),
    size: const Size(390, 1900),
    overrides: overrides,
    act: (tester) async {
      await tester.tap(find.text('Crise financière'));
      await tester.pump();
    },
  );
  screenshot(
    'm5-1-trip-wizard-floor',
    const TripWizardScreen(),
    overrides: overrides,
    act: (tester) async {
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '24/10/1929');
      await tester.pump();
    },
  );
  screenshot(
    'm5-2-trip-wizard-difficulty',
    const TripWizardScreen(),
    size: const Size(390, 1500),
    overrides: overrides,
    act: (tester) async {
      await toStep2(tester);
      await tester.tap(find.text('Réaliste'));
      await tester.pump();
      await tester.tap(find.text('Commencer avec un matelas de sécurité'));
      await tester.pump();
    },
  );
  screenshot(
    'm5-2-trip-wizard-recap',
    const TripWizardScreen(),
    size: const Size(390, 1400),
    overrides: overrides,
    act: (tester) async {
      await toStep2(tester);
      await tester.tap(find.text('Réaliste'));
      await tester.pump();
      await tester.tap(find.text('Commencer avec un matelas de sécurité'));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pump();
      await tester.tap(find.text('Suivant'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
