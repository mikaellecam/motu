import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';
import 'package:finance_companion/core/l10n/formats.dart';
import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/widgets/cache_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final updated = DateTime.utc(2026, 10, 8, 13, 30);

  Future<void> show(
    WidgetTester tester,
    CacheStatus status, {
    VoidCallback? onRetry,
    VoidCallback? reconnect,
  }) async {
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cacheStatusProvider.overrideWith((ref) => Stream.value(status)),
          if (reconnect != null)
            backendRetryProvider.overrideWithValue(reconnect),
        ],
        child: MainApp.screen(
          Scaffold(body: CacheStatusBanner(onRetry: onRetry)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The device's local time, formatted once the app has loaded the locale.
  String when() {
    final local = updated.toLocal();
    final formats = Formats('fr');
    return '${formats.date(local)}, ${formats.time(local)}';
  }

  testWidgets('offline: the date and time of the cached prices', (
    tester,
  ) async {
    await show(tester, Offline(updated));
    expect(
      find.text('Hors connexion. Tu vois les cours du ${when()}.'),
      findsOneWidget,
    );
  });

  testWidgets('online after a failed refresh', (tester) async {
    await show(tester, Stale(updated));
    expect(
      find.text('Cours du ${when()}\u202f: la mise à jour n\'a pas abouti.'),
      findsOneWidget,
    );
  });

  testWidgets('nothing while fresh, or offline with nothing cached', (
    tester,
  ) async {
    await show(tester, const Fresh());
    expect(find.byType(Card), findsNothing);
    await show(tester, const Offline(null));
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('« Réessayer » tries the backend at once, then the screen '
      'reloads (M13-18)', (tester) async {
    final calls = <String>[];
    await show(
      tester,
      Offline(updated),
      onRetry: () => calls.add('reload'),
      reconnect: () => calls.add('reconnect'),
    );
    await tester.tap(find.text('Réessayer'));
    expect(calls, ['reconnect', 'reload']);
  });
}
