import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/outline/outline_panel.dart';
import 'package:len/features/editor/pdf/pdf_interaction.dart';
import 'package:len/features/editor/pdf/pdf_layer.dart';
import 'package:len/features/editor/pdf/pdf_page_info.dart';
import 'package:len/features/editor/pdf/pdf_text_selection.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:len/ui/app_theme.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

import 'pdf_test.dart' show pdfium;
import 'support/real_async.dart';

/// Two A4 pages: text, a web link and a link to page 2 on the first, a
/// heading on the second; an outline with a nested entry.
Future<List<int>> interactivePdf() {
  final doc = pw.PdfDocument();
  final font = pw.PdfFont.helvetica(doc);
  final one = pw.PdfPage(doc, pageFormat: pw.PdfPageFormat.a4);
  final two = pw.PdfPage(doc, pageFormat: pw.PdfPageFormat.a4);
  one.getGraphics()
    ..setFillColor(pw.PdfColors.black)
    ..drawString(font, 24, 'Hello PDF world', 60, 760)
    ..drawString(font, 24, 'Second line of text', 60, 720)
    ..drawString(font, 24, 'Visit example', 60, 600)
    ..drawString(font, 24, 'Go to page two', 60, 520);
  two.getGraphics().drawString(font, 24, 'Chapter two', 60, 760);
  pw.PdfAnnot(
    one,
    pw.PdfAnnotUrlLink(rect: const pw.PdfRect(55, 590, 200, 30), url: 'https://example.com/'),
  );
  doc.pdfNames.addDest('two', two);
  pw.PdfAnnot(one, pw.PdfAnnotNamedLink(rect: const pw.PdfRect(55, 510, 200, 30), dest: 'two'));
  final intro = pw.PdfOutline(doc, title: 'Introduction', dest: one);
  doc.outline.add(intro);
  intro.add(pw.PdfOutline(doc, title: 'Details', dest: one));
  doc.outline.add(pw.PdfOutline(doc, title: 'Chapter two', dest: two));
  return doc.save();
}

