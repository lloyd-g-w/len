import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/link_target.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/documents/export/pdf_export.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/tools/content_layer.dart';
import 'package:len/ink/tool_settings.dart';

import 'document_editor_test.dart' show closeEditor, drawAt, inkOf, pumpEditor;
import 'support/selection_actions.dart';

SurfaceElement _link(String id, NotebookPage page, LinkTarget target, Rect rect) =>
    LinkElements.create(
      id: id,
      surfaceId: page.id,
      rect: rect,
      target: target,
      createdAt: 1,
      z: -1,
    );

void main() {
  group('LinkTarget', () {
    test('URLs: scheme added, only web and mail', () {
      expect(UrlLinkTarget.parse('example.com/a')!.uri.toString(), 'https://example.com/a');
      expect(UrlLinkTarget.parse('me@example.com')!.uri.toString(), 'mailto:me@example.com');
      expect(UrlLinkTarget.parse('http://x.org')!.uri.scheme, 'http');
      expect(UrlLinkTarget.parse('javascript:alert(1)'), isNull);
      expect(UrlLinkTarget.parse('file:///etc/passwd'), isNull);
      expect(UrlLinkTarget.parse('two words'), isNull);
      expect(UrlLinkTarget.parse(''), isNull);
    });

    test('round-trips through JSON; invalid targets are null', () {
      const page = PageLinkTarget(notebookId: 'n', pageId: 'p');
      expect(LinkTarget.fromJson(page.toJson()), page);
      final url = UrlLinkTarget.parse('https://len.dev')!;
      expect(LinkTarget.fromJson(url.toJson()), url);
      expect(LinkTarget.fromJson({'page': 'p'}), isNull);
      expect(LinkTarget.fromJson({'url': 'ftp://x'}), isNull);
      expect(LinkTarget.fromJson('x'), isNull);
    });
  });

  testWidgets('link lassoed ink to a page; follow it by finger tap and from the menu', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    final pages = s.pages.pagesOf(nb.id);
    await drawAt(tester, const Offset(400, 300));
    final ink = inkOf(s, pages.first).last;
    final content = tester.widget<ContentLayer>(find.byType(ContentLayer)).content;
    content.selection.select([content.selection.model.strokeById(ink.id)!], const []);
    await tester.pumpAndSettle();

    await selectionAction(tester, 'Link…');
    await tester.pumpAndSettle();
    // The link menu opens below the selection pill, not over it.
    expect(
      tester.getRect(find.text('Link to page…')).top,
      greaterThan(tester.getRect(find.byTooltip('More')).bottom),
    );
    await tester.tap(find.text('Link to page…'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 (this page)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('link-page-2')));
    await tester.pumpAndSettle();
    expect(find.text('Linked to Page 3'), findsOneWidget);

    final stored = SurfaceCopier(
      s.strokes,
      elements: s.elements,
    ).loadAllElements(pages.first.id).where(LinkElements.isLink).toList();
    expect(stored, hasLength(1));
    expect(
      LinkElements.targetOf(stored.single),
      PageLinkTarget(notebookId: nb.id, pageId: pages[2].id),
    );
    expect(stored.single.rect.contains(ink.points.first.offset), isTrue);

    // A finger tap with stylus-only on follows the link.
    content.selection.clear();
    await tester.pumpAndSettle(const Duration(seconds: 5)); // The message fades.
    await expectLater(
      find.byType(PagedDocumentView),
      matchesGoldenFile('goldens/link_affordance.png'),
    );
    s.preferences.stylusOnly = true;
    tester.widget<ContentLayer>(find.byType(ContentLayer)).tools.stylusOnly = true;
    await tester.pump();
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    final linkScreen = doc.viewport.toScreen(
      doc.layout.frameOf(0)!.topLeft + stored.single.rect.center,
    );
    await tester.tapAt(linkScreen, kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    expect(doc.currentPage, 2);

    // Back on page 1, the long-press menu offers it too.
    doc.scrollToPage(0);
    await tester.pumpAndSettle();
    final at = doc.viewport.toScreen(doc.layout.frameOf(0)!.topLeft + stored.single.rect.center);
    final press = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 700));
    await press.up();
    await tester.pumpAndSettle();
    expect(find.text('Go to Page 3'), findsOneWidget);
    await tester.tap(find.text('Go to Page 3'));
    await tester.pumpAndSettle();
    expect(doc.currentPage, 2);
    await closeEditor(tester);
  });

  testWidgets('web links ask before opening; Remove link deletes it', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    final page = s.pages.pagesOf(nb.id).first;
    await drawAt(tester, const Offset(400, 300));
    final content = tester.widget<ContentLayer>(find.byType(ContentLayer)).content;
    final model = content.selection.model;
    content.selection.select([model.strokeById(inkOf(s, page).last.id)!], const []);
    await tester.pumpAndSettle();
    await selectionAction(tester, 'Link…');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link to web address…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('link-url-field')), 'not a url');
    await tester.pump();
    expect(find.text('Not a web address'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('link-url-field')), 'example.com');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Link'));
    await tester.pumpAndSettle();
    expect(find.text('Linked to example.com'), findsOneWidget);
    expect(content.selection.elements.where(LinkElements.isLink), hasLength(1));

    // Undo removes the link again (one edit).
    content.selection.clear();
    final tools = tester.widget<ContentLayer>(find.byType(ContentLayer)).tools;
    tools.tool = EditorTool.pen;
    await tester.pump();
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)').first);
    await tester.pumpAndSettle();
    List<SurfaceElement> links() => SurfaceCopier(
      s.strokes,
      elements: s.elements,
    ).loadAllElements(page.id).where(LinkElements.isLink).toList();
    expect(links(), isEmpty);
    await tester.tap(find.byTooltip('Redo (Ctrl+Shift+Z)').first);
    await tester.pumpAndSettle();
    expect(links(), hasLength(1));

    // Removing it from the selection menu.
    content.selection.select(
      [model.strokeById(inkOf(s, page).last.id)!],
      [for (final l in links()) model.elementById(l.id)!],
    );
    await tester.pumpAndSettle();
    await selectionAction(tester, 'Link…');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove link'));
    await tester.pumpAndSettle();
    expect(links(), isEmpty);
    await closeEditor(tester);
  });

  test('PDF export writes page links as GoTo and web links as URI annotations', () async {
    const a = NotebookPage(
      id: 'a',
      notebookId: 'n',
      sortKey: 1,
      width: 600,
      height: 800,
      paper: Paper(PaperStyle.blank),
    );
    const b = NotebookPage(
      id: 'b',
      notebookId: 'n',
      sortKey: 2,
      width: 600,
      height: 800,
      paper: Paper(PaperStyle.blank),
    );
    final bytes = await PdfExporter.build([
      ExportPage(
        a,
        const [],
        elements: [
          _link(
            'l1',
            a,
            const PageLinkTarget(notebookId: 'n', pageId: 'b'),
            const Rect.fromLTWH(10, 10, 100, 20),
          ),
          _link(
            'l2',
            a,
            UrlLinkTarget.parse('https://len.dev/x')!,
            const Rect.fromLTWH(10, 50, 100, 20),
          ),
          _link(
            'l3',
            a,
            const PageLinkTarget(notebookId: 'other', pageId: 'zz'),
            const Rect.fromLTWH(10, 90, 100, 20),
          ),
        ],
      ),
      ExportPage(b, const []),
    ]);
    final text = String.fromCharCodes(bytes);
    expect(RegExp(r'/Subtype\s*/Link').allMatches(text).length, 2);
    expect(text, contains('/URI'));
    expect(text, contains('https://len.dev/x'));
    expect(text, contains('/GoTo'));
    expect(text, contains('page-2'));
  });
}
