import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:webview_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: MyApp(initialLocale: Locale('en')),
      ),
    );

    // Verify that the selection screen is shown by checking for some text
    // The selection screen has 'Choose Scan Type' in English
    expect(find.text('Choose Scan Type'), findsOneWidget);
  });
}
