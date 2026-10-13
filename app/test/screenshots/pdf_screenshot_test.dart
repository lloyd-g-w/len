import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/pdf/pdf_layer.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

import '../pdf_interaction_test.dart' show interactivePdf;
import '../pdf_test.dart' show pdfium;
import 'screenshot_harness.dart';

/// PDF text selection (menu and handles) and the outline sheet, with real
/// fonts, on a tablet and a phone, light and dark.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });

  Future<void> wait(WidgetTester tester, [int times = 20]) async {
    for (var i = 0; i < times; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
  }

  for (final (name, size, dpr) in [
    ('tablet', const Size(1280, 800), 1.0),
    ('phone', const Size(390, 844), 2.0),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('pdf selection $name ${mode.name}', skip: pdfium == null, (tester) async {
        setWindow(tester, size, dpr: dpr);
        final dir = Directory.systemTemp.createTempSync('len_pdf_shot_');
        final services = AppServices.create(
          AppDatabase.inMemory(),
          blobBackend: FileBlobBackend(dir.path),
        );
        addTearDown(() {
          services.dispose();
          dir.deleteSync(recursive: true);
        });
        final nb = await tester.runAsync(() async {
          final file = File('${dir.path}/Lecture.pdf')..writeAsBytesSync(await interactivePdf());
          final importer = PdfImporter(services);
          final notebook = await importer.createNotebook(
            await importer.store(XFile(file.path)),
            title: 'Lecture',
            cover: 0,
          );
          await importer.dispose();
          return notebook;
        });
        await pumpApp(tester, services, EditorScreen(notebook: nb!), mode: mode);
        await wait(tester);
        final pdf = tester.widget<PdfLayer>(find.byType(PdfLayer)).interaction;
        final page = pdf.doc.pages.first;
        final glyphs = pdf.info.glyphs(page.background!.blob, 0)!;
        final start = glyphs.text.indexOf('PDF');
        pdf.selection.select(page, glyphs, start, glyphs.text.indexOf('text') + 4, menu: true);
        await settle(tester);
        await shoot(tester, 'pdf_selection_${name}_${mode.name}');

        pdf.selection.clear();
        await settle(tester);
        await tester.tap(find.byTooltip('All pages'));
        await settle(tester);
        await tester.tap(find.text('Outline'));
        await wait(tester, 10);
        await settle(tester);
        await shoot(tester, 'pdf_outline_${name}_${mode.name}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
