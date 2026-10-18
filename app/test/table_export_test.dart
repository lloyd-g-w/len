import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium;
import 'table_layout_test.dart' show shopping;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'tables are exported as selectable text in their cells, with their grid',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
      Pdfrx.pdfiumModulePath = pdfium;
      final dir = Directory.systemTemp.createTempSync('len_pdf_table_');
      final services = AppServices.create(
        AppDatabase.inMemory(),
        blobBackend: FileBlobBackend(dir.path),
      );
      addTearDown(() {
        services.dispose();
        dir.deleteSync(recursive: true);
      });
      final nb = services.notebooks.create(
        title: 'Tables',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final page = services.pages.pagesOf(nb.id).single;
      const width = 320.0;
      final data = shopping();
      final box = SurfaceElement(
        id: 'table',
        surfaceId: page.id,
        type: ElementType.text.name,
        rect: Rect.fromLTWH(100, 120, width, TextLayout.heightOf(data, width)),
        z: 1,
        createdAt: 1,
        data: data.toJson(),
      );
      services.elements.save([box]);
      final exporter = NotebookExporter(services);
      final bytes = await exporter.pdf([page]);
      await exporter.dispose();
      final doc = await PdfDocument.openData(bytes);
      final text = (await doc.pages.single.loadText())!;
      final layout = TextLayout.layout(data, width);
      for (final word in ['Item', 'Price', 'sourdough', 'Milk', '1.10', 'Total']) {
        final at = text.fullText.indexOf(word);
        expect(at, greaterThanOrEqualTo(0), reason: word);
        final m = data.text.indexOf(word);
        final expected = layout.boxesOf(m, m + 1).first.toRect().shift(box.rect.topLeft);
        final rect = text.charRects[at];
        expect(rect.left / 0.75, closeTo(expected.left, 2), reason: word);
        final midY = (page.height * 0.75 - (rect.top + rect.bottom) / 2) / 0.75;
        expect(midY, inInclusiveRange(expected.top - 1, expected.bottom + 1), reason: word);
      }
      layout.dispose();
      await doc.dispose();
    },
  );
}
