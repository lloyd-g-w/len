import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Page actions are intentionally not kept on the peeking page indicator.
Future<void> nextPage(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
  await tester.pumpAndSettle();
}

/// "Add page after" from ⋯ → Page.
Future<void> addPageAfter(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Page'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add page after').last);
  await tester.pumpAndSettle();
}
