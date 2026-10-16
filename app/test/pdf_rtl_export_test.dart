import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/documents/export/arabic_forms.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium;

/// English with Hebrew words, an Arabic paragraph (right-aligned in this
/// left-to-right box) and a numbered Hebrew item. Letters do not repeat,
/// so each can be found in the PDF's text.
final TextData sample = TextData.rich(
  text: 'Hello אבג (דהז)\nسمك لا تَخ\nטיכ',
  paras: const [
    ParaStyle.body,
    ParaStyle.body,
    ParaStyle(list: ListKind.number),
  ],
  font: TextFont.lora,
  fontSize: 24,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Arabic letters take their joining forms; lam-alef is one ligature', () {
    String shaped(String s) => ArabicForms.shape(s).map((g) => g.glyph).join();
    String part2(String s, int start, int end) =>
        ArabicForms.shape(s, start, end).map((g) => g.glyph).join();
    // Seen (initial), meem (medial), kaf (final).
    expect(shaped('سمك'), '\uFEB3\uFEE4\uFEDA');
    // Alef joins only the letter before: beh-alef-beh = initial, final, isolated.
    expect(shaped('باب'), '\uFE91\uFE8E\uFE8F');
    expect(shaped('لا'), '\uFEFB');
    expect(shaped('سلام'), '\uFEB3\uFEFC\uFEE1');
    expect(ArabicForms.shape('سلام')[1], (glyph: '\uFEFC', start: 1, end: 3));
    // Marks are transparent to joining and kept.
    expect(shaped('بَب'), '\uFE91\u064E\uFE90');
    // Marks between lam and alef stay (over the ligature).
    expect(shaped('لَا'), '\uFEFB\u064E');
    expect(ArabicForms.shape('لَا')[1], (glyph: '\u064E', start: 1, end: 2));
    // Part of a word (a stretch formatted differently) joins the letters
    // around it, as on screen: kaf-teh-alef-beh with only teh coloured.
    final word = 'كتاب';
    String part(int start, int end) =>
        ArabicForms.shape(word, start, end).map((g) => g.glyph).join();
    expect(part(0, 1) + part(1, 2) + part(2, 4), '\uFEDB\uFE98\uFE8E\uFE8F');
    expect(ArabicForms.shape(word, 1, 2).single, (glyph: '\uFE98', start: 1, end: 2));
    // A lam and an alef formatted apart join without their ligature.
    expect(part2('سلام', 0, 2) + part2('سلام', 2, 4), '\uFEB3\uFEE0\uFE8E\uFEE1');
    // A zero-width joiner joins: heh before it takes its initial form.
    expect(shaped('ه\u200D'), '\uFEEB\u200D');
    // Alef maksura and noon ghunna join both sides (Unicode: dual joining);
    // their initial and medial forms are the dotless tooth (FBE8 / FBE9).
    expect(shaped('بىب'), '\uFE91\uFBE9\uFE90');
    expect(shaped('ىب'), '\uFBE8\uFE90');
    expect(shaped('بى'), '\uFE91\uFEF0');
    expect(shaped('ى'), '\uFEEF');
    expect(shaped('بںب'), '\uFE91\uFBE9\uFE90');
    expect(shaped('ںب'), '\uFBE8\uFE90');
    expect(shaped('بں'), '\uFE91\uFB9F');
    expect(shaped('ں'), '\uFB9E');
    // Persian; other characters pass through.
    expect(shaped('پ'), '\uFB56');
    expect(shaped('a1'), 'a1');
  });

  late Directory dir;
  late AppServices services;

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_pdf_rtl_');
    services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
  });
  tearDown(() {
    services.dispose();
    dir.deleteSync(recursive: true);
  });

  test(
    'Hebrew and Arabic export as text, each glyph where the app lays it out',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      final nb = services.notebooks.create(
        title: 'RTL',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final page = services.pages.pagesOf(nb.id).single;
      const width = 360.0;
      final box = SurfaceElement(
        id: 'rtl',
        surfaceId: page.id,
        type: ElementType.text.name,
        rect: Rect.fromLTWH(120, 140, width, TextLayout.heightOf(sample, width)),
        z: 1,
        createdAt: 1,
        data: sample.toJson(),
      );
      services.elements.save([box]);
      final exporter = NotebookExporter(services);
      final bytes = await exporter.pdf([page]);
      final png = await exporter.png(page, scale: 1);
      await exporter.dispose();

      // Written as text (not an image), with the Hebrew and Arabic fonts.
      final raw = String.fromCharCodes(bytes);
      expect(raw, contains('NotoSansHebrew'));
      expect(raw, contains('NotoSansArabic'));
      final doc = await PdfDocument.openData(bytes);
      final text = (await doc.pages.single.loadText())!;
      final full = text.fullText;

      final layout = TextLayout.layout(sample, width);
      double pdfLeft(String char) {
        final at = full.indexOf(char);
        expect(at, isNot(-1), reason: 'U+${char.codeUnitAt(0).toRadixString(16)} in the PDF');
        return text.charRects[at].left / 0.75 - box.rect.left;
      }

      double appLeft(int start, [int? end]) => layout
          .boxesOf(start, end ?? start + 1)
          .map((b) => b.left)
          .reduce((a, b) => a < b ? a : b);

      // Hebrew letters right to left, each at its laid-out place; the
      // brackets around a Hebrew word are mirrored as on screen.
      final t = sample.text;
      for (final letter in ['א', 'ב', 'ג', 'ד', 'ה', 'ז', 'ט', 'י', 'כ']) {
        expect(pdfLeft(letter), closeTo(appLeft(t.indexOf(letter)), 1.5), reason: letter);
      }
      expect(pdfLeft('א'), greaterThan(pdfLeft('ב')));
      expect(pdfLeft('ב'), greaterThan(pdfLeft('ג')));
      final open = layout.boxesOf(t.indexOf('('), t.indexOf('(') + 1).single;
      expect(open.direction, TextDirection.rtl);
      expect(full, contains(')'));
      // Arabic right to left, where the app put it, in its joined forms
      // (as wide as the app's shaped glyphs; PDFium reads them back as the
      // letters, the lam-alef ligature as both).
      final seen = t.indexOf('س');
      for (var k = 0; k < 3; k++) {
        final letter = t[seen + k];
        expect(pdfLeft(letter), closeTo(appLeft(seen + k), 1.5), reason: letter);
        final pdfWidth = text.charRects[full.indexOf(letter)].width / 0.75;
        final appWidth = layout.boxesOf(seen + k, seen + k + 1).single.toRect().width;
        expect(pdfWidth, closeTo(appWidth, appWidth * 0.2 + 1), reason: letter);
      }
      final ligature = [pdfLeft('ل'), pdfLeft('ا')].reduce((a, b) => a < b ? a : b);
      expect(ligature, closeTo(appLeft(seen + 4, seen + 6), 1.5));
      expect(pdfLeft('س'), greaterThan(pdfLeft('ك')));
      // A mark sits over its letter.
      final teh = t.indexOf('ت');
      final mark = text.charRects[full.indexOf('\u064E')];
      final letter = layout.boxesOf(teh, teh + 2).first; // one cluster
      expect(
        (mark.left + mark.right) / 2 / 0.75 - box.rect.left,
        inInclusiveRange(letter.left, letter.right),
      );
      // The Arabic paragraph is right-aligned in this left-to-right box.
      expect(pdfLeft('س'), greaterThan(width * 0.75));
      // The Hebrew item's number reads ".1", right of its text.
      expect(full, contains('.1'));
      expect(
        text.charRects[full.indexOf('.1')].left / 0.75 - box.rect.left,
        greaterThan(pdfLeft('ט')),
      );
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
          File('/tmp/len_rtl_text_$name.png').writeAsBytesSync(out!.buffer.asUint8List());
        }
      }
      final a = await _dark(pdfImage, box.rect), b = await _dark(pngImage, box.rect);
      expect(a.total, closeTo(b.total, b.total * 0.3));
      // Ink falls in the same places: compare the left, middle and right.
      for (var k = 0; k < 3; k++) {
        expect(a.thirds[k], closeTo(b.thirds[k], b.thirds[k] * 0.35 + 20), reason: 'third $k');
      }
    },
  );
}

/// Dark pixels inside [area], in all and per horizontal third.
Future<({int total, List<int> thirds})> _dark(ui.Image image, Rect area) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final thirds = [0, 0, 0];
  for (var y = area.top.floor(); y < area.bottom.ceil(); y++) {
    for (var x = area.left.floor(); x < area.right.ceil(); x++) {
      final i = (y * image.width + x) * 4;
      if (data.getUint8(i) < 100 && data.getUint8(i + 1) < 100 && data.getUint8(i + 2) < 100) {
        thirds[((x - area.left) * 3 ~/ area.width).clamp(0, 2)]++;
      }
    }
  }
  return (total: thirds.fold(0, (a, b) => a + b), thirds: thirds);
}
