import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/document/paged_document_view.dart';

/// Page actions are intentionally not kept on the peeking page indicator.
Future<void> nextPage(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
  await tester.pumpAndSettle();
}

/// "Add page after" from the canvas menu (a right click on the page).
Future<void> addPageAfter(WidgetTester tester) async {
  await tester.tapAt(
    tester.getCenter(find.byType(PagedDocumentView)),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add page after').last);
  await tester.pumpAndSettle();
}
