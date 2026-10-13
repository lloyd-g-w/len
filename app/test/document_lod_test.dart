import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/document_layout.dart';
import 'package:len/features/editor/document/document_painters.dart';
import 'package:len/features/editor/document/document_surfaces.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

import 'support/canvas_fixtures.dart';
import 'support/ink_scene.dart';

/// Paged documents zoomed out far draw each page from level-of-detail
/// chunk rasters; edits, undo and sync must never show stale ink.
void main() {
  const view = Size(400, 300);

  Stroke line(String id, Offset from, {String page = 'p0'}) => Stroke(
    id: id,
    surfaceId: page,
    tool: InkTool.ballpoint,
    color: 0xFF1B1F3B,
    width: 40,
    points: [for (var i = 0; i < 10; i++) StrokePoint(from.dx + i * 20, from.dy, .6)],
    createdAt: id.hashCode & 0xFFFFFF,
  );

  testWidgets('pages zoomed out far are drawn from rasters, current after edits, undo and sync', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final doc = _Doc(view, scale: 0.1)
        ..save([
          line('a', const Offset(100, 200)),
          line('c', const Offset(100, 400)),
          line('b', const Offset(600, 700)),
        ]);
      await doc.rest();
      // Where stroke a is (chunk (0, 0) of page 0, with c).
      final chunkA = doc.screenRectOf(0, const Rect.fromLTRB(60, 160, 340, 240));
      final chunkC = doc.screenRectOf(0, const Rect.fromLTRB(60, 360, 340, 440));
      expect(await doc.inkIn(chunkA), greaterThan(0));
      final settled = CountingCanvas();
      doc.painter().paint(settled, view);
      expect(settled.pictures, 0, reason: 'images only');
      expect(settled.images, greaterThan(0));

      // Erase a: gone in the very next frame (its chunk from vectors).
      final page = doc.surfaces.peek('p0')!;
      final a = page.model.strokeById('a')!;
      page.model.commit(InkEdit(removed: [a]));
      final frame = CountingCanvas();
      doc.painter().paint(frame, view);
      expect(frame.pictures, greaterThan(0));
      expect(await doc.inkIn(chunkA), 0);
      expect(await doc.inkIn(chunkC), greaterThan(0), reason: 'the rest of the chunk shows');
      await doc.rest();
      expect(await doc.inkIn(chunkA), 0, reason: 'fresh raster');

      // Undo: back at once, and in the new raster.
      doc.surfaces.undo();
      expect(await doc.inkIn(chunkA), greaterThan(0));
      await doc.rest();
      final after = CountingCanvas();
      doc.painter().paint(after, view);
      expect(after.pictures, 0);
      expect(await doc.inkIn(chunkA), greaterThan(0));

      // Sync: the stroke deleted remotely, the page reloaded.
      page.model.flush(); // Write-behind: the undo's insert is stored.
      doc.repository.delete(['a']);
      doc.surfaces.reload('p0');
      expect(await doc.inkIn(chunkA), 0, reason: 'no stale raster');
      await doc.rest();
      expect(await doc.inkIn(chunkA), 0);
      expect(await doc.inkIn(chunkC), greaterThan(0));
      doc.dispose();
    });
  });

  testWidgets('zooming out past the threshold: tiles stand in, no vectors', (tester) async {
    await tester.runAsync(() async {
      final doc = _Doc(view, scale: 0.6)
        ..save(scribbles(300, const Rect.fromLTWH(40, 40, 700, 1040)), page: 'p0');
      await doc.rest();
      doc.viewport.zoomAt(Offset.zero, 0.1 / 0.6);
      final canvas = CountingCanvas();
      doc.painter().paint(canvas, view);
      expect(canvas.pictures, 0);
      expect(canvas.images, greaterThan(0), reason: 'the tiles of 60 %, scaled');
      await doc.rest();
      final lod = CountingCanvas();
      doc.painter().paint(lod, view);
      expect(lod.pictures, 0);
      expect(doc.surfaces.peek('p0')!.rasters.length, greaterThan(0));
      doc.dispose();
    });
  });
}

/// A notebook of two A4 pages in a view at [scale] (1 device pixel per
/// logical pixel).
class _Doc {
  _Doc(Size size, {required double scale}) {
    viewport
      ..setSize(size)
      ..setView(scale: scale, offset: const Offset(20, 10));
  }

  final db = AppDatabase.inMemory();
  late final repository = StrokeRepository(db, deviceId: 'd');
  final pages = [
    for (var i = 0; i < 2; i++)
      NotebookPage(
        id: 'p$i',
        notebookId: 'nb',
        sortKey: i.toDouble(),
        width: 794,
        height: 1123,
        paper: Paper(PaperStyle.blank),
      ),
  ];
  late final layout = DocumentLayout.continuous([for (final p in pages) p.size]);
  late final surfaces = DocumentSurfaces(repository);
  final viewport = ViewportController(minScale: 0.05, maxScale: 8);

  void save(List<Stroke> strokes, {String page = 'p0'}) => repository.save([
    for (final s in strokes)
      Stroke(
        id: s.id,
        surfaceId: page,
        tool: s.tool,
        color: s.color,
        width: s.width,
        points: s.points,
        createdAt: s.createdAt,
        style: s.style,
      ),
  ]);

  DocumentInkPainter painter() =>
      DocumentInkPainter(layout: layout, pages: pages, surfaces: surfaces, viewport: viewport);

  void _show() {
    final ahead = DocumentLayout.lookahead(viewport.visibleWorld);
    surfaces.showPages({
      for (final i in layout.visiblePages(ahead))
        pages[i].id: ahead.shift(-layout.frameOf(i)!.topLeft),
    });
  }

  bool get _busy =>
      surfaces.all.any((s) => s.tiles.isBusy || s.rasters.isBusy || s.model.isLoading);

  /// Paints until nothing is pending.
  Future<void> rest() async {
    for (var i = 0; i < 40; i++) {
      _show();
      painter().paint(CountingCanvas(), viewport.size);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle(() => !_busy);
      if (!_busy && i > 1) return;
    }
  }

  /// The screen rectangle of page [index]'s local rectangle [rect].
  Rect screenRectOf(int index, Rect rect) {
    final frame = layout.frameOf(index)!;
    final page = rect.intersect(Offset.zero & frame.size).shift(frame.topLeft);
    return Rect.fromPoints(viewport.toScreen(page.topLeft), viewport.toScreen(page.bottomRight));
  }

  /// Inked pixels within [rect] in a frame painted now.
  Future<int> inkIn(Rect rect) async {
    final recorder = ui.PictureRecorder();
    painter().paint(Canvas(recorder), viewport.size);
    final picture = recorder.endRecording();
    final size = viewport.size;
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    picture.dispose();
    final Uint8List bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();
    image.dispose();
    var count = 0;
    final r = rect.deflate(1);
    for (var y = r.top.ceil(); y < r.bottom.floor(); y++) {
      for (var x = r.left.ceil(); x < r.right.floor(); x++) {
        if (bytes[(y * size.width.ceil() + x) * 4 + 3] > 0) count++;
      }
    }
    return count;
  }

  void dispose() {
    surfaces.dispose();
    db.close();
  }
}
