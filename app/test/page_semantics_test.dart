import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/surface_text.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/document_controller.dart';
import 'package:len/features/editor/document/document_layout.dart';
import 'package:len/features/editor/document/page_semantics.dart';
import 'package:len/features/editor/document/paged_document_view.dart';

import 'content_tools_ui_test.dart' show openCanvas;
import 'document_editor_test.dart' show closeEditor, drawAt, inkOf, pumpEditor;
import 'search_ui_test.dart' show textBox;

DocumentController _doc(WidgetTester tester) =>
    tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;

/// The one semantics node named [label].
SemanticsNode _node(String label) => find.semantics.byLabel(label).evaluate().single;

/// Whether some semantics node is named [label].
bool _shown(String label) => find.semantics.byLabel(label).evaluate().isNotEmpty;

void _act(SemanticsNode node, SemanticsAction action, [Object? args]) =>
    node.owner!.performAction(node.id, action, args);

void _custom(SemanticsNode node, CustomSemanticsAction action) =>
    _act(node, SemanticsAction.customAction, CustomSemanticsAction.getIdentifier(action));

bool _offers(SemanticsNode node, CustomSemanticsAction action) => node
    .getSemanticsData()
    .customSemanticsActionIds!
    .contains(CustomSemanticsAction.getIdentifier(action));

/// A recognised line of handwriting on [surface] (what the indexer stores).
void _handwriting(AppServices s, String surface, String text, Offset at) => s.database.execute(
  'INSERT INTO ink_text (surface_id, stroke_key, language, text, x, y, w, h) '
  "VALUES (?, ?, 'en', ?, ?, ?, 200, 30)",
  [surface, 'k-$text', text, at.dx, at.dy],
);

/// Lets the database's commit reach the cache, then the frame it asks for.
Future<void> _committed(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('each page in view is a node with its text; actions turn pages and say so', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (s, nb) = await pumpEditor(tester);
    final doc = _doc(tester);
    final pages = s.pages.pagesOf(nb.id);
    // Page 1 is fitted to the width with page 2 below it on screen.
    expect(_node('Page 1 of 3').value, '');
    expect(_shown('Page 2 of 3'), isTrue);
    expect(_shown('Page 3 of 3'), isFalse, reason: 'only pages in view');

    // Text boxes and handwriting read top to bottom; the PDF's text after.
    s.elements.save([
      textBox('low', pages[0].id, 'Second', const Offset(100, 400)),
      textBox('top', pages[0].id, 'First', const Offset(100, 100)),
    ]);
    _handwriting(s, pages[0].id, 'written between', const Offset(80, 250));
    s.database.execute(
      'INSERT INTO search_docs (kind, ref_id, surface_id, body) VALUES (?, ?, ?, ?)',
      ['pdf', pages[0].id, pages[0].id, 'The PDF page'],
    );
    await _committed(tester);
    expect(_node('Page 1 of 3').value, 'First\nwritten between\nSecond\n\nThe PDF page');

    s.pages.setBookmarked(pages[1].id, true);
    doc.setPages(s.pages.pagesOf(nb.id));
    await tester.pump();
    final first = _node('Page 1 of 3');
    expect(_offers(first, PageSemantics.next), isTrue);
    expect(_offers(first, PageSemantics.previous), isFalse);
    expect(first.getSemanticsData().hasAction(SemanticsAction.scrollUp), isTrue);
    expect(first.getSemanticsData().hasAction(SemanticsAction.scrollDown), isFalse);

    _custom(first, PageSemantics.next);
    await tester.pumpAndSettle();
    expect(doc.currentPage, 1);
    expect(tester.takeAnnouncements().map((a) => a.message), ['Page 2 of 3, bookmarked']);

    // Scrolling forward on a page is the next page, back the previous one.
    _act(_node('Page 2 of 3, bookmarked'), SemanticsAction.scrollUp);
    await tester.pumpAndSettle();
    expect(doc.currentPage, 2);
    expect(tester.takeAnnouncements().map((a) => a.message), ['Page 3 of 3']);
    final last = _node('Page 3 of 3');
    expect(_offers(last, PageSemantics.next), isFalse);
    _act(last, SemanticsAction.scrollDown);
    await tester.pumpAndSettle();
    expect(doc.currentPage, 1);
    expect(tester.takeAnnouncements().map((a) => a.message), ['Page 2 of 3, bookmarked']);

    // The nodes take no pointers: the pen still writes on the page.
    final before = inkOf(s, pages[1]).length;
    await drawAt(tester, const Offset(300, 500));
    expect(inkOf(s, pages[1]), hasLength(before + 1));
    await closeEditor(tester);
    semantics.dispose();
  });

  testWidgets('single-page flow: one node, turned by its actions', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpEditor(tester, size: const Size(1280, 900));
    final doc = _doc(tester)..setFlow(PageFlow.single);
    await tester.pumpAndSettle();
    expect(_shown('Page 1 of 3'), isTrue);
    expect(_shown('Page 2 of 3'), isFalse);
    _custom(_node('Page 1 of 3'), PageSemantics.next);
    await tester.pumpAndSettle();
    expect(doc.currentPage, 1);
    expect(_shown('Page 1 of 3'), isFalse);
    _custom(_node('Page 2 of 3'), PageSemantics.previous);
    await tester.pumpAndSettle();
    expect(doc.currentPage, 0);
    expect(tester.takeAnnouncements().map((a) => a.message), ['Page 2 of 3', 'Page 1 of 3']);
    await closeEditor(tester);
    semantics.dispose();
  });

  testWidgets('an infinite canvas is one node with its text', (tester) async {
    final semantics = tester.ensureSemantics();
    final (s, nb) = await openCanvas(
      tester,
      seed: (s, nb) => s.elements.save([
        textBox('b', nb.id, 'Below', const Offset(100, 600)),
        textBox('far', nb.id, 'Far away', const Offset(5000, 5000)),
        textBox('a', nb.id, 'Above', const Offset(100, 100)),
      ]),
    );
    expect(_node('Canvas').value, 'Above\nBelow\nFar away');
    _handwriting(s, nb.id, 'scribbled', const Offset(0, 300));
    await _committed(tester);
    expect(_node('Canvas').value, 'Above\nscribbled\nBelow\nFar away');
    semantics.dispose();
  });

  testWidgets('without a screen reader nothing is built or read', semanticsEnabled: false, (
    tester,
  ) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'Physics',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: 0,
      firstPage: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
    );
    final doc = DocumentController(pages: services.pages.pagesOf(nb.id), strokes: services.strokes);
    addTearDown(doc.dispose);
    final made = <SurfaceTextCache>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PageSemantics.document(
          doc: doc,
          texts: () {
            made.add(SurfaceTextCache(SurfaceText(services.database)));
            return made.last;
          },
        ),
      ),
    );
    doc.viewport
      ..setSize(const Size(800, 1000))
      ..panBy(const Offset(0, -200));
    await tester.pump();
    expect(made, isEmpty);
    expect(find.byType(ListenableBuilder), findsNothing, reason: 'no listening while off');

    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(made, hasLength(1));
    expect(made.single.reads, 1);
    expect(_shown('Page 1 of 1'), isTrue);
    // Scrolling reads nothing again: the text is cached.
    doc.viewport.panBy(const Offset(0, -50));
    await tester.pump();
    expect(made.single.reads, 1);
    semantics.dispose();
    await tester.pump();
    expect(find.byType(ListenableBuilder), findsNothing);
  });
}
