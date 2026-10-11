import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart' show MaterialApp, Rect, Size, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text_data.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/features/documents/pdf/pdf_background_cache.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/documents/pdf/pdf_renderer.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:len/ui/app_theme.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

/// A two-page PDF: a red square on an A4 page, then a Letter page.
Future<Uint8List> samplePdf() {
  final doc = pw.PdfDocument();
  final a4 = pw.PdfPage(doc, pageFormat: pw.PdfPageFormat.a4);
  a4.getGraphics()
    ..setFillColor(pw.PdfColors.red)
    ..drawRect(0, a4.pageFormat.height - 200, 200, 200)
    ..fillPath();
  pw.PdfPage(doc, pageFormat: pw.PdfPageFormat.letter);
  return doc.save();
}

Future<Color> pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

typedef Color = ui.Color;

/// `flutter test` does not bundle native assets; use the PDFium library a
/// regular build downloaded (see pdfium_dart's build hook).
final String? pdfium = [
  '.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_7811/linux-x64/libpdfium.so',
  'build/native_assets/linux/libpdfium.so',
].map((p) => File(p).absolute.path).where((p) => File(p).existsSync()).firstOrNull;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppServices services;

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_pdf_test_');
    services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
  });
  tearDown(() {
    services.dispose();
    dir.deleteSync(recursive: true);
  });

  test(
    'import a PDF, render its pages, export with ink',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      final file = File('${dir.path}/Lecture_3.pdf')..writeAsBytesSync(await samplePdf());
      final importer = PdfImporter(services);
      final sha = await importer.store(XFile(file.path));
      final nb = await importer.createNotebook(
        sha,
        title: PdfImporter.titleFor('Lecture_3.pdf'),
        cover: 0,
      );
      await importer.dispose();
      expect(nb.title, 'Lecture 3');

      final pages = services.pages.pagesOf(nb.id);
      expect(pages, hasLength(2));
      expect(pages[0].width, closeTo(794, 1)); // A4 at 96 dpi
      expect(pages[1].height, closeTo(1056, 1)); // Letter
      expect(pages.map((p) => p.background!.pageIndex), [0, 1]);
      expect(services.blobs.pendingUploads(), [sha]);

      // Background rendering: the red square sits at the top-left.
      final renderer = PdfRenderer(services.blobs);
      final image = (await renderer.render(sha, 0, 400))!;
      expect(image.width, 400);
      final red = await pixel(image, 20, 20);
      expect(red.r, greaterThan(0.9));
      expect(red.g, lessThan(0.4));
      final white = await pixel(image, 300, 500);
      expect(white.g, greaterThan(0.9));
      await renderer.dispose();

      // Ink on the first page, then export the notebook.
      services.strokes.save([
        Stroke(
          id: 'ink',
          surfaceId: pages[0].id,
          tool: InkTool.pen,
          color: 0xFF0000FF,
          width: 12,
          points: [for (var i = 0; i < 50; i++) StrokePoint(400 + i * 4.0, 600, 0.8)],
          createdAt: 1,
        ),
      ]);
      final exporter = NotebookExporter(services);
      final pdfBytes = await exporter.pdf(pages, title: nb.title);
      final png = await exporter.png(pages[0], scale: 1);
      await exporter.dispose();
      expect(String.fromCharCodes(pdfBytes.take(5)), '%PDF-');
      expect(png.sublist(1, 4), 'PNG'.codeUnits);

      final exported = await PdfDocument.openData(pdfBytes);
      expect(exported.pages, hasLength(2));
      expect(exported.pages[0].width, closeTo(595, 1)); // A4 in points
      final rendered = (await exported.pages[0].render(fullWidth: 794, fullHeight: 1123))!;
      final img = await rendered.createImage();
      rendered.dispose();
      final ink = await pixel(img, 480, 600);
      expect(ink.b, greaterThan(0.8));
      expect(ink.r, lessThan(0.3));
      final background = await pixel(img, 50, 50);
      expect(background.r, greaterThan(0.8)); // The PDF page survived.
      expect(background.g, lessThan(0.4));
      await exported.dispose();
    },
  );

  test(
    'templates and highlighter export as vectors',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      final nb = services.notebooks.create(
        title: 'Cornell',
        kind: NotebookKind.paged,
        paper: PaperStyle.cornell,
        coverColor: 0,
        firstPage: const PageTemplate(paper: Paper(PaperStyle.cornell), color: PaperColor.cream),
      );
      final page = services.pages.pagesOf(nb.id).single;
      services.strokes.save([
        Stroke(
          id: 'hl',
          surfaceId: page.id,
          tool: InkTool.highlighter,
          color: 0xFFFACC15,
          width: 24,
          points: [for (var i = 0; i < 30; i++) StrokePoint(300 + i * 8.0, 300, 0.5)],
          createdAt: 1,
        ),
      ]);
      final exporter = NotebookExporter(services);
      final bytes = await exporter.pdf([page]);
      await exporter.dispose();
      final doc = await PdfDocument.openData(bytes);
      final rendered = (await doc.pages.single.render(fullWidth: 794, fullHeight: 1123))!;
      final img = await rendered.createImage();
      rendered.dispose();
      await doc.dispose();
      if (Platform.environment['LEN_DEBUG_EXPORT'] != null) {
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('/tmp/len_cornell.png').writeAsBytesSync(png!.buffer.asUint8List());
      }
      final paper = await pixel(img, 700, 1000);
      expect(paper.b, lessThan(paper.r)); // Cream, not white.
      final highlight = await pixel(img, 400, 300);
      expect(highlight.r, greaterThan(0.85));
      expect(highlight.b, lessThan(0.8)); // Translucent yellow over cream.
      expect(highlight.b, greaterThan(0.4));
    },
  );

  test(
    'text boxes are exported to PDF and PNG',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      final nb = services.notebooks.create(
        title: 'Notes',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final page = services.pages.pagesOf(nb.id).single;
      services.elements.save([
        SurfaceElement(
          id: 'title',
          surfaceId: page.id,
          type: ElementType.text.name,
          rect: const Rect.fromLTWH(100, 100, 400, 80),
          z: 1,
          createdAt: 1,
          data: const TextData(text: '████████', fontSize: 48, color: 0xFFD00000).toJson(),
        ),
      ]);
      final exporter = NotebookExporter(services);
      final bytes = await exporter.pdf([page]);
      final png = await exporter.png(page, scale: 1);
      await exporter.dispose();
      final decoded = await ui.instantiateImageCodec(png);
      final pngImage = (await decoded.getNextFrame()).image;
      final doc = await PdfDocument.openData(bytes);
      final rendered = (await doc.pages.single.render(fullWidth: 794, fullHeight: 1123))!;
      final img = await rendered.createImage();
      rendered.dispose();
      await doc.dispose();
      for (final image in [img, pngImage]) {
        if (Platform.environment['LEN_DEBUG_EXPORT'] != null) {
          final out = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/len_text_${image.width}_${identical(image, img)}.png')
              .writeAsBytesSync(out!.buffer.asUint8List());
        }
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        int redIn(int x0, int y0, int x1, int y1) {
          var n = 0;
          for (var y = y0; y < y1; y++) {
            for (var x = x0; x < x1; x++) {
              final i = (y * image.width + x) * 4;
              if (data.getUint8(i) > 150 && data.getUint8(i + 1) < 80) n++;
            }
          }
          return n;
        }

        // Red glyphs where the box is, nothing elsewhere.
        expect(redIn(100, 100, 500, 180), greaterThan(1000));
        expect(redIn(0, 200, 794, 1123), 0);
      }
    },
  );

  testWidgets('the editor shows imported PDF pages under the ink', skip: pdfium == null, (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(900, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final nb = await tester.runAsync(() async {
      final file = File('${dir.path}/doc.pdf')..writeAsBytesSync(await samplePdf());
      final importer = PdfImporter(services);
      final notebook = await importer.createNotebook(
        await importer.store(XFile(file.path)),
        title: 'PDF',
        cover: 0,
      );
      await importer.dispose();
      return notebook;
    });
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
    // Rendering happens on PDFium's worker; give it real time.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/editor_pdf.png'));
    await tester.pumpWidget(const SizedBox());
  });

  test('background cache quantises resolutions', () {
    expect(PdfBackgroundCache.bucketFor(10), 256);
    expect(PdfBackgroundCache.bucketFor(256), 256);
    expect(PdfBackgroundCache.bucketFor(300), 362);
    expect(PdfBackgroundCache.bucketFor(1000), 1024);
    expect(PdfBackgroundCache.bucketFor(100000), PdfBackgroundCache.maxWidth);
    expect(PdfBackgroundCache.bucketFor(double.nan), 256);
  });

  test(
    'without local files (web) PDFs are imported from bytes and opened from memory',
    skip: pdfium == null,
    () async {
      final memory = AppServices.create(AppDatabase.inMemory());
      addTearDown(memory.dispose);
      final importer = PdfImporter(memory);
      final sha = await importer.store(XFile.fromData(await samplePdf(), name: 'web.pdf'));
      expect(memory.blobs.localPath(sha), isNull);
      expect((await importer.specsFor(sha)).length, 2);
      await importer.dispose();
      final renderer = PdfRenderer(memory.blobs);
      final image = (await renderer.render(sha, 0, 200))!;
      expect(image.width, 200);
      expect((await pixel(image, 10, 10)).r, greaterThan(0.9));
      await renderer.dispose();
    },
  );
}