/// Opens [interactivePdf] imported into [services] (files in [dir]) in an
/// editor of [size]; text copied to the clipboard goes to [copied].
Future<PdfInteraction> openPdfEditor(
  WidgetTester tester,
  AppServices services,
  Directory dir, {
  Size size = const Size(900, 1200),
  List<String>? copied,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
    call,
  ) async {
    if (call.method == 'Clipboard.setData') {
      copied?.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  final nb = await tester.runAsync(() async {
    final file = File('${dir.path}/doc.pdf')..writeAsBytesSync(await interactivePdf());
    final importer = PdfImporter(services);
    final notebook = await importer.createNotebook(
      await importer.store(XFile(file.path)),
      title: 'PDF',
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
  final bg = pdf.doc.pages.first.background!;
  // PDFium works on its own thread, in real time.
  await pumpUntil(tester, () => pdf.info.glyphs(bg.blob, 0) != null, reason: 'glyphs');
  await pumpUntilPdfRendered(tester);
  return pdf;
}

/// The screen position of character [i] of [text] on page 1 (its middle,
/// or its [right] edge).
Offset pdfTextAt(PdfInteraction pdf, String text, {int i = 0, bool right = false}) {
  final page = pdf.doc.pages.first;
  final glyphs = pdf.info.glyphs(page.background!.blob, 0)!;
  final box = glyphs.boxes[glyphs.text.indexOf(text) + i];
  final frame = pdf.doc.layout.frameOf(0)!;
  final n = right ? Offset(box.right - 0.001, box.center.dy) : box.center;
  return pdf.doc.viewport.toScreen(frame.topLeft + Offset(n.dx * frame.width, n.dy * frame.height));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('glyph hits', () {
    // "ab cd" on one line, 0.1 wide per character, space without a box.
    final glyphs = PdfGlyphs('ab cd', [
      const Rect.fromLTRB(0.1, 0.1, 0.2, 0.15),
      const Rect.fromLTRB(0.2, 0.1, 0.3, 0.15),
      Rect.zero,
      const Rect.fromLTRB(0.4, 0.1, 0.5, 0.15),
      const Rect.fromLTRB(0.5, 0.1, 0.6, 0.15),
    ]);

    test('the character under a point, or near it on the same line', () {
      expect(glyphs.indexAt(const Offset(0.25, 0.12)), 1);
      expect(glyphs.indexAt(const Offset(0.61, 0.12)), 4); // Just past the end.
      expect(glyphs.indexAt(const Offset(0.8, 0.12)), isNull); // Too far.
      expect(glyphs.indexAt(const Offset(0.25, 0.5)), isNull); // Another line.
      expect(glyphs.nearestIndex(const Offset(0.45, 0.9)), 3);
    });

    test('words', () {
      expect(glyphs.wordAt(1), (0, 2));
      expect(glyphs.wordAt(4), (3, 5));
      expect(glyphs.wordAt(2), (2, 3)); // The space alone.
    });

    test('a selection reports its text and one box per line', () {
      final selection = PdfSelection();
      expect(selection.isEmpty, isTrue);
      expect(selection.text, '');
      selection.dispose();
      expect(glyphs.rectsFor(0, 5), [const Rect.fromLTRB(0.1, 0.1, 0.6, 0.15)]);
    });

    test('highlight strokes run along the middle of a line, end to end', () {
      final points = PdfInteraction.highlightPoints(
        const Rect.fromLTRB(0.1, 0.1, 0.6, 0.15),
        const Size(800, 1000),
      )!;
      expect(points.first.offset, const Offset(80, 125));
      expect(points.last.offset, const Offset(480, 125));
      expect(points.length, greaterThan(100)); // One point every 2 units.
      expect(PdfInteraction.highlightPoints(Rect.zero, const Size(800, 1000)), isNull);
    });
  });

  group('in the editor', () {
    late Directory dir;
    late AppServices services;
    final copied = <String>[];

    setUpAll(() {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
      Pdfrx.pdfiumModulePath = pdfium;
    });
    setUp(() {
      dir = Directory.systemTemp.createTempSync('len_pdf_interaction_');
      services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
      copied.clear();
    });
    tearDown(() {
      services.dispose();
      dir.deleteSync(recursive: true);
    });

    Future<PdfInteraction> open(WidgetTester tester, {Size size = const Size(900, 1200)}) =>
        openPdfEditor(tester, services, dir, size: size, copied: copied);

    Offset at(PdfInteraction pdf, String text, {int i = 0, bool right = false}) =>
        pdfTextAt(pdf, text, i: i, right: right);

    testWidgets('right click / long press selects a word; copy', skip: pdfium == null, (
      tester,
    ) async {
      final pdf = await open(tester);
      await tester.tapAt(
        at(pdf, 'Hello', i: 1),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(pdf.selection.text, 'Hello');
      expect(find.text('Paste here'), findsNothing); // Not the canvas menu.
      await tester.tap(find.byKey(const ValueKey('pdf-copy')));
      await tester.pumpAndSettle();
      expect(copied, ['Hello']);
      expect(pdf.selection.isEmpty, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('long press a word, drag its end handle, highlight', skip: pdfium == null, (
      tester,
    ) async {
      final pdf = await open(tester);
      pdf.tools.stylusOnly = true; // Fingers navigate: a long press selects.
      await tester.longPressAt(at(pdf, 'Second'), kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      expect(pdf.selection.text, 'Second');
      final from = pdf.handleEnds!.$2, to = at(pdf, 'text', i: 3, right: true);
      final gesture = await tester.startGesture(from, kind: PointerDeviceKind.touch);
      for (var t = 0.1; t <= 1.0; t += 0.1) {
        await gesture.moveTo(Offset.lerp(from, to, t)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(pdf.selection.text, 'Second line of text');
      await tester.tap(find.byKey(const ValueKey('pdf-highlight')));
      await tester.pumpAndSettle();
      final page = pdf.doc.pages.first;
      final model = pdf.doc.surfaces.surfaceOf(page.id).model;
      final strokes = model.strokesNear(Offset.zero & page.size).toList();
      expect(strokes, hasLength(1));
      expect(strokes.single.tool, InkTool.highlighter);
      // Over the line: 720 pt baseline → about 120 pt from the top (160 units).
      expect(strokes.single.bounds.center.dy, closeTo((842 - 728) * 4 / 3, 12));
      expect(pdf.selection.isEmpty, isTrue);
      await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/pdf_highlight.png'));
      // One undo removes it.
      pdf.doc.surfaces.undo();
      expect(model.strokesNear(Offset.zero & page.size), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a selection runs across pages: copy and highlight both', skip: pdfium == null, (
      tester,
    ) async {
      final pdf = await open(tester, size: const Size(900, 2000));
      pdf.tools.stylusOnly = true; // Fingers navigate: a long press selects.
      // The end of page 1 and the top of page 2 on screen.
      final view = pdf.doc.viewport;
      view.panBy(Offset(0, -view.toScreen(const Offset(0, 40)).dy));
      await tester.pump();
      final second = pdf.doc.pages[1];
      await pumpUntil(
        tester,
        () => pdf.info.glyphs(second.background!.blob, 1) != null,
        reason: 'glyphs of page 2',
      );
      await pumpUntilPdfRendered(tester);
      await tester.pumpAndSettle();
      Offset onPage(int index, String text, {bool right = false}) {
        final page = pdf.doc.pages[index];
        final glyphs = pdf.info.glyphs(page.background!.blob, index)!;
        final box = glyphs.boxes[glyphs.text.indexOf(text) + (right ? text.length - 1 : 0)];
        final frame = pdf.doc.layout.frameOf(index)!;
        final n = box.center; // The middle of the first (or, [right], last) letter.
        return pdf.doc.viewport.toScreen(
          frame.topLeft + Offset(n.dx * frame.width, n.dy * frame.height),
        );
      }

      await tester.longPressAt(onPage(0, 'Second'), kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      expect(pdf.selection.text, 'Second');
      // Drag the end handle down onto the second page's heading.
      final from = pdf.handleEnds!.$2, to = onPage(1, 'Chapter', right: true);
      final gesture = await tester.startGesture(from, kind: PointerDeviceKind.touch);
      for (var t = 0.05; t <= 1.0; t += 0.05) {
        await gesture.moveTo(Offset.lerp(from, to, t)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(pdf.selection.spansPages, isTrue);
      expect(pdf.selection.spans.map((s) => s.page.id), [for (final p in pdf.doc.pages) p.id]);
      final text = pdf.selection.text;
      expect(text, startsWith('Second line of text'));
      expect(text, contains('Go to page two\n\nChapter'), reason: 'pages joined by a blank line');
      expect(text, endsWith('Chapter'));
      // The start handle stays on page 1, the end on page 2.
      final ends = pdf.handleEnds!;
      expect(ends.$1.dy, lessThan(tester.getCenter(find.byType(EditorScreen)).dy));
      expect(ends.$2.dy, closeTo(onPage(1, 'Chapter').dy, 30));

      await tester.tap(find.byKey(const ValueKey('pdf-copy')));
      await tester.pumpAndSettle();
      expect(copied, [text]);

      pdf.selectRange(
        pdf.textPointAt(onPage(0, 'Second'))!,
        pdf.textPointAt(onPage(1, 'Chapter', right: true))!,
        menu: true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-highlight')));
      await tester.pumpAndSettle();
      for (final page in pdf.doc.pages) {
        final strokes = pdf.doc.surfaces
            .surfaceOf(page.id)
            .model
            .strokesNear(Offset.zero & page.size);
        expect(strokes, isNotEmpty, reason: 'highlighted on ${page.id}');
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'links: a finger tap jumps to the page or asks before the web',
      skip: pdfium == null,
      (tester) async {
        final pdf = await open(tester);
        pdf.tools.stylusOnly = true; // Fingers navigate.
        await tester.tapAt(at(pdf, 'Visit'), kind: PointerDeviceKind.touch);
        await tester.pumpAndSettle();
        expect(find.text('Open link?'), findsOneWidget);
        expect(find.text('https://example.com/'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.tapAt(at(pdf, 'Go to'), kind: PointerDeviceKind.touch);
        await tester.pumpAndSettle();
        expect(pdf.doc.currentPage, 1);
        // A right click selects the link's text; its menu opens the link.
        pdf.doc.scrollToPage(0);
        await tester.pumpAndSettle();
        await tester.tapAt(
          at(pdf, 'Visit'),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pdf-open-link')));
        await tester.pumpAndSettle();
        expect(find.text('Open link?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(pdf.selection.isEmpty, isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('the outline lists entries and goes to their pages', skip: pdfium == null, (
      tester,
    ) async {
      final pdf = await open(tester);
      await tester.tap(find.byTooltip('All pages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outline'));
      await pumpUntil(
        tester,
        () => find.text('Introduction').evaluate().isNotEmpty,
        reason: 'the outline',
      );
      await tester.pumpAndSettle();
      expect(find.text('Introduction'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      await expectLater(find.byType(OutlinePanel), matchesGoldenFile('goldens/pdf_outline.png'));
      await tester.tap(find.byTooltip('Collapse'));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsNothing);
      await tester.tap(find.text('Chapter two'));
      await tester.pumpAndSettle();
      expect(pdf.doc.currentPage, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }, skip: pdfium == null ? 'PDFium not built yet' : null);
}
