import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/pdf_text_source.dart';
import 'package:len/data/search/search_index.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/search/editor/editor_search_bar.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:len/ui/app_theme.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'content_golden_test.dart' show loadFonts;
import 'pdf_test.dart' show pdfium;

/// A two-page A4 PDF with real (Helvetica) text.
Future<Uint8List> textPdf() {
  final doc = pw.Document();
  for (final lines in const [
    ['Lecture 4: Thermodynamics', 'The first law conserves energy.'],
    ['Entropy', 'In an isolated system entropy never decreases.', 'Energy flows as heat.'],
  ]) {
    doc.addPage(
      pw.Page(
        pageFormat: pw.PdfPageFormat.a4,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 18),
                child: pw.Text(line, style: const pw.TextStyle(fontSize: 22)),
              ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppServices services;
  final skip = pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : null;

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_search_pdf_');
    services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
  });
  tearDown(() {
    services.dispose();
    dir.deleteSync(recursive: true);
  });

  test('PDFium extracts page text and glyph boxes', skip: skip, () async {
    final doc = await const PdfrxTextSource().open(await textPdf());
    addTearDown(doc.dispose);
    expect(doc.pageCount, 2);
    final text = await doc.pageText(1);
    expect(text, contains('entropy never decreases'));
    final glyphs = (await doc.glyphs(1))!;
    final start = glyphs.text.indexOf('entropy never');
    final rects = glyphs.rectsFor(start, start + 'entropy'.length);
    expect(rects, hasLength(1), reason: 'one word, one line');
    final r = rects.single;
    // Normalised to the page, top-left origin, inside the text area.
    expect(r.left, greaterThan(0));
    expect(r.right, lessThan(1));
    expect(r.top, greaterThan(0));
    expect(r.top, lessThan(0.3));
    expect(r.height, closeTo(22 / pw.PdfPageFormat.a4.height, 0.02));
  });

  testWidgets('imported PDF text is searchable and highlighted in the editor', skip: skip != null, (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(900, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadFonts();
    final nb = await tester.runAsync(() async {
      final file = File('${dir.path}/Thermo.pdf')..writeAsBytesSync(await textPdf());
      final importer = PdfImporter(services);
      final notebook = await importer.createNotebook(
        await importer.store(XFile(file.path)),
        title: 'Thermo',
        cover: 0,
      );
      await importer.dispose();
      await services.search.indexPdfs(); // Started by the import; wait for it.
      return notebook;
    });
    final hits = services.search.search('entropy');
    expect(hits.single.kind, SearchHitKind.pdf);
    expect(hits.single.pageIndex, 1);

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: nb!),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search in notebook'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'energy');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('2 matches'), findsOneWidget);
    await tester.tap(find.byTooltip('Next (Enter)'));
    await tester.tap(find.byTooltip('Next (Enter)'));
    // Glyphs and the page render on PDFium's worker; give it real time.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('2 of 2'), findsOneWidget);
    final controller = tester.widget<EditorSearchBar>(find.byType(EditorSearchBar)).controller;
    final rects = controller.rectsOf(controller.currentMatch!);
    expect(rects, hasLength(1));
    expect(controller.currentMatch!.pageIndex, 1);
    await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/search_pdf.png'));
    await tester.pumpWidget(const SizedBox());
  });
}
