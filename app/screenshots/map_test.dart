import 'package:finance_companion/application/learning/next_step_card.dart';
import 'package:finance_companion/application/learning/ui_level.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/next_step.dart';

import 'screenshot.dart';

// The map (M7-1) and its next step (M7-3). The wallet's buildings stand on
// its own island, in the money screens (M13-1).

void main() {
  screenshotRoute(
    'm7-1-map',
    '/',
    overrides: [
      nextStepViewProvider.overrideWith((ref) async => null),
      currentUiLevelProvider.overrideWith((ref) async => 1),
    ],
  );

  screenshotRoute(
    'm7-3-next-step',
    '/',
    overrides: [
      nextStepViewProvider.overrideWith(
        (ref) async => const NextStepView(
          PlayNode('lb.cash-inflation'),
          title: Localized(
            '10 000 € sous le matelas',
            '€10,000 under the mattress',
          ),
        ),
      ),
      currentUiLevelProvider.overrideWith((ref) async => 2),
    ],
  );
}
