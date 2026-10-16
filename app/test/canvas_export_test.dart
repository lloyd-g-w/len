import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/documents/export/export_flow.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/features/documents/export/pdf_export.dart';
import 'package:len/features/documents/export/print_flow.dart';
import 'package:len/platform/file_export.dart';
import 'package:len/platform/print_document.dart';

import 'content_tools_ui_test.dart' show openCanvas;
import 'support/real_async.dart';

/// A stroke on [surface] from [from] to [to] (world units).
Stroke line(String id, String surface, Offset from, Offset to) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF1F2937,
  width: 4,
  points: [
    for (var i = 0; i <= 10; i++)
      StrokePoint(from.dx + (to.dx - from.dx) * i / 10, from.dy + (to.dy - from.dy) * i / 10, 0.5),
  ],
  createdAt: 1,
);

Notebook board(AppServices s, {PaperStyle paper = PaperStyle.gridLarge}) =>
    s.notebooks.create(title: 'Board', kind: NotebookKind.canvas, paper: paper, coverColor: 0);

/// The PNG's size in pixels (its IHDR chunk).
(int, int) pngSize(Uint8List png) {
  final data = ByteData.sublistView(png);
  return (data.getUint32(16), data.getUint32(20));
}

Future<ui.Color> pixel(Uint8List png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  final c = ui.Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
  image.dispose();
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppServices services;
  late NotebookExporter exporter;

  setUp(() {
    services = AppServices.create(AppDatabase.inMemory());
    exporter = NotebookExporter(services);
  });
  tearDown(() async {
    await exporter.dispose();
    services.dispose();
  });

  test('a canvas exports as one page fitted to its drawing, wherever it is', () {
    final nb = board(services);
    expect(exporter.canvasPage(nb), isNull, reason: 'empty');
    services.strokes.save([
      line('a', nb.id, const Offset(-1037, 2213), const Offset(-637, 2213)),
      line('b', nb.id, const Offset(-837, 2013), const Offset(-837, 2513)),
    ]);
    final page = exporter.canvasPage(nb)!;
    const m = NotebookExporter.canvasMargin;
    final bounds = services.strokes.contentBounds(nb.id)!;
    expect(page.page.size, bounds.inflate(m).size);
    expect(page.worldOrigin, bounds.inflate(m).topLeft);
    // The drawing moved onto the page, keeping the margin.
    final moved = page.strokes.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b));
    expect(moved.left, closeTo(m, 1e-9));
    expect(moved.top, closeTo(m, 1e-9));
    expect(page.page.paper.style, PaperStyle.gridLarge);
    // Without the background: plain white paper.
    expect(exporter.canvasPage(nb, template: false)!.page.paper.style, PaperStyle.blank);
  });

  test('the PNG keeps the grid where the canvas draws it', () async {
    final nb = board(services);
    services.strokes.save([line('a', nb.id, const Offset(1013, 517), const Offset(1413, 517))]);
    final canvas = exporter.canvasPage(nb)!;
    final png = await exporter.canvasPng(canvas, scale: 1);
    expect(pngSize(png), (canvas.page.width.ceil(), canvas.page.height.ceil()));

    // A vertical grid line of the canvas (world x), seen in the export.
    final origin = canvas.worldOrigin!;
    final area = origin & canvas.page.size;
    final pattern = PaperPattern.of(nb.paper, area);
    // A vertical line, a few pixels in from the left edge.
    final lineX = pattern.lines
        .where((l) => l.a.dx == l.b.dx && l.a.dx > area.left + 4)
        .map((l) => l.a.dx)
        .reduce((a, b) => a < b ? a : b);
    final y = (canvas.page.height - 8).round(); // Below the ink.
    final onLine = await pixel(png, (lineX - origin.dx).round(), y);
    final paper = await pixel(png, (lineX - origin.dx).round() + 5, y);
    expect(onLine, isNot(paper), reason: 'a grid line where the canvas has one');
  });

  test('a scanned page under an image template exports with the template', () async {
    Uint8List solid(int r, int g, int b) {
      final image = img.Image(width: 8, height: 8)..clear(img.ColorRgb8(r, g, b));
      return img.encodePng(image);
    }

    final scan = await services.blobs.putBytes(solid(255, 0, 0), mime: 'image/png');
    final template = await services.blobs.putBytes(solid(0, 0, 255), mime: 'image/png');
    final nb = services.notebooks.create(
      title: 'Scans',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = services.pages.insertPages(nb.id, [
      (
        size: const Size(100, 140),
        paper: Paper.image(template),
        color: PaperColor.white,
        background: PageBackground.image(blob: scan),
      ),
    ]).single;
    final png = await exporter.png(page, scale: 1);
    expect(await pixel(png, 50, 70), const ui.Color(0xFF0000FF), reason: 'the template on top');
  });

  test('the PDF is one page the size of the drawing', () async {
    final nb = board(services, paper: PaperStyle.dotted);
    services.strokes.save([line('a', nb.id, const Offset(-300, -100), const Offset(300, 200))]);
    final canvas = exporter.canvasPage(nb)!;
    final pdf = await exporter.canvasPdf(canvas, title: nb.title);
    final text = latin1.decode(pdf);
    expect(text, startsWith('%PDF'));
    expect(RegExp('/Type\\s*/Page\\b').allMatches(text), hasLength(1));
    final k = PdfExporter.pointsPerUnit;
    final box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]').firstMatch(text)!;
    expect(double.parse(box[1]!), closeTo(canvas.page.width * k, 0.01));
    expect(double.parse(box[2]!), closeTo(canvas.page.height * k, 0.01));
  });

  test('a huge drawing is exported smaller rather than as an unopenable PNG', () async {
    final nb = board(services, paper: PaperStyle.blank);
    services.strokes.save([line('a', nb.id, Offset.zero, const Offset(20000, 3000))]);
    final png = await exporter.canvasPng(exporter.canvasPage(nb)!, scale: 3);
    final (w, h) = pngSize(png);
    expect(w, lessThanOrEqualTo(NotebookExporter.maxCanvasPixels));
    expect(w, greaterThan(NotebookExporter.maxCanvasPixels - 2));
    expect(h, lessThan(w));
  });

  testWidgets('⋯ → Export… on a canvas exports its whole drawing', (tester) async {
    final saved = <(List<String>, String)>[];
    final (_, nb) = await openCanvas(
      tester,
      seed: (s, nb) =>
          s.strokes.save([line('a', nb.id, const Offset(100, 100), const Offset(400, 300))]),
    );
    // The menu entry runs the real flow; swap in a recording saver.
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Export…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final done = exportCanvasFlow(
      context,
      notebook: nb,
      save: (files, {required mime, toDevice = false, subject}) async {
        saved.add(([for (final f in files) f.name], mime));
        return ExportedFiles(ExportedTo.downloaded, count: 1, name: files.single.name);
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Whole canvas, PDF'), findsOneWidget);
    expect(find.text('Pages'), findsNothing, reason: 'no page choice');
    expect(find.text('Background'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-button')));
    await pumpUntil(tester, () => saved.isNotEmpty, reason: 'the export');
    await tester.pumpAndSettle();
    await done;
    expect(saved.single.$1, ['Board.pdf']);
    expect(saved.single.$2, 'application/pdf');
    expect(find.text('Downloaded “Board.pdf”'), findsOneWidget);
  });

  testWidgets('⋯ → Print… on a canvas prints its whole drawing (R22-8)', (tester) async {
    final printed = <(String, int)>[];
    final (_, nb) = await openCanvas(
      tester,
      seed: (s, nb) =>
          s.strokes.save([line('a', nb.id, const Offset(100, 100), const Offset(400, 300))]),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Print…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    final done = printCanvasFlow(
      context,
      notebook: nb,
      printer: (bytes, {required name, required pages}) async {
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        printed.add((name, pages));
        return PrintHandoff.viewer;
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Whole canvas'), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('print-button')));
    await pumpUntil(tester, () => printed.isNotEmpty, reason: 'the print');
    await tester.pumpAndSettle();
    await done;
    expect(printed.single, ('Board.pdf', 1));
    expect(find.text('Opened “Board.pdf” in your PDF viewer to print'), findsOneWidget);
  });

  testWidgets('an empty canvas says there is nothing to export', (tester) async {
    final (_, nb) = await openCanvas(tester);
    final context = tester.element(find.byType(Scaffold).first);
    await exportCanvasFlow(
      context,
      notebook: nb,
      save: (_, {required mime, toDevice = false, subject}) async => fail('saved'),
    );
    await tester.pump();
    expect(find.text('Nothing to export yet: the canvas is empty'), findsOneWidget);
  });
}
