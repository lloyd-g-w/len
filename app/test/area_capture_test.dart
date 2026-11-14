import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/capture/area_capturer.dart';
import 'package:len/features/editor/capture/area_image.dart';
import 'package:len/features/editor/document/document_layout.dart';

import 'canvas_export_test.dart' show board, line, pixel, pngSize;

const _red = 0xFFE03131;

/// A thick red stroke on [surface] from [from] to [to].
Stroke _redLine(String id, String surface, Offset from, Offset to) {
  final plain = line(id, surface, from, to);
  return Stroke(
    id: id,
    surfaceId: surface,
    tool: plain.tool,
    color: _red,
    width: 8,
    points: plain.points,
    createdAt: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppServices services;
  late AreaCapturer capturer;

  setUp(() {
    services = AppServices.create(AppDatabase.inMemory());
    capturer = AreaCapturer(services);
  });
  tearDown(() => services.dispose());

  /// A paged notebook of [count] 300 × 400 pages of [paper].
  (Notebook, List<NotebookPage>, DocumentLayout) paged(
    int count, {
    PaperStyle paper = PaperStyle.gridLarge,
    PageBackground? background,
  }) {
    final nb = services.notebooks.create(
      title: 'Pages',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    for (final p in services.pages.pagesOf(nb.id)) {
      services.pages.delete(p.id);
    }
    final pages = services.pages.insertPages(nb.id, [
      for (var i = 0; i < count; i++)
        (
          size: const Size(300, 400),
          paper: Paper(paper),
          color: PaperColor.white,
          background: background,
        ),
    ]);
    final layout = DocumentLayout.continuous([for (final p in pages) p.size]);
    return (nb, pages, layout);
  }

  bool near(ui.Color c, int argb, {int tolerance = 40}) {
    final want = ui.Color(argb);
    return ((c.r - want.r) * 255).abs() < tolerance &&
        ((c.g - want.g) * 255).abs() < tolerance &&
        ((c.b - want.b) * 255).abs() < tolerance;
  }

  test('the scale follows the screen, at least 288 dpi, and keeps the image in bounds', () {
    expect(AreaImage.scaleFor(const Size(200, 100)), AreaImage.baseScale);
    expect(AreaImage.scaleFor(const Size(200, 100), screenScale: 5), 5);
    expect(AreaImage.scaleFor(const Size(200, 100), screenScale: 50), AreaImage.maxScale);
    final big = AreaImage.scaleFor(const Size(4000, 1000), screenScale: 2);
    expect(4000 * big, closeTo(AreaImage.maxPixels, 1e-6));
  });

  test('a page area shows its paper, template and ink where they are', () async {
    final (_, pages, layout) = paged(1);
    final page = pages.single;
    services.strokes.save([
      _redLine('ink', page.id, const Offset(100, 200), const Offset(300, 200)),
    ]);
    const area = Rect.fromLTRB(80, 150, 280, 260);
    final shot = (await capturer.pages(area, pages: pages, layout: layout))!;
    const s = AreaImage.baseScale;
    expect((shot.width, shot.height), ((200 * s).round(), (110 * s).round()));
    expect(pngSize(shot.png), (shot.width, shot.height));
    expect(shot.area, area);

    final ink = await pixel(shot.png, ((150 - 80) * s).round(), ((200 - 150) * s).round());
    expect(near(ink, _red), isTrue, reason: 'the ink, got $ink');
    // A vertical grid line of the page, and the paper beside it.
    final pattern = PaperPattern.of(page.paper, page.bounds, page: page.bounds);
    final lineX = pattern.lines
        .where((l) => l.a.dx == l.b.dx && l.a.dx > area.left + 4 && l.a.dx < area.right - 8)
        .first
        .a
        .dx;
    final y = ((240 - 150) * s).round();
    final onLine = await pixel(shot.png, ((lineX - 80) * s).round(), y);
    final paper = await pixel(shot.png, ((lineX - 80) * s).round() + 8, y);
    expect(paper, PaperColor.white.paper);
    expect(onLine, isNot(paper), reason: 'the template is drawn');
    expect(onLine.a, 1);
  });

  test('an area across pages shows both, the desk between them transparent and trimmed', () async {
    final (_, pages, layout) = paged(2, paper: PaperStyle.blank);
    final second = layout.frameOf(1)!;
    services.strokes.save([
      _redLine('ink', pages[1].id, const Offset(100, 40), const Offset(200, 40)),
    ]);
    final area = Rect.fromLTRB(-50, 350, 350, second.top + 60);
    final shot = (await capturer.pages(area, pages: pages, layout: layout))!;
    expect(shot.area, Rect.fromLTRB(0, 350, 300, second.top + 60), reason: 'no desk aside');
    const s = AreaImage.baseScale;
    int y(double doc) => ((doc - 350) * s).round();
    expect(await pixel(shot.png, 30, y(380)), PaperColor.white.paper, reason: 'page 1');
    final gap = await pixel(shot.png, 30, y(400 + DocumentLayout.defaultGap / 2));
    expect(gap.a, 0, reason: 'the desk is not captured');
    expect(await pixel(shot.png, 30, y(second.top + 20)), PaperColor.white.paper);
    final ink = await pixel(shot.png, (150 * s).round(), y(second.top + 40));
    expect(near(ink, _red), isTrue, reason: 'ink on page 2, got $ink');
    // Wholly in the desk: nothing to capture.
    final desk = Rect.fromLTWH(0, 401, 300, DocumentLayout.defaultGap - 2);
    expect(await capturer.pages(desk, pages: pages, layout: layout), isNull);
  });

  test('a scanned page captures its scan', () async {
    final scan = await services.blobs.putBytes(
      img.encodePng(img.Image(width: 8, height: 8)..clear(img.ColorRgb8(0, 160, 0))),
      mime: 'image/png',
    );
    final (_, pages, layout) = paged(
      1,
      paper: PaperStyle.blank,
      background: PageBackground.image(blob: scan),
    );
    final shot = (await capturer.pages(
      const Rect.fromLTWH(20, 20, 100, 100),
      pages: pages,
      layout: layout,
    ))!;
    expect(near(await pixel(shot.png, 150, 150), 0xFF00A000, tolerance: 8), isTrue);
  });

  test('a canvas area keeps the grid where the canvas draws it, ink included', () async {
    final nb = board(services);
    services.strokes.save([
      _redLine('ink', nb.id, const Offset(-900, -300), const Offset(-600, -300)),
    ]);
    const area = Rect.fromLTRB(-1000, -400, -500, -200);
    final shot = (await capturer.canvas(area, notebook: nb, screenScale: 1))!;
    const s = AreaImage.baseScale;
    expect((shot.width, shot.height), ((500 * s).round(), (200 * s).round()));
    final ink = await pixel(shot.png, (150 * s).round(), (100 * s).round());
    expect(near(ink, _red), isTrue, reason: 'the ink, got $ink');
    final pattern = PaperPattern.of(nb.paper, area);
    final lineX = pattern.lines
        .where((l) => l.a.dx == l.b.dx && l.a.dx > area.left + 4)
        .map((l) => l.a.dx)
        .reduce((a, b) => a < b ? a : b);
    final y = (180 * s).round();
    final onLine = await pixel(shot.png, ((lineX - area.left) * s).round(), y);
    final paper = await pixel(shot.png, ((lineX - area.left) * s).round() + 8, y);
    expect(onLine, isNot(paper), reason: 'a grid line where the canvas has one');
  });
}
