import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/pdf_text_source.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/pdf/pdf_highlight_snap.dart';
import 'package:len/features/editor/pdf/pdf_interaction.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

import 'pdf_interaction_test.dart' show openPdfEditor, pdfTextAt;
import 'pdf_rotation_test.dart' show a4, rotatedPdf;
import 'pdf_test.dart' show pdfium;

/// The text-aware highlighter: highlighter strokes along PDF text become
/// clean highlights over the words they cover.
void main() {
  group('snapping', () {
    const page = NotebookPage(
      id: 'p',
      notebookId: 'n',
      sortKey: 1,
      width: 1000,
      height: 1000,
      paper: Paper(PaperStyle.blank),
    );
    // Two lines, 20 units wide per character and 20 high, from x = 100.
    const first = 'Hello world again', second = 'Second line here';
    List<Rect> boxes(String line, double top) => [
      for (var i = 0; i < line.length; i++)
        line[i] == ' ' ? Rect.zero : Rect.fromLTWH(0.1 + 0.02 * i, top, 0.02, 0.02),
    ];
    final glyphs = PdfGlyphs('$first\n$second', [
      ...boxes(first, 0.1),
      Rect.zero,
      ...boxes(second, 0.13),
    ]);
    var ids = 0;

    Stroke highlight(List<Offset> points, {double width = 16}) => Stroke(
      id: 'h',
      surfaceId: 'p',
      tool: InkTool.highlighter,
      color: 0xFFFFEB3B,
      width: width,
      points: [for (final p in points) StrokePoint(p.dx, p.dy, 0.5)],
      createdAt: 7,
    );

    /// Points every 4 units from [a] to [b], wobbling by [wobble].
    List<Offset> line(Offset a, Offset b, {double wobble = 0}) {
      final n = ((b - a).distance / 4).ceil();
      return [
        for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)! + Offset(0, i.isEven ? wobble : 0),
      ];
    }

    List<Stroke>? snap(List<Offset> points) =>
        PdfHighlightSnap.snapTo(highlight(points), page, glyphs, newId: () => 'n${ids++}');

    test('a wobbly stroke along a line covers the words it mostly covers', () {
      // From the middle of "Hello"'s e to "world"'s l, then a little of "again".
      final strokes = snap(line(const Offset(130, 108), const Offset(370, 113), wobble: 3))!;
      final s = strokes.single;
      expect(s.points.first.x, closeTo(100, 1e-6));
      expect(s.points.last.x, closeTo(320, 1e-6), reason: '"Hello world", not "ag"');
      expect(s.points.every((p) => (p.y - 110).abs() < 1e-6), isTrue, reason: 'straight');
      expect(s.width, closeTo(22, 1e-9), reason: 'the line, a little taller');
      expect(s.color, 0xFFFFEB3B);
      expect(s.createdAt, 7);
      expect(s.style.thinning, 0);
    });

    test('back and forth over two lines highlights both', () {
      final strokes = snap([
        ...line(const Offset(100, 110), const Offset(440, 110)),
        ...line(const Offset(440, 140), const Offset(100, 140)),
      ])!;
      expect(strokes, hasLength(2));
      expect(strokes.map((s) => s.points.first.y.round()), [110, 140]);
    });

    test('anything else stays as drawn', () {
      expect(snap(line(const Offset(200, 50), const Offset(200, 400))), isNull, reason: 'across');
      expect(snap(line(const Offset(100, 500), const Offset(400, 500))), isNull, reason: 'margin');
      expect(
        snap([
          ...line(const Offset(100, 90), const Offset(200, 90)),
          ...line(const Offset(200, 90), const Offset(200, 130)),
          ...line(const Offset(200, 130), const Offset(100, 130)),
          ...line(const Offset(100, 130), const Offset(100, 90)),
        ]),
        isNull,
        reason: 'a box around a word',
      );
      expect(snap(line(const Offset(100, 110), const Offset(125, 110))), isNull, reason: 'a dab');
    });

    test('an underline just below the letters stays as drawn (R8-30)', () {
      // The first line runs from y = 100 to 120; letters end at 120.
      expect(snap(line(const Offset(100, 124), const Offset(360, 124))), isNull);
      expect(snap(line(const Offset(100, 122), const Offset(360, 123), wobble: 2)), isNull);
      // Slightly off the middle, or wide enough to cover it, it snaps.
      expect(snap(line(const Offset(100, 115), const Offset(360, 116))), hasLength(1));
      expect(
        PdfHighlightSnap.snapTo(
          highlight(line(const Offset(100, 123), const Offset(360, 123)), width: 30),
          page,
          glyphs,
          newId: () => 'n${ids++}',
        ),
        hasLength(1),
        reason: 'a wide stroke still covers the middle',
      );
    });
  });

  group('on turned pages (R8-30)', () {
    setUpAll(() {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
      Pdfrx.pdfiumModulePath = pdfium;
    });

    test(
      'a stroke along a line snaps to it at 0°, 90°, 180° and 270°',
      skip: pdfium == null,
      () async {
        final source = await const PdfrxTextSource().open(await rotatedPdf([0, 1, 2, 3]));
        addTearDown(source.dispose);
        for (var turns = 0; turns < 4; turns++) {
          final glyphs = (await source.glyphs(turns))!;
          final size = turns.isOdd ? Size(a4.height, a4.width) : a4;
          final page = NotebookPage(
            id: 'p',
            notebookId: 'n',
            sortKey: 1,
            width: size.width,
            height: size.height,
            paper: const Paper(PaperStyle.blank),
          );
          Offset at(int i) => Offset(
            glyphs.boxes[i].center.dx * size.width,
            glyphs.boxes[i].center.dy * size.height,
          );
          final s = glyphs.text.indexOf('Second'), e = glyphs.text.indexOf('text') + 3;
          final from = at(s), to = at(e);
          final n = ((to - from).distance / 3).ceil();
          // Along the line, wobbling a little across it.
          final across = Offset(-(to - from).dy, (to - from).dx) / (to - from).distance;
          final points = [
            for (var i = 0; i <= n; i++)
              Offset.lerp(from, to, i / n)! + across * (i.isEven ? 1.5 : -1.5),
          ];
          Stroke stroke(List<Offset> points) => Stroke(
            id: 'h',
            surfaceId: 'p',
            tool: InkTool.highlighter,
            color: 0xFFFFEB3B,
            width: 12,
            points: [for (final p in points) StrokePoint(p.dx, p.dy, 0.5)],
            createdAt: 0,
          );
          var ids = 0;
          final snapped = PdfHighlightSnap.snapTo(
            stroke(points),
            page,
            glyphs,
            newId: () => 'n${ids++}',
          );
          expect(snapped, hasLength(1), reason: '$turns');
          final line = snapped!.single;
          final vertical = turns.isOdd;
          final across0 = line.points.map((p) => vertical ? p.x : p.y);
          expect(
            across0.reduce(math.max) - across0.reduce(math.min),
            lessThan(1e-6),
            reason: 'straight at $turns',
          );
          // It covers the line from "Second" to "text".
          final along = line.points.map((p) => vertical ? p.y : p.x).toList();
          final lo = along.reduce(math.min), hi = along.reduce(math.max);
          for (final i in [s, e]) {
            final a = vertical ? at(i).dy : at(i).dx;
            expect(a, inInclusiveRange(lo, hi), reason: '$turns: character $i');
          }
          // Across the line, it stays as drawn.
          final mid = Offset.lerp(from, to, 0.5)!;
          expect(
            PdfHighlightSnap.snapTo(
              stroke([for (var k = -20; k <= 20; k++) mid + across * (k * 4.0)]),
              page,
              glyphs,
              newId: () => 'x',
            ),
            isNull,
            reason: '$turns: across',
          );
        }
      },
    );
  });

  group('in the editor', () {
    late Directory dir;
    late AppServices services;

    setUpAll(() {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
      Pdfrx.pdfiumModulePath = pdfium;
    });
    setUp(() {
      dir = Directory.systemTemp.createTempSync('len_pdf_snap_');
      services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
    });
    tearDown(() {
      services.dispose();
      dir.deleteSync(recursive: true);
    });

    Future<List<Stroke>> highlightAcross(WidgetTester tester, PdfInteraction pdf) async {
      final from = pdfTextAt(pdf, 'Hello', i: 1), to = pdfTextAt(pdf, 'world', i: 3);
      final pen = await tester.startGesture(from, kind: PointerDeviceKind.stylus);
      for (var t = 0.05; t <= 1.0001; t += 0.05) {
        await pen.moveTo(Offset.lerp(from, to, t)! + Offset(0, t * 10 % 2 < 1 ? 2 : -2));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await pen.up();
      await tester.pumpAndSettle();
      final page = pdf.doc.pages.first;
      return pdf.doc.surfaces
          .surfaceOf(page.id)
          .model
          .strokesNear(Offset.zero & page.size)
          .toList();
    }

    testWidgets('a highlight along PDF text snaps to it, one undo step', skip: pdfium == null, (
      tester,
    ) async {
      final pdf = await openPdfEditor(tester, services, dir);
      pdf.tools
        ..stylusOnly = true
        ..tool = EditorTool.highlighter;
      await tester.pumpAndSettle();
      final s = (await highlightAcross(tester, pdf)).single;
      final ys = s.points.map((p) => p.y);
      expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(1e-6), reason: 'straight');
      // From the start of "Hello" to the end of "world" (not "PDF" alone).
      final page = pdf.doc.pages.first;
      final glyphs = pdf.info.glyphs(page.background!.blob, 0)!;
      final h = glyphs.text.indexOf('Hello'), d = glyphs.text.indexOf('world') + 4;
      expect(s.points.first.x, closeTo(glyphs.boxes[h].left * page.width, 0.5));
      expect(s.points.last.x, closeTo(glyphs.boxes[d].right * page.width, 0.5));
      pdf.doc.surfaces.undo();
      await tester.pumpAndSettle();
      expect(
        pdf.doc.surfaces.surfaceOf(page.id).model.strokesNear(Offset.zero & page.size),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with hold to snap off it snaps all the same', skip: pdfium == null, (
      tester,
    ) async {
      final pdf = await openPdfEditor(tester, services, dir);
      pdf.tools
        ..stylusOnly = true
        ..holdToStraighten = false
        ..tool = EditorTool.highlighter;
      await tester.pumpAndSettle();
      final s = (await highlightAcross(tester, pdf)).single;
      final ys = s.points.map((p) => p.y);
      expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(1e-6), reason: 'straight');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
