import 'package:finance_companion/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('on Android, nothing stretches nor glows past a list end', (
    tester,
  ) async {
    // Android 12+ stretches the content by default (M9-21).
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      MainApp.screen(
        Scaffold(
          body: ListView(children: [for (var i = 0; i < 60; i++) Text('$i')]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
