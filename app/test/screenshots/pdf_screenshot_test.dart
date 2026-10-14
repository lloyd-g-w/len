import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/editor/chrome/editor_tips.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/pdf/pdf_layer.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

import '../pdf_interaction_test.dart' show interactivePdf, pdfTextAt;
import '../pdf_test.dart' show pdfium;
import '../support/real_async.dart';
import 'screenshot_harness.dart';

/// PDF text selection (menu and handles), a highlighter stroke snapped to
/// the text and the outline sheet, with real fonts, on a tablet and a
/// phone, light and dark.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });

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
        final pdf = tester.widget<PdfLayer>(find.byType(PdfLayer)).interaction;
        final page = pdf.doc.pages.first;
        await pumpUntil(
          tester,
          () => pdf.info.glyphs(page.background!.blob, 0) != null,
          reason: 'glyphs',
        );
        await pumpUntilPdfRendered(tester);
        final glyphs = pdf.info.glyphs(page.background!.blob, 0)!;
        final start = glyphs.text.indexOf('PDF');
        pdf.selection.select(page, glyphs, start, glyphs.text.indexOf('text') + 4, menu: true);
        await settle(tester);
        await shoot(tester, 'pdf_selection_${name}_${mode.name}');

        // A wobbly highlighter stroke along a line snaps to its words.
        pdf.selection.clear();
        services.settings.markTipSeen(EditorTip.penButton.name); // Not in the shot.
        pdf.tools
          ..stylusOnly = true
          ..tool = EditorTool.highlighter;
        await settle(tester);
        final from = pdfTextAt(pdf, 'Second'), to = pdfTextAt(pdf, 'text', i: 2);
        final pen = await tester.startGesture(from, kind: PointerDeviceKind.stylus);
        for (var t = 0.05; t <= 1.0001; t += 0.05) {
          await pen.moveTo(Offset.lerp(from, to, t)! + Offset(0, t * 20 % 2 < 1 ? 2 : -2));
          await tester.pump(const Duration(milliseconds: 8));
        }
        await pen.up();
        await settle(tester);
        await shoot(tester, 'pdf_highlight_snapped_${name}_${mode.name}');
        pdf.tools.tool = EditorTool.pen;
        await settle(tester);

        await tester.tap(find.byTooltip('All pages'));
        await settle(tester);
        await tester.tap(find.text('Outline'));
        await pumpUntil(
          tester,
          () => find.text('Introduction').evaluate().isNotEmpty,
          reason: 'the outline',
        );
        await settle(tester);
        await shoot(tester, 'pdf_outline_${name}_${mode.name}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
