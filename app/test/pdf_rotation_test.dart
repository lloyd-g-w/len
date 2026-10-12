import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/pdf_text_source.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/pdf_page_space.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/documents/pdf/pdf_renderer.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/pdf/pdf_interaction.dart';
import 'package:len/features/editor/pdf/pdf_layer.dart';
import 'package:len/features/editor/pdf/pdf_text_selection.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:len/ui/app_theme.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

import 'pdf_test.dart' show pdfium;

/// One A4 page per entry of [turns], shown turned clockwise by that many
/// quarter turns (`/Rotate`): two lines of text, a web link over the first
/// and a link to the first page over the second.
Future<Uint8List> rotatedPdf(List<int> turns) {
  final doc = pw.PdfDocument();
  final font = pw.PdfFont.helvetica(doc);
  final pages = [
    for (final t in turns)
      pw.PdfPage(doc, pageFormat: pw.PdfPageFormat.a4, rotate: pw.PdfPageRotation.values[t]),
  ];
  doc.pdfNames.addDest('first', pages.first);
  for (final page in pages) {
    page.getGraphics()
      ..setFillColor(pw.PdfColors.black)
      ..drawString(font, 24, 'Hello PDF world', 60, 760)
      ..drawString(font, 24, 'Second line of text', 60, 720);
    pw.PdfAnnot(page, pw.PdfAnnotUrlLink(rect: linkRect, url: 'https://example.com/'));
    pw.PdfAnnot(page, pw.PdfAnnotNamedLink(rect: pageLinkRect, dest: 'first'));
  }
  return doc.save();
}

const linkRect = pw.PdfRect(55, 750, 200, 30);
const pageLinkRect = pw.PdfRect(55, 710, 250, 30);
const a4 = Size(595.28, 841.89);

/// Where PDF rectangle [r] of an A4 page turned by [turns] is shown.
Rect shown(pw.PdfRect r, int turns) => pdfRectToDisplay(
  r.left,
  r.bottom,
  r.right,
  r.top,
  width: a4.width,
  height: a4.height,
  quarterTurns: turns,
);

