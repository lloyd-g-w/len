import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/document/document_controller.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_flow_chains.dart';

import 'search_ui_test.dart' show pumpEditorFor;

/// [n] numbered lines.
String lines(int n) => [for (var i = 0; i < n; i++) 'Line $i'].join('\n');

/// A paged notebook of two blank pages open in the editor.
Future<(AppServices, Notebook)> openNotebook(WidgetTester tester) async {
  final services = AppServices.create(AppDatabase.inMemory());
  addTearDown(services.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  final nb = services.notebooks.create(
    title: 'Notes',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0xFF3B5BDB,
  );
  services.pages.addPage(nb.id);
  await pumpEditorFor(tester, services, nb);
  return (services, nb);
}

PagedDocumentView view(WidgetTester tester) =>
    tester.widget<PagedDocumentView>(find.byType(PagedDocumentView));
DocumentController doc(WidgetTester tester) => view(tester).controller;
TextEditSession session(WidgetTester tester) => view(tester).input.content!.text;
final field = find.byKey(const ValueKey('text-box-field'));
RichTextController controller(WidgetTester tester) =>
    tester.widget<TextField>(field).controller! as RichTextController;

List<SurfaceElement> textOn(AppServices s, String page) => s.elements.allOn(page);

/// Starts a box with the Text tool at page-1 point [at] and types [text].
Future<void> typeBox(WidgetTester tester, Offset at, String text) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
  await tester.pump();
  await tester.tapAt(doc(tester).pageViewport.toScreen(at));
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

/// The global position of the field's caret at display offset [offset].
Offset caretAt(WidgetTester tester, int offset) {
  final editable = tester
      .state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText)))
      .renderEditable;
  return editable.localToGlobal(
    editable.getLocalRectForCaret(TextPosition(offset: offset)).topLeft,
  );
}

/// Where the first page break of the edited text is (model offset).
int breakOf(WidgetTester tester) => session(tester).breaksFor(controller(tester).data).first.at;

void main() {
  testWidgets('typing past the bottom margin goes on at the top of the next page', (tester) async {
    final (services, nb) = await openNotebook(tester);
    final pages = services.pages.pagesOf(nb.id);
    final page = pages.first;
    final margin = FlowPage.marginOf(page.size);
    await typeBox(tester, Offset(80, page.height - margin - 100), lines(10));

    final s = session(tester);
    expect(s.frames, hasLength(2));
    // The field shows the second part where it will be stored: at the top
    // margin of page 2, under the first.
    final c = controller(tester);
    final p1 = doc(tester).pageViewport.toScreen(s.frames[0].topLeft);
    final p2 = doc(tester).pageViewport.toScreen(s.frames[1].topLeft);
    expect(caretAt(tester, 0).dy, closeTo(p1.dy, 1));
    expect(caretAt(tester, _display(c, breakOf(tester))).dy, closeTo(p2.dy, 1));

    // Esc stores two boxes, one per page, as one undo step.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final head = textOn(services, page.id).single;
    final next = textOn(services, pages[1].id).single;
    expect(TextFlowChains.flowOf(next)!.from, head.id);
    expect(
      TextFlow.join([TextData.fromJson(head.data), TextData.fromJson(next.data)]).text,
      lines(10),
    );
    expect(next.rect.top, closeTo(margin, 0.01));
  });

  testWidgets('the caret crosses the page edge; typing there flows the text on', (tester) async {
    final (services, nb) = await openNotebook(tester);
    final pages = services.pages.pagesOf(nb.id);
    final page = pages.first;
    final margin = FlowPage.marginOf(page.size);
    await typeBox(tester, Offset(80, page.height - margin - 100), lines(10));
    final s = session(tester);
    final c = controller(tester);
    final whole = c.data.text;
    // At the end of the first page's last line, → steps over to the next page.
    final endOfFirst = breakOf(tester) - 1;
    c.selection = TextSelection.collapsed(offset: _display(c, endOfFirst));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.modelSelection.start, endOfFirst + 1);
    final p2 = doc(tester).pageViewport.toScreen(s.frames[1].topLeft);
    expect(caretAt(tester, c.selection.extentOffset).dy, closeTo(p2.dy, 1));
    // ← goes back to the end of page one.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(c.modelSelection.start, endOfFirst);

    // Backspace at the start of the next page joins the lines across it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(c.data.text, whole.replaceFirst('\n', '', endOfFirst));

    // Undo while editing takes the edit back, across the pages.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.data.text, whole);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(textOn(services, pages[1].id), hasLength(1));

    // Ctrl+Z after finishing removes the box from both pages.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(textOn(services, page.id), isEmpty);
    expect(textOn(services, pages[1].id), isEmpty);
  });

  testWidgets('text running past the last page adds a page; undo takes it away', (tester) async {
    final (services, nb) = await openNotebook(tester);
    final page = services.pages.pagesOf(nb.id).first;
    await typeBox(tester, Offset(80, page.height / 2), lines(120));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final pages = services.pages.pagesOf(nb.id);
    expect(pages.length, greaterThan(2));
    expect(doc(tester).pages.length, pages.length);
    expect(textOn(services, pages.last.id), hasLength(1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(services.pages.pagesOf(nb.id), hasLength(2));
    expect(textOn(services, page.id), isEmpty);
    // Redo brings the text back with the page.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final again = services.pages.pagesOf(nb.id);
    expect(again.length, pages.length);
    final head = textOn(services, page.id).single;
    final chain = [
      TextData.fromJson(head.data),
      for (final p in again.skip(1))
        ...textOn(services, p.id).map((e) => TextData.fromJson(e.data)),
    ];
    expect(TextFlow.join(chain).text, lines(120));
  });
}

/// The field's display offset of model offset [model].
int _display(RichTextController c, int model) => c.plan.offsets.toDisplay(model);
