import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/text_prompt.dart';

void main() {
  Future<List<String?>> pumpPrompt(WidgetTester tester, {required bool allowEmpty}) async {
    final answers = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await showTextPrompt(
                context,
                title: 'Name it',
                initialValue: 'Old',
                allowEmpty: allowEmpty,
              ),
            ),
            child: const Text('Ask'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' ');
    await tester.pump();
    return answers;
  }

  bool okEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'OK')).enabled;

  testWidgets('an empty answer: neither the button nor Enter submits it', (tester) async {
    final answers = await pumpPrompt(tester, allowEmpty: false);
    expect(okEnabled(tester), isFalse);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Name it'), findsOneWidget, reason: 'still open');
    expect(answers, isEmpty);
  });

  testWidgets('allowEmpty: the button and Enter both submit an empty answer', (tester) async {
    final answers = await pumpPrompt(tester, allowEmpty: true);
    expect(okEnabled(tester), isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Name it'), findsNothing);
    expect(answers, ['']);
  });
}
