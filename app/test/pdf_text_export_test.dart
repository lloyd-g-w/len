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
import 'package:len/ink/elements/text_flow_layout.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart';

import 'hanging_indent_test.dart' show leftOf, wrappedList, wrappedListWidth;
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
      final offsets = layout.offsets;
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

  test(
    'wrapped list items are exported with hanging indents',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      final nb = services.notebooks.create(
        title: 'Lists',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final page = services.pages.pagesOf(nb.id).single;
      final box = SurfaceElement(
        id: 'lists',
        surfaceId: page.id,
        type: ElementType.text.name,
        rect: Rect.fromLTWH(
          100,
          100,
          wrappedListWidth,
          TextLayout.heightOf(wrappedList, wrappedListWidth),
        ),
        z: 1,
        createdAt: 1,
        data: wrappedList.toJson(),
      );
      services.elements.save([box]);
      final exporter = NotebookExporter(services);
      final bytes = await exporter.pdf([page]);
      await exporter.dispose();
      final doc = await PdfDocument.openData(bytes);
      final text = (await doc.pages.single.loadText())!;
      final layout = TextLayout.layout(wrappedList, wrappedListWidth);
      final source = wrappedList.text;
      double pdfLeft(int m) {
        // The word starting at model offset [m], found in the PDF's text.
        final word = RegExp(r'\S+').matchAsPrefix(source, m)!.group(0)!;
        final before = RegExp(r'\S+')
            .allMatches(source.substring(0, m))
            .where((w) => w.group(0) == word);
        var at = -1;
        for (var k = 0; k <= before.length; k++) {
          at = text.fullText.indexOf(word, at + 1);
        }
        return text.charRects[at].left / 0.75 - box.rect.left;
      }

      var start = 0;
      var checked = 0;
      for (var line = 0; line < wrappedList.paras.length; line++) {
        final nl = source.indexOf('\n', start);
        final end = nl < 0 ? source.length : nl;
        if (wrappedList.paras[line].isList) {
          final textStart = pdfLeft(start);
          expect(textStart, closeTo(leftOf(layout, start), 2.5), reason: 'line $line');
          for (final w in layout.wraps.where((w) => w > start && w < end)) {
            expect(pdfLeft(w), closeTo(textStart, 2.5), reason: 'wrap at $w');
            checked++;
          }
        }
        start = end + 1;
      }
      expect(checked, greaterThanOrEqualTo(4));
      layout.dispose();
      await doc.dispose();
    },
  );

  test(
    'a box flowing over two pages exports page by page: numbers run on, no marker repeats',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      final nb = services.notebooks.create(
        title: 'Flow',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      services.pages.addPage(nb.id);
      final pages = services.pages.pagesOf(nb.id);
      final items = [for (var i = 1; i <= 8; i++) 'Item$i ${List.filled(10, 'word$i').join(' ')}'];
      final whole = TextData.rich(
        text: items.join('\n'),
        paras: [for (final _ in items) const ParaStyle(list: ListKind.number)],
        fontSize: 20,
      );
      const width = 300.0;
      final layout = TextLayout.layout(whole, width);
      final line = layout.painter.computeLineMetrics().first.height;
      // Room for 7 lines on the first page: the split falls inside an item.
      final parts = TextFlowLayout.split(layout, (k) => k == 0 ? line * 7.5 : 10000);
      layout.dispose();
      expect(parts, hasLength(2));
      expect(parts[1].joined, isTrue);
      final head = SurfaceElement(
        id: 'head',
        surfaceId: pages[0].id,
        type: ElementType.text.name,
        rect: Rect.fromLTWH(100, 600, width, parts[0].height),
        z: 1,
        createdAt: 1,
        data: parts[0].dataOf(whole).toJson(),
      );
      final next = SurfaceElement(
        id: 'next',
        surfaceId: pages[1].id,
        type: ElementType.text.name,
        rect: Rect.fromLTWH(100, 60, width, parts[1].height),
        z: 1,
        createdAt: 1,
        data: parts[1].dataOf(whole, from: 'head').toJson(),
      );
      services.elements.save([head, next]);
      final exporter = NotebookExporter(services);
      final bytes = await exporter.pdf(pages);
      await exporter.dispose();
      final doc = await PdfDocument.openData(bytes);
      final first = (await doc.pages[0].loadText())!.fullText;
      final second = (await doc.pages[1].loadText())!.fullText;
      await doc.dispose();
      // Every word once, in order over the two pages.
      final all = '$first $second'.replaceAll(RegExp(r'\s+'), ' ');
      for (final item in items) {
        expect(all, contains(item.split(' ').first));
      }
      final split = TextData.fromJson(next.data);
      final continued = TextLayout.markersOf(split).first;
      expect(continued.continued, isTrue);
      // The item cut by the page shows its number on the first page only;
      // the items after it count on.
      expect(first, contains(continued.label));
      expect(second, isNot(contains(continued.label)));
      expect(second, contains('${continued.number + 1}.'));
      expect(second, isNot(contains('1.')));
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
