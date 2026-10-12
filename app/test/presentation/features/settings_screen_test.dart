import 'package:decimal/decimal.dart';
import 'package:finance_companion/application/settings/settings.dart';
import 'package:finance_companion/core/l10n/app_localizations.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/core/theme/app_theme.dart';
import 'package:finance_companion/data/repositories/profile_repository.dart';
import 'package:finance_companion/presentation/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers.dart';

const nnbsp = ' ';
const nbsp = ' ';

/// Records what the screen asks for in [calls].
class FakeSettings extends SettingsController {
  FakeSettings(this.calls);
  final List<String> calls;

  @override
  void build() {}

  @override
  Future<void> setLanguage(String? code) async => calls.add('language $code');
  @override
  Future<void> setShowAll(bool on) async => calls.add('showAll $on');
  @override
  Future<void> setStartingCash(Money amount) async =>
      calls.add('cash ${amount.minorUnits}');
  @override
  Future<void> setFxFee(Decimal rate) async => calls.add('fee $rate');
  @override
  Future<void> refreshNow() async => calls.add('refresh');
  @override
  Future<void> clearCache() async => calls.add('clear');
  @override
  Future<void> resetLiveWallet() async => calls.add('reset');
}

late List<String> calls;

Future<void> show(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  calls = [];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsControllerProvider.overrideWith(() => FakeSettings(calls)),
        settingsViewProvider.overrideWith(
          (ref) async => SettingsView(
            settings: const AppSettings(),
            level: 2,
            fxFee: Decimal.parse('0.0015'),
            startingCash: const Money(5000000, Currency.eur),
            cache: (
              histories: 3,
              closes: 1250,
              lastFetch: DateTime.utc(2026, 10, 12, 8, 30),
              bytes: 3 * 1024 * 1024 ~/ 2,
            ),
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: appTheme(),
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const SettingsScreen()),
            GoRoute(
              path: '/onboarding',
              builder: (_, _) => const Text('questionnaire'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every section, with where things stand', (tester) async {
    await show(tester);
    for (final title in [
      'Langue',
      'Niveau',
      'Données',
      'Simulation',
      'À propos',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Niveau 2 sur 3'), findsOneWidget);
    expect(
      find.text("3 historiques, 1${nnbsp}250 cours, 1,5 Mo sur l'appareil"),
      findsOneWidget,
    );
    expect(
      find.textContaining('Dernière mise à jour des cours'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, '50${nnbsp}000,00$nbsp€'),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '0,15$nnbsp%'))
          .selected,
      isTrue,
    );
    expect(
      find.textContaining("l'argent de cette app est fictif"),
      findsOneWidget,
    );
  });

  testWidgets('each setting is sent as chosen', (tester) async {
    await show(tester);
    await tester.tap(find.text('English'));
    await tester.tap(find.text('Tout afficher dès maintenant'));
    await tester.tap(find.widgetWithText(ChoiceChip, '1${nnbsp}000,00$nbsp€'));
    await tester.tap(find.widgetWithText(ChoiceChip, '1,00$nnbsp%'));
    await tester.tap(find.text('Actualiser maintenant'));
    await tester.pumpAndSettle();
    expect(
      find.text('Les cours seront mis à jour à la prochaine lecture.'),
      findsOneWidget,
    );
    expect(calls, [
      'language en',
      'showAll true',
      'cash 100000',
      'fee 0.01',
      'refresh',
    ]);
  });

  testWidgets('the reset asks first', (tester) async {
    await show(tester);
    await tester.tap(find.text('Réinitialiser le portefeuille live'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Il repartira aujourd\'hui avec 50${nnbsp}000,00'),
      findsOneWidget,
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await tester.tap(find.text('Réinitialiser le portefeuille live'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    expect(calls, ['reset']);
    expect(find.text('Portefeuille live réinitialisé.'), findsOneWidget);
  });

  testWidgets('the questionnaire opens again', (tester) async {
    await show(tester);
    await tester.tap(find.text('Refaire le questionnaire'));
    await tester.pumpAndSettle();
    expect(find.text('questionnaire'), findsOneWidget);
  });

  testWidgets('accessible, with text at 130 %', (tester) async {
    textAt(tester, 1.3);
    await show(tester);
    await expectAccessible(tester);
  });
}
