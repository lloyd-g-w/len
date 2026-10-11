import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium;

/// A formatted note: heading, mixed formatting, a bulleted and a
/// numbered list, a ticked checklist item, two fonts.
final TextData note = TextData.rich(
  text:
      'Shopping list\nBuy fresh milk today\nbread\neggs\nfirst step\nsecond step\n'
      'call grandma',
  spans: const [
    StyledRange(18, 23, SpanStyle(bold: true, color: 0xFFD00000)), // fresh
    StyledRange(24, 28, SpanStyle(italic: true, underline: true)), // milk
    StyledRange(29, 34, SpanStyle(highlight: 0x80FFEB3B)), // today
    StyledRange(35, 40, SpanStyle(font: TextFont.mono)), // bread
  ],
  paras: const [
    ParaStyle(heading: 1),
    ParaStyle.body,
    ParaStyle(list: ListKind.bullet),
    ParaStyle(list: ListKind.bullet, indent: 1),
    ParaStyle(list: ListKind.number),
    ParaStyle(list: ListKind.number),
    ParaStyle(list: ListKind.check, checked: true),
  ],
  font: TextFont.lora,
  fontSize: 22,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppServices services;

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_pdf_text_');
    services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
  });
  tearDown(() {
    services.dispose();
    dir.deleteSync(recursive: true);
  });

  test(
    'rich text boxes are exported as selectable text in embedded fonts, where the app lays them out',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      final nb = services.notebooks.create(
        title: 'Notes',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final page = services.pages.pagesOf(nb.id).single;
      const width = 420.0;
      final box = SurfaceElement(
        id: 'note',
        surfaceId: page.id,
        type: ElementType.text.name,
        rect: Rect.fromLTWH(120, 140, width, TextLayout.heightOf(note, width)),
        z: 1,
        createdAt: 1,
        data: note.toJson(),
      );
      services.elements.save([box]);
      final exporter = NotebookExporter(services);
      final bytes = await exporter.pdf([page]);
      final png = await exporter.png(page, scale: 1);
      await exporter.dispose();

      // The fonts are embedded (not referenced).
      final raw = String.fromCharCodes(bytes);
      expect(RegExp('/FontFile2').allMatches(raw).length, greaterThanOrEqualTo(3));

      final doc = await PdfDocument.openData(bytes);
      final text = (await doc.pages.single.loadText())!;
      for (final word in ['Shopping', 'fresh', 'milk', 'today', 'eggs', 'grandma']) {
        expect(text.fullText, contains(word));
      }
      // Numbers are text too.
      expect(text.fullText, contains('2.'));

      // Each word sits where the app's layout puts it.
      final layout = TextLayout.layout(note, width);
      final offsets = MarkerOffsets(note);
      for (final word in ['milk', 'eggs', 'grandma']) {
        final m = note.text.indexOf(word);
        final expected = layout.painter
            .getBoxesForSelection(
              TextSelection(
                baseOffset: offsets.toDisplay(m),
                extentOffset: offsets.toDisplay(m) + word.length,
              ),
            )
            .single
            .toRect()
            .shift(box.rect.topLeft);
        final at = text.fullText.indexOf(word);
        final rect = text.charRects[at];
        expect(rect.left / 0.75, closeTo(expected.left, 2), reason: word);
        final midY = (page.height * 0.75 - (rect.top + rect.bottom) / 2) / 0.75;
        expect(midY, inInclusiveRange(expected.top, expected.bottom), reason: word);
      }
      layout.dispose();

      // The PDF looks like the app's own rendering (PNG export).
      final rendered = (await doc.pages.single.render(fullWidth: 794, fullHeight: 1123))!;
      final pdfImage = await rendered.createImage();
      rendered.dispose();
      await doc.dispose();
      final pngImage = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
      if (Platform.environment['LEN_DEBUG_EXPORT'] != null) {
        for (final (name, image) in [('pdf', pdfImage), ('png', pngImage)]) {
          final out = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/len_rich_text_$name.png').writeAsBytesSync(out!.buffer.asUint8List());
        }
      }
      final a = await _ink(pdfImage, box.rect);
      final b = await _ink(pngImage, box.rect);
      expect(a.dark, closeTo(b.dark, b.dark * 0.3)); // PDFium renders a bit bolder
      expect(a.red, closeTo(b.red, math.max(b.red * 0.25, 20)));
      expect(a.yellow, closeTo(b.yellow, b.yellow * 0.25));
      expect(b.red, greaterThan(50));
      expect(b.yellow, greaterThan(200));
    },
  );
}

/// Counts dark, red and yellow (highlight) pixels inside [area].
Future<({int dark, int red, int yellow})> _ink(ui.Image image, Rect area) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var dark = 0, red = 0, yellow = 0;
  for (var y = area.top.floor(); y < area.bottom.ceil(); y++) {
    for (var x = area.left.floor(); x < area.right.ceil(); x++) {
      final i = (y * image.width + x) * 4;
      final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2);
      if (r < 100 && g < 100 && b < 100) dark++;
      if (r > 150 && g < 80 && b < 80) red++;
      if (r > 200 && g > 200 && b < 170) yellow++;
    }
  }
  return (dark: dark, red: red, yellow: yellow);
}
