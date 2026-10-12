import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/document/document_controller.dart';
import 'package:len/features/editor/document/go_to_page_dialog.dart';
import 'package:len/features/editor/document/paged_document_view.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;

DocumentController _doc(WidgetTester tester) =>
    tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;

Future<void> _ctrlG(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ctrl+G asks for a page: typing a number and Enter goes there', (tester) async {
    await pumpEditor(tester);
    expect(_doc(tester).currentPage, 0);
    await _ctrlG(tester);
    expect(find.byType(GoToPageDialog), findsOneWidget);
    // One thumbnail per page; the current page is the one named.
    for (final n in [1, 2, 3]) {
      expect(find.byKey(ValueKey('go-to-page-$n')), findsOneWidget);
    }
    expect(find.widgetWithText(TextField, '1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '3');
    await tester.pump();
    // The strip follows the number typed.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('go-to-page-3'))),
      isSemantics(label: 'Page 3', isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('go-to-page-1'))),
      isSemantics(label: 'Page 1', isSelected: false),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(GoToPageDialog), findsNothing);
    expect(_doc(tester).currentPage, 2);
    await closeEditor(tester);
  });

  testWidgets('tapping a thumbnail goes to that page at once', (tester) async {
    await pumpEditor(tester);
    await _ctrlG(tester);
    await tester.tap(find.byKey(const ValueKey('go-to-page-2')));
    await tester.pumpAndSettle();
    expect(find.byType(GoToPageDialog), findsNothing);
    expect(_doc(tester).currentPage, 1);
    await closeEditor(tester);
  });

  testWidgets('a number out of range cannot be submitted', (tester) async {
    await pumpEditor(tester);
    await _ctrlG(tester);
    await tester.enterText(find.byType(TextField), '9');
    await tester.pump();
    expect(find.text('Pages 1–3'), findsOneWidget);
    final go = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Go'));
    expect(go.onPressed, isNull);
    // Enter does nothing either; Cancel leaves the page as it was.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(GoToPageDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_doc(tester).currentPage, 0);
    await closeEditor(tester);
  });

  testWidgets('the page indicator opens it too', (tester) async {
    await pumpEditor(tester);
    // Shown when the notebook opens.
    await tester.tap(find.byTooltip('Go to page'));
    await tester.pumpAndSettle();
    expect(find.byType(GoToPageDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('go-to-page-3')));
    await tester.pumpAndSettle();
    expect(_doc(tester).currentPage, 2);
    await closeEditor(tester);
  });
}
