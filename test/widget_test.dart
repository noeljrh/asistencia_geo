// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asistencia_geo/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Prefer a stable key-based lookup for the counter if available.
    final Finder counterByKey = find.byKey(const Key('counter'));
    final Finder counterByText0 = find.text('0');

    if (counterByKey.evaluate().isNotEmpty) {
      // Verify that our counter starts at 0 (key-based).
      expect(counterByKey, findsOneWidget);

      // Tap the '+' icon and trigger a frame.
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      // Verify that our counter has incremented to 1 (text check).
      expect(find.text('1'), findsOneWidget);
    } else if (counterByText0.evaluate().isNotEmpty) {
      // Fallback: verify that our counter starts at 0 (text-based).
      expect(counterByText0, findsOneWidget);
      expect(find.text('1'), findsNothing);

      // Tap the '+' icon and trigger a frame.
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      // Verify that our counter has incremented.
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsOneWidget);
    } else {
      // If neither the key nor the default text is present, fail with a clear message.
      fail('No counter widget found. Add a Text widget with key Key("counter") or a Text("0") to the UI.');
    }
  });
}
