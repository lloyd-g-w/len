import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium, pixel;
import 'support/encrypted_pdf.dart';
import 'support/pdf_fixtures.dart';

/// An A4 page with a red square top-left and a line of Helvetica text.
Future<Uint8List> textPdf() {
  final doc = pw.PdfDocument();
  final page = pw.PdfPage(doc, pageFormat: pw.PdfPageFormat.a4);
  final h = page.pageFormat.height;
  page.getGraphics()
    ..setFillColor(pw.PdfColors.red)
    ..drawRect(0, h - 200, 200, 200)
    ..fillPath()
    ..setFillColor(pw.PdfColors.black)
    ..drawString(pw.PdfFont.helvetica(doc), 24, 'Lecture notes vectors', 60, h - 300);
  return doc.save();
}

/// A page whose `/Contents` array holds a non-stream: PDFium shows the red
/// rectangle, Len's copier refuses the page (→ image fallback).
Uint8List oddContentsPdf() {
  final pdf = RawPdf('1.4');
  pdf.obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  pdf.obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  pdf.obj(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents [4 0 R 5 0 R] >>');
  const ops = '1 0 0 rg 0 100 150 100 re f';
  pdf.stream(4, '<< /Length ${ops.length} >>', latin1.encode(ops));
  pdf.obj(5, '42');
  pdf.xrefTable('<< /Size 6 /Root 1 0 R >>');
  return pdf.finish();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppServices services;

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_pdf_vector_');
    services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
  });
  tearDown(() {
    services.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<List<NotebookPage>> import(Uint8List bytes) async {
    final file = File('${dir.path}/in.pdf')..writeAsBytesSync(bytes);
    final importer = PdfImporter(services);
    final nb = await importer.createNotebook(
      await importer.store(XFile(file.path)),
      title: 'PDF',
      cover: 0,
    );
    await importer.dispose();
    return services.pages.pagesOf(nb.id);
  }

  Future<(Uint8List, List<int>)> export(List<NotebookPage> pages) async {
    final rasterized = <int>[];
    final exporter = NotebookExporter(services);
    final bytes = await exporter.pdf(pages, onRasterized: rasterized.add);
    await exporter.dispose();
    return (bytes, rasterized);
  }

  Future<ui.Image> render(PdfDocument doc, int width) async {
    final page = doc.pages.first;
    final rendered = (await page.render(
      fullWidth: width.toDouble(),
      fullHeight: (width * page.height / page.width).roundToDouble(),
    ))!;
    final image = await rendered.createImage();
    rendered.dispose();
    return image;
  }

  const skip = 'PDFium not built yet (run `flutter build linux` once)';

  test(
    'imported pages are exported as vectors: text stays text, ink on top',
    skip: pdfium == null ? skip : false,
    () async {
      final pages = await import(await textPdf());
      services.strokes.save([
        Stroke(
          id: 'ink',
          surfaceId: pages[0].id,
          tool: InkTool.ballpoint,
          color: 0xFF0000FF,
          width: 12,
          points: [for (var i = 0; i < 50; i++) StrokePoint(400 + i * 4.0, 600, 0.8)],
          createdAt: 1,
        ),
      ]);
      final (bytes, rasterized) = await export(pages);
      expect(rasterized, isEmpty);
      final doc = await PdfDocument.openData(bytes);
      expect((await doc.pages.first.loadText())!.fullText, contains('Lecture notes vectors'));
      final image = await render(doc, 794);
      expect((await pixel(image, 50, 50)).r, greaterThan(0.9)); // The PDF's red square.
      expect((await pixel(image, 50, 50)).g, lessThan(0.3));
      expect((await pixel(image, 480, 600)).b, greaterThan(0.8)); // Ink above it.
      await doc.dispose();
    },
  );

  test(
    'encrypted PDFs are decrypted by PDFium, then copied as vectors',
    skip: pdfium == null ? skip : false,
    () async {
      final pages = await import(base64.decode(encryptedPdfBase64));
      final (bytes, rasterized) = await export(pages);
      expect(rasterized, isEmpty);
      final doc = await PdfDocument.openData(bytes);
      expect((await doc.pages.first.loadText())!.fullText, contains('Secret notes'));
      final image = await render(doc, 300);
      expect((await pixel(image, 20, 20)).r, greaterThan(0.9));
      await doc.dispose();
    },
  );

  test(
    'a page Len cannot copy is embedded as an image',
    skip: pdfium == null ? skip : false,
    () async {
      final pages = await import(oddContentsPdf());
      final (bytes, rasterized) = await export(pages);
      expect(rasterized, [0]);
      final doc = await PdfDocument.openData(bytes);
      final image = await render(doc, 300);
      final red = await pixel(image, 20, 20);
      expect(red.r, greaterThan(0.9));
      expect(red.g, lessThan(0.3));
      expect((await pixel(image, 250, 150)).g, greaterThan(0.9)); // White elsewhere.
      await doc.dispose();
    },
  );
}
