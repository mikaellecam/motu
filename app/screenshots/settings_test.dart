import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/settings/settings.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/profile_repository.dart';
import 'package:finance_companion/presentation/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';

import 'screenshot.dart';

// Settings at level 2, the device's language, the defaults, a cache of a few
// histories.

void main() {
  screenshot(
    'm9-1-settings',
    const SettingsScreen(),
    size: const Size(390, 1750),
    overrides: [
      settingsViewProvider.overrideWith(
        (ref) async => SettingsView(
          settings: const AppSettings(),
          level: 2,
          fxFee: Decimal.parse('0.0015'),
          startingCash: const Money(5000000, Currency.eur),
          cache: (
            histories: 6,
            closes: 4218,
            lastFetch: DateTime.utc(2026, 10, 12, 7, 45),
            bytes: 2831155,
          ),
        ),
      ),
    ],
  );
}
