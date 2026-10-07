import 'package:finance_companion/core/widgets/async_states.dart';
import 'package:finance_companion/core/widgets/chunky.dart';
import 'package:finance_companion/presentation/debug/gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets('gallery shows every component of both families', (tester) async {
    // Tall enough for the whole list to be built at once.
    tester.view.physicalSize = const Size(1080, 12000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpApp(tester, const GalleryScreen());

    expect(find.byType(ChunkyCard), findsOneWidget);
    expect(find.byType(ChunkyButton), findsNWidgets(3));
    expect(find.byType(FilledButton), findsNWidgets(2));
    expect(find.byType(OutlinedButton), findsWidgets);
    expect(find.byType(TextButton), findsWidgets);
    expect(find.byType(AsyncSkeleton), findsOneWidget);
    expect(find.byType(StaleBanner), findsNWidgets(2));
    expect(find.byType(ErrorView), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });
}
