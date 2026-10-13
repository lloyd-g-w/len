import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/messages.dart';

void main() {
  // Found by the desktop e2e suite: Flutter keeps snack bars with an
  // action until dismissed, so "Stylus detected … Undo" and every other
  // Undo message stayed over the page for good.
  testWidgets('a message with an action goes away by itself', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMessage(
                context,
                'Page 2 deleted',
                action: SnackBarAction(label: 'Undo', onPressed: () {}),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 deleted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 deleted'), findsNothing);
  });
}
