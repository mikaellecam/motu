import 'package:finance_companion/application/explorer/explorer.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/cache_status.dart';

import 'catalogue.dart';
import 'screenshot.dart';

void main() {
  screenshotRoute('m4-1-shell-map', '/');
  screenshotRoute(
    'm4-1-shell-explore',
    '/explore',
    overrides: [
      cacheStatusProvider.overrideWith((ref) => Stream.value(const Fresh())),
      explorerRowsProvider.overrideWith((ref, _) async => catalogueRows),
    ],
  );
}
