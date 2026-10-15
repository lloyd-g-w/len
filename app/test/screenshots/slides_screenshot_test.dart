import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

import '../pdf_test.dart' show pdfium;
import '../support/real_async.dart';
import 'screenshot_harness.dart';

/// A 16:9 slide deck, as a lecturer shares it.
Future<List<int>> slideDeck(int count) {
  final doc = pw.PdfDocument();
  final font = pw.PdfFont.helvetica(doc);
  final bold = pw.PdfFont.helveticaBold(doc);
  for (var i = 1; i <= count; i++) {
    final page = pw.PdfPage(doc, pageFormat: const pw.PdfPageFormat(720, 405));
    page.getGraphics()
      ..setFillColor(const pw.PdfColor(0.1, 0.2, 0.45))
      ..drawRect(0, 360, 720, 45)
      ..fillPath()
      ..setFillColor(pw.PdfColors.white)
      ..drawString(bold, 22, 'Lecture 5 - Slide $i', 30, 374)
      ..setFillColor(pw.PdfColors.black)
      ..drawString(font, 18, '- Newton\'s second law: F = m a', 40, 300)
      ..drawString(font, 18, '- Momentum p = m v is conserved', 40, 260)
      ..drawString(font, 18, '- Impulse J = F dt = dp', 40, 220)
      ..drawString(font, 10, '$i / $count', 670, 15);
  }
  return doc.save();
}

/// Lecture slides on a portrait tablet and a phone: the editor, a blank
/// page added after a slide, and the overview.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });

  for (final (name, size, dpr) in [
    ('tablet_portrait', const Size(800, 1280), 1.0),
    ('phone', const Size(390, 844), 2.0),
  ]) {
    testWidgets('slides $name', skip: pdfium == null, (tester) async {
      setWindow(tester, size, dpr: dpr);
      final dir = Directory.systemTemp.createTempSync('len_slides_shot_');
      final services = AppServices.create(
        AppDatabase.inMemory(),
        blobBackend: FileBlobBackend(dir.path),
      );
      addTearDown(() {
        services.dispose();
        dir.deleteSync(recursive: true);
      });
      final nb = await tester.runAsync(() async {
        final file = File('${dir.path}/Lecture 5.pdf')..writeAsBytesSync(await slideDeck(12));
        final importer = PdfImporter(services);
        final notebook = await importer.createNotebook(
          await importer.store(XFile(file.path)),
          title: 'Lecture 5',
          cover: 0,
        );
        await importer.dispose();
        return notebook;
      });
      await pumpApp(tester, services, EditorScreen(notebook: nb!));
      await pumpUntilPdfRendered(tester);
      await settle(tester);
      await shoot(tester, 'slides_${name}');

      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await tester.tap(find.text('Page').last);
      await settle(tester);
      await tester.tap(find.text('Add page after'));
      await pumpUntilPdfRendered(tester);
      await settle(tester);
      await shoot(tester, 'slides_added_${name}');

      await tester.tap(find.byTooltip('All pages'));
      await pumpUntilPdfRendered(tester);
      await settle(tester);
      await shoot(tester, 'slides_overview_${name}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
