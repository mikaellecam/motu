import 'package:finance_companion/main.dart';
import 'package:finance_companion/presentation/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(MainApp(router: buildRouter()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
