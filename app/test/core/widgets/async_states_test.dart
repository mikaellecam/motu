import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/widgets/async_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('ErrorView copy', () {
    final cases = <(Failure, String)>[
      (
        const NetworkFailure(),
        'Impossible de joindre le serveur. Vérifie ta connexion.',
      ),
      (
        const RateLimitedFailure(Duration(seconds: 30)),
        'Trop de demandes d\'un coup. Réessaie dans 30 s.',
      ),
      // Rounded up: never "0 s" while the server still refuses.
      (
        const RateLimitedFailure(Duration(milliseconds: 1200)),
        'Trop de demandes d\'un coup. Réessaie dans 2 s.',
      ),
      (const NotFoundFailure(), 'Cette donnée n\'existe pas, ou plus.'),
      (
        DataUnavailableFailure(DateTime(2008, 9, 15)),
        'Pas de données disponibles au 15 septembre 2008.',
      ),
      (
        const StorageFailure(),
        'Impossible de lire ou d\'enregistrer sur ton appareil.',
      ),
      (
        const ValidationFailure('amount_zero'),
        'Une erreur inattendue s\'est produite.',
      ),
    ];
    for (final (failure, expected) in cases) {
      testWidgets('${failure.runtimeType} → $expected', (tester) async {
        await pumpApp(tester, ErrorView(failure: failure));
        expect(find.text(expected), findsOneWidget);
      });
    }

    testWidgets('English', (tester) async {
      await pumpApp(
        tester,
        const ErrorView(failure: NetworkFailure()),
        locale: 'en',
      );
      expect(
        find.text('Can\'t reach the server. Check your connection.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('ErrorView shows retry only with a callback', (tester) async {
    await pumpApp(tester, const ErrorView(failure: NetworkFailure()));
    expect(find.text('Réessayer'), findsNothing);

    var retries = 0;
    await pumpApp(
      tester,
      ErrorView(failure: const NetworkFailure(), onRetry: () => retries++),
    );
    await tester.tap(find.text('Réessayer'));
    expect(retries, 1);
  });

  group('StaleBanner', () {
    final lastUpdated = DateTime(2026, 10, 7, 17, 35);

    testWidgets('offline copy from the spec, with date and time', (
      tester,
    ) async {
      await pumpApp(
        tester,
        StaleBanner(lastUpdated: lastUpdated, offline: true),
      );
      expect(
        find.text(
          'Hors connexion. Tu vois les cours du 7 octobre 2026, '
          '17 h 35.',
        ),
        findsOneWidget,
      );
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('stale while online', (tester) async {
      var retries = 0;
      await pumpApp(
        tester,
        StaleBanner(
          lastUpdated: lastUpdated,
          offline: false,
          onRetry: () => retries++,
        ),
      );
      expect(
        find.text(
          'Cours du 7 octobre 2026, 17 h 35 : '
          'la mise à jour n\'a pas abouti.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Réessayer'));
      expect(retries, 1);
    });
  });

  testWidgets('AsyncSkeleton draws one bar per line', (tester) async {
    await pumpApp(tester, const AsyncSkeleton(lines: 4));
    expect(
      find.descendant(
        of: find.byType(AsyncSkeleton),
        matching: find.byType(FractionallySizedBox),
      ),
      findsNWidgets(4),
    );
  });

  testWidgets('screen readers hear that it loads', (tester) async {
    await pumpApp(tester, const AsyncSkeleton());
    expect(find.bySemanticsLabel('Chargement…'), findsOneWidget);
  });
}
