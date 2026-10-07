import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

void main() {
  screenshotRoute(
    'm6-7-onboarding-question',
    '/onboarding',
    act: (tester) async {
      await tester.tap(find.text('Suivant'));
      await tester.pump();
    },
  );
  screenshotRoute(
    'm6-7-onboarding-result',
    '/onboarding',
    act: (tester) async {
      for (final answer in [
        'Long terme, plus de 8 ans',
        "J'attends",
        "Ce qu'est un ETF",
        'Livret A ou livrets',
        '15 min',
      ]) {
        await tester.tap(find.text(answer));
        await tester.pump();
        await tester.tap(find.text('Suivant'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
  );
}