const directions = PdfTextDirection.values; // By quarter turns.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('page space', () {
    test('PDF rectangles map onto the turned page', () {
      // A box near the top-left corner of the unturned page.
      Rect at(int turns) =>
          pdfRectToDisplay(10, 80, 20, 90, width: 100, height: 100, quarterTurns: turns);
      expect(at(0), rectMoreOrLessEquals(const Rect.fromLTRB(0.1, 0.1, 0.2, 0.2)));
      expect(at(1), rectMoreOrLessEquals(const Rect.fromLTRB(0.8, 0.1, 0.9, 0.2))); // Top-right.
      expect(at(2), rectMoreOrLessEquals(const Rect.fromLTRB(0.8, 0.8, 0.9, 0.9))); // Bottom-right.
      expect(at(3), rectMoreOrLessEquals(const Rect.fromLTRB(0.1, 0.8, 0.2, 0.9))); // Bottom-left.
    });

    for (var turns = 0; turns < 4; turns++) {
      test('lines read along their direction at ${turns * 90}°', () {
        // "ab cd\nef": two lines, 0.1 wide per character, unturned.
        Rect box(double x, double y) => Rect.fromLTWH(x, y, 0.1, 0.05);
        final upright = [
          box(0.1, 0.1),
          box(0.2, 0.1),
          Rect.zero,
          box(0.4, 0.1),
          box(0.5, 0.1),
          Rect.zero,
          box(0.1, 0.2),
          box(0.2, 0.2),
        ];
        Rect turn(Rect r) => r.isEmpty
            ? r
            : Rect.fromPoints(
                rotateNormalized(r.topLeft, turns),
                rotateNormalized(r.bottomRight, turns),
              );
        final glyphs = PdfGlyphs('ab cd\nef', [for (final r in upright) turn(r)]);
        expect(glyphs.lines, hasLength(2));
        expect(glyphs.lines.map((l) => l.direction).toSet(), {directions[turns]});
        expect(glyphs.rectsFor(0, 8), [
          rectMoreOrLessEquals(turn(const Rect.fromLTRB(0.1, 0.1, 0.6, 0.15))),
          rectMoreOrLessEquals(turn(const Rect.fromLTRB(0.1, 0.2, 0.3, 0.25))),
        ]);
        // Hits: a character, just past the end of a line, another line.
        Offset p(double x, double y) => rotateNormalized(Offset(x, y), turns);
        expect(glyphs.indexAt(p(0.25, 0.12)), 1);
        expect(glyphs.indexAt(p(0.61, 0.12)), 4);
        expect(glyphs.indexAt(p(0.8, 0.12)), isNull);
        expect(glyphs.indexAt(p(0.25, 0.5)), isNull);
        expect(glyphs.nearestIndex(p(0.45, 0.9)), 7); // Below "ef": its nearest end.
        expect(glyphs.nearestIndex(p(0.45, 0.13)), 3);
        // Handles: the start of the first line (at the top of its letters).
        expect(glyphs.lines.first.startCorner, offsetMoreOrLessEquals(p(0.1, 0.1)));
        expect(glyphs.lines.last.endCorner, offsetMoreOrLessEquals(p(0.3, 0.25)));
        // Highlights run along the line in reading order.
        final line = glyphs.linesFor(0, 2).single;
        final points = PdfInteraction.highlightPoints(
          line.rect,
          const Size(1000, 1000),
          direction: line.direction,
        )!;
        expect(points.first.offset, offsetMoreOrLessEquals(p(0.1, 0.125) * 1000));
        expect(points.last.offset, offsetMoreOrLessEquals(p(0.3, 0.125) * 1000));
        expect(line.thickness, closeTo(0.05, 1e-9));
      });
    }
  });

  group('with PDFium', () {
    late Directory dir;
    late AppServices services;

    setUpAll(() {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
      Pdfrx.pdfiumModulePath = pdfium;
    });
    setUp(() {
      dir = Directory.systemTemp.createTempSync('len_pdf_rotation_');
      services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
    });
    tearDown(() {
      services.dispose();
      dir.deleteSync(recursive: true);
    });

    test('text and links of turned pages are where the page shows them', () async {
      final bytes = await rotatedPdf([0, 1, 2, 3]);
      final doc = await const PdfrxTextSource().open(bytes);
      final sha = await services.blobs.putBytes(bytes, mime: 'application/pdf');
      final renderer = PdfRenderer(services.blobs);
      for (var turns = 0; turns < 4; turns++) {
        final glyphs = (await doc.glyphs(turns))!;
        final i = glyphs.text.indexOf('Second');
        // "S" sits on the 720 pt baseline, 60 pt from the left edge.
        final s = glyphs.boxes[i];
        final expected = shown(const pw.PdfRect(60, 720, 16, 17), turns);
        expect((s.center - expected.center).distance, lessThan(0.02), reason: '$turns');
        expect(glyphs.lineOf(i)!.direction, directions[turns]);
        final selection = PdfSelection()..select(_page, glyphs, i, glyphs.text.indexOf('text') + 4);
        expect(selection.text, 'Second line of text');
        expect(selection.lines, hasLength(1));
        final line = selection.lines.single.rect;
        final band = shown(const pw.PdfRect(60, 715, 220, 24), turns);
        expect(band.overlaps(line) && band.inflate(0.02).contains(line.center), isTrue);
        selection.dispose();

        final links = await renderer.links(sha, turns);
        final web = links.firstWhere((l) => l.url != null);
        expect(web.url.toString(), 'https://example.com/');
        expect(web.rects.single, rectMoreOrLessEquals(shown(linkRect, turns), epsilon: 1e-3));
        final internal = links.firstWhere((l) => l.page != null);
        expect(internal.page, 0);
        expect(internal.contains(s.center), isTrue);
      }
      await doc.dispose();
      await renderer.dispose();
    });

    testWidgets('select and highlight a line on a page turned 90° (golden)', (tester) async {
      tester.view
        ..physicalSize = const Size(900, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final nb = await tester.runAsync(() async {
        final file = File('${dir.path}/turned.pdf')..writeAsBytesSync(await rotatedPdf([1]));
        final importer = PdfImporter(services);
        final notebook = await importer.createNotebook(
          await importer.store(XFile(file.path)),
          title: 'Turned',
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
      final pdf = tester.widget<PdfLayer>(find.byType(PdfLayer)).interaction;
      final page = pdf.doc.pages.first;
      final bg = page.background!;
      for (var i = 0; i < 60 && !pdf.info.isLoaded(bg.blob, 0); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      final glyphs = pdf.info.glyphs(bg.blob, 0)!;
      final frame = pdf.doc.layout.frameOf(0)!;
      Offset screenOf(Offset n) => pdf.doc.viewport.toScreen(
        frame.topLeft + Offset(n.dx * frame.width, n.dy * frame.height),
      );
      final start = glyphs.text.indexOf('Second'), end = glyphs.text.indexOf('text') + 3;
      // The line runs down the screen: long press its first word, then drag
      // the end handle to its last letter.
      final word = screenOf(glyphs.boxes[start].center);
      final to = screenOf(glyphs.boxes[end].center);
      expect(to.dy - word.dy, greaterThan(100));
      pdf.tools.stylusOnly = true; // Fingers navigate: a long press selects.
      await tester.longPressAt(word, kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      expect(pdf.selection.text, 'Second');
      final from = pdf.handleEnds!.$2;
      final gesture = await tester.startGesture(from, kind: PointerDeviceKind.touch);
      for (var t = 0.1; t <= 1.0; t += 0.1) {
        await gesture.moveTo(Offset.lerp(from, to, t)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(pdf.selection.text, 'Second line of text');
      final ends = pdf.handleEnds!;
      expect(ends.$1.dy, lessThan(ends.$2.dy)); // Start at the top, end at the bottom.
      expect(ends.$1.dx, greaterThan(ends.$2.dx)); // Letters' tops face right.
      await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/pdf_select_90.png'));

      await tester.tap(find.byKey(const ValueKey('pdf-highlight')));
      await tester.pumpAndSettle();
      final model = pdf.doc.surfaces.surfaceOf(page.id).model;
      final stroke = model.strokesNear(Offset.zero & page.size).single;
      expect(stroke.tool, InkTool.highlighter);
      // Down the page, about as wide as the letters are tall (24 pt → 32 units).
      expect(stroke.points.last.y - stroke.points.first.y, greaterThan(200));
      expect(stroke.points.first.x, closeTo(stroke.points.last.x, 0.01));
      expect(stroke.width, inInclusiveRange(18.0, 40.0));
      await tester.pumpWidget(const SizedBox());
    });
  }, skip: pdfium == null ? 'PDFium not built yet' : null);
}

const _page = NotebookPage(
  id: 'p',
  notebookId: 'n',
  sortKey: 1,
  width: 794,
  height: 1123,
  paper: Paper(PaperStyle.blank),
);
