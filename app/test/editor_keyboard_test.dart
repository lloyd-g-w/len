import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/library/notebook_card.dart';

import 'content_documents_test.dart' show ctrl;
import 'content_tools_ui_test.dart' show key;
import 'document_editor_test.dart' show closeEditor, drawAt, inkOf, pumpEditor;
import 'library_ui_test.dart' show addNotebook, pumpSeeded;

/// Desktop keyboard basics (UX_AUDIT P1-12). In a paged notebook: Ctrl+A,
/// arrow nudges of a selection, arrows turning pages otherwise, zoom keys.
/// In the library: F2 renames, ⌘⌫ trashes the focused notebook.
void main() {
  // The page indicator only peeks while pages move, so ask the controller.
  int currentPage(WidgetTester tester) =>
      tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller.currentPage;

  Future<void> shift(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(k);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  testWidgets('Ctrl+A selects the page; arrows nudge it, a burst is one undo step', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final page = s.pages.pagesOf(nb.id).first;
    final seeded = {for (final st in inkOf(s, page)) st.id};
    List<Stroke> mine() => inkOf(s, page).where((st) => !seeded.contains(st.id)).toList();
    await drawAt(tester, const Offset(300, 400));
    final drawn = mine().single;
    // Ctrl+A selects the seeded ink too; this stroke shows the moves.
    StrokePoint first() =>
        mine().firstWhere((st) => st.points.length == drawn.points.length).points.first;

    await ctrl(tester, LogicalKeyboardKey.keyA);
    expect(find.byTooltip('Delete (Del)'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(first().x - drawn.points.first.x, closeTo(1, 1e-6));
    expect(currentPage(tester), 0, reason: 'a selection keeps the page');

    await shift(tester, LogicalKeyboardKey.arrowDown);
    expect(first().y - drawn.points.first.y, closeTo(10, 1e-6));
    expect(find.byTooltip('Delete (Del)'), findsOneWidget, reason: 'still selected');

    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(mine().single.id, drawn.id);
    await closeEditor(tester);
  });

  testWidgets('without a selection → turns the page; Ctrl+= zooms in', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final page = s.pages.pagesOf(nb.id).first;
    final seeded = {for (final st in inkOf(s, page)) st.id};
    List<Stroke> mine() => inkOf(s, page).where((st) => !seeded.contains(st.id)).toList();
    await drawAt(tester, const Offset(300, 400));
    final before = mine().single.points.first;

    await ctrl(tester, LogicalKeyboardKey.equal);
    await tester.pumpAndSettle();
    await drawAt(tester, const Offset(300, 400));
    final after = mine().firstWhere((st) => st.points.first != before).points.first;
    // The same spot on screen is now another, nearer the middle, on the page.
    expect((after.x - before.x).abs(), greaterThan(5));

    await key(tester, LogicalKeyboardKey.escape);
    await ctrl(tester, LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(currentPage(tester), 1);
    await closeEditor(tester);
  });

  testWidgets('library: F2 renames and ⌘⌫ trashes the focused notebook', (tester) async {
    final services = await pumpSeeded(tester, (s) => addNotebook(s, 'Keys'));
    final inner = find.descendant(of: find.byType(NotebookCard), matching: find.byType(Builder));
    Focus.of(tester.element(inner.first)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.text('Rename notebook'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Locks');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(services.notebooks.list().single.title, 'Locks');

    Focus.of(tester.element(inner.first)).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(services.notebooks.trashed().single.title, 'Locks');
  });
}
