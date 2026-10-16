import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/outline/outline_entry.dart';
import 'package:len/domain/outline/outline_tree.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/features/documents/export/pdf_bookmarks.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium;

/// The notebook's outline becomes the exported PDF's bookmarks (UX_AUDIT
/// R22-3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppServices services;

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });
  setUp(() => services = AppServices.create(AppDatabase.inMemory()));
  tearDown(() => services.dispose());
  bookmarkOrderTests();

  test(
    'outline entries of exported pages are nested bookmarks; others give way to their children',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      final nb = services.notebooks.create(
        title: 'Notes',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      for (var i = 0; i < 3; i++) {
        services.pages.addPage(nb.id);
      }
      final pages = services.pages.pagesOf(nb.id);
      final outline = services.outline;
      final ch1 = outline.add(notebookId: nb.id, pageId: pages[0].id, title: 'Chapter 1');
      outline.add(notebookId: nb.id, pageId: pages[1].id, title: 'Forces', parentId: ch1.id);
      final ch2 = outline.add(notebookId: nb.id, pageId: pages[2].id, title: 'Chapter 2');
      outline.add(notebookId: nb.id, pageId: pages[3].id, title: 'Energy', parentId: ch2.id);

      final exporter = NotebookExporter(services);
      // Pages 2–4: Chapter 1's page is left out, Forces takes its place.
      final pdf = await exporter.pdf(pages.sublist(1), title: nb.title);
      await exporter.dispose();
      final doc = await PdfDocument.openData(pdf);
      final nodes = await doc.loadOutline();
      await doc.dispose();
      expect([for (final n in nodes) n.title], ['Forces', 'Chapter 2']);
      expect([for (final n in nodes) n.dest?.pageNumber], [1, 2]);
      expect(nodes[1].children.single.title, 'Energy');
      expect(nodes[1].children.single.dest?.pageNumber, 3);
      // Readers open with the bookmarks showing.
      expect(String.fromCharCodes(pdf), contains('/PageMode/UseOutlines'));
    },
  );

  test('a notebook without an outline exports no bookmarks', () async {
    final nb = services.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final exporter = NotebookExporter(services);
    final pdf = await exporter.pdf(services.pages.pagesOf(nb.id));
    await exporter.dispose();
    final raw = String.fromCharCodes(pdf);
    expect(raw, isNot(contains('/Outlines')));
    expect(raw, contains('/PageMode/UseNone'));
  });
}

/// Bookmarks of left-out pages' children stay in page order among the
/// entries they join.
void bookmarkOrderTests() {
  OutlineEntry entry(String id, String page, {String? parent}) => OutlineEntry(
    id: id,
    notebookId: 'nb',
    pageId: page,
    parentId: parent,
    title: id,
    createdAt: 0,
  );
  test('children moving up for a left-out page keep the pages\' order', () {
    final order = {for (var i = 0; i < 5; i++) 'p$i': i};
    final tree = OutlineTree([
      entry('Part 1', 'p0'),
      entry('Late section', 'p4', parent: 'Part 1'),
      entry('Part 2', 'p2'),
    ], order);
    final bookmarks = exportBookmarks(tree, {for (var i = 1; i < 5; i++) 'p$i': i - 1});
    expect([for (final b in bookmarks) b.title], ['Part 2', 'Late section']);
    expect([for (final b in bookmarks) b.page], [1, 3]);
  });
}
