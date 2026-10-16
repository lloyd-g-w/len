import 'dart:io';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/documents/overview/page_commands.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/documents/pdf/pdf_renderer.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:len/ui/app_theme.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'data_test.dart' show stroke;
import 'pdf_missing_test.dart' show otherPdf, shaOf;
import 'pdf_test.dart' show pdfium;
import 'support/real_async.dart';

/// Replace PDF…: the lecturer's new version of the slides under the same
/// notes (UX_AUDIT R18-1).
void main() {
  late Directory dir;
  late AppServices services;

  setUpAll(() async {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
    if (pdfium != null) await PdfRenderer.ensureInitialized();
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_pdf_replace_test_');
    services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
  });
  tearDown(() {
    services.dispose();
    dir.deleteSync(recursive: true);
  });

  test('Replace PDF… is offered on PDF pages only', () {
    expect(PageCommand.menuFor(pdf: true), contains(PageCommand.replacePdf));
    expect(PageCommand.menuFor(pdf: false), PageCommand.menu);
    expect(PageCommand.menuFor(pdf: true).last, PageCommand.delete);
  });

  testWidgets(
    'a new version shows under the notes, its new pages added; one undo',
    skip: pdfium == null,
    (tester) async {
      tester.view
        ..physicalSize = const ui.Size(900, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final old = await otherPdf(pages: 2);
      final updated = await otherPdf(pages: 3);
      final newFile = File('${dir.path}/Lecture 5 v2.pdf')..writeAsBytesSync(updated);
      final nb = (await tester.runAsync(() async {
        final file = File('${dir.path}/Lecture 5.pdf')..writeAsBytesSync(old);
        final importer = PdfImporter(services);
        final notebook = await importer.createNotebook(
          await importer.store(XFile(file.path)),
          title: 'Lecture 5',
          cover: 0,
        );
        await importer.dispose();
        return notebook;
      }))!;
      final first = services.pages.pagesOf(nb.id).first;
      services.strokes.save([stroke('note', const Offset(40, 40), surface: first.id)]);
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: EditorScreen(notebook: nb),
          ),
        ),
      );
      await pumpUntilPdfRendered(tester);
      final session = tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;
      var finished = false;
      final done = session.commands!
          .replacePdf(tester.element(find.byType(EditorCanvas)), first, file: XFile(newFile.path))
          .whenComplete(() => finished = true);
      await pumpUntil(tester, () => find.text('Replace the PDF?').evaluate().isNotEmpty);
      expect(find.textContaining('on 2 pages, page for page'), findsOneWidget);
      expect(find.textContaining('Its 1 new page is added at the end'), findsOneWidget);
      expect(find.textContaining('change shape'), findsNothing); // Both A5.
      await tester.tap(find.text('Replace'));
      await pumpUntil(tester, () => finished);
      await done;
      await tester.pump();

      List<(String?, int?)> backgrounds() => [
        for (final p in services.pages.pagesOf(nb.id)) (p.pdf?.blob, p.pdf?.pageIndex),
      ];
      final sha = shaOf(updated);
      expect(backgrounds(), [(sha, 0), (sha, 1), (sha, 2)]);
      expect(services.pages.pagesOf(nb.id).first.id, first.id); // The notes stay.
      expect(find.text('PDF replaced'), findsOneWidget);

      // One step for the notebook's undo (the button, Ctrl+Z).
      await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
      await tester.pump();
      expect(backgrounds(), [(shaOf(old), 0), (shaOf(old), 1)]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pages take a new version\'s shape, their width and notes kept; one undo',
    skip: pdfium == null,
    (tester) async {
      tester.view
        ..physicalSize = const ui.Size(900, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final old = await otherPdf(pages: 2);
      const wide = pw.PdfPageFormat(800, 450); // 16:9 slides.
      final updated = await otherPdf(pages: 2, format: wide);
      final newFile = File('${dir.path}/Lecture 5 v2.pdf')..writeAsBytesSync(updated);
      final nb = (await tester.runAsync(() async {
        final file = File('${dir.path}/Lecture 5.pdf')..writeAsBytesSync(old);
        final importer = PdfImporter(services);
        final notebook = await importer.createNotebook(
          await importer.store(XFile(file.path)),
          title: 'Lecture 5',
          cover: 0,
        );
        await importer.dispose();
        return notebook;
      }))!;
      final before = services.pages.pagesOf(nb.id);
      final first = before.first;
      final note = stroke('note', const Offset(40, 40), surface: first.id);
      services.strokes.save([note]);
      final ink = services.strokes.contentBounds(first.id);
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: EditorScreen(notebook: nb),
          ),
        ),
      );
      await pumpUntilPdfRendered(tester);
      final session = tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;
      var finished = false;
      final done = session.commands!
          .replacePdf(tester.element(find.byType(EditorCanvas)), first, file: XFile(newFile.path))
          .whenComplete(() => finished = true);
      await pumpUntil(tester, () => find.text('Replace the PDF?').evaluate().isNotEmpty);
      expect(find.textContaining('Pages change shape to match'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await pumpUntil(tester, () => finished);
      await done;
      await tester.pump();

      List<ui.Size> sizes() => [for (final p in services.pages.pagesOf(nb.id)) p.size];
      final width = first.width;
      expect(sizes(), [ui.Size(width, width * 450 / 800), ui.Size(width, width * 450 / 800)]);
      // The ink stays where it was, unscaled.
      expect(services.strokes.contentBounds(first.id), ink);
      // The document shows the new shape.
      expect(session.doc!.pages.first.size, ui.Size(width, width * 450 / 800));

      await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
      await tester.pump();
      expect(sizes(), [for (final p in before) p.size]);
      expect(session.doc!.pages.first.size, first.size);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the same file again changes nothing', skip: pdfium == null, (tester) async {
    tester.view
      ..physicalSize = const ui.Size(900, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final old = await otherPdf(pages: 2);
    final file = File('${dir.path}/Lecture 5.pdf')..writeAsBytesSync(old);
    final nb = (await tester.runAsync(() async {
      final importer = PdfImporter(services);
      final notebook = await importer.createNotebook(
        await importer.store(XFile(file.path)),
        title: 'Lecture 5',
        cover: 0,
      );
      await importer.dispose();
      return notebook;
    }))!;
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: nb),
        ),
      ),
    );
    await pumpUntilPdfRendered(tester);
    final session = tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;
    var finished = false;
    final page = services.pages.pagesOf(nb.id).first;
    final done = session.commands!
        .replacePdf(tester.element(find.byType(EditorCanvas)), page, file: XFile(file.path))
        .whenComplete(() => finished = true);
    await pumpUntil(tester, () => finished);
    await done;
    await tester.pump();
    expect(find.text('These pages already show “Lecture 5.pdf”'), findsOneWidget);
    expect(await tester.runAsync(() => services.blobs.has(shaOf(old))), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
