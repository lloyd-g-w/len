import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/raster_store.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/chunk_digest.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/stroke_chunks.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/templates/paper.dart';
import 'package:len/domain/templates/paper_style.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/ink_surface.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/render/chunk_picture_cache.dart';
import 'package:len/ink/render/chunk_raster_cache.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

import 'support/canvas_fixtures.dart';
import 'support/ink_scene.dart';

const _size = Size(400, 300);

/// A canvas over [db] viewed at 10 % (chunks 51 px: level 64), as the
/// editor shows it: from [store] without loading ([stored]), or loaded.
class _View {
  _View(this.db, {this.store, bool stored = true, String device = 'd'}) {
    strokes = StrokeRepository(db, deviceId: device);
    model = SurfaceModel(
      surfaceId: 's',
      repository: strokes,
      elementRepository: ElementRepository(db, deviceId: device),
      reader: strokes,
      maxLoadedChunks: 1 << 20,
      rasterStore: store,
    );
    viewport
      ..setSize(_size)
      ..zoomAt(Offset.zero, 0.1)
      ..panBy(const Offset(40, 40));
    if (stored) {
      model.showStored(viewport.visibleWorld);
    } else {
      model.ensureLoaded(viewport.visibleWorld);
    }
  }

  final AppDatabase db;
  final RasterStore? store;
  late final StrokeRepository strokes;
  late final SurfaceModel model;
  final viewport = ViewportController(minScale: 0.01);
  late final pictures = ChunkPictureCache(model, devicePixelRatio: 1);
  late final rasters = ChunkRasterCache(pictures, maxBytes: 64 << 20);

  CommittedInkPainter get painter =>
      CommittedInkPainter(model: model, cache: pictures, viewport: viewport, rasters: rasters);

  /// Paints until frames stop changing and nothing is pending (each step
  /// — digests, reads, loads, rasters — waits for a paint asking for it);
  /// returns the last frame's draws.
  Future<CountingCanvas> warm() async {
    var stable = 0, previous = -1;
    for (var i = 0; i < 200; i++) {
      final canvas = CountingCanvas();
      painter.paint(canvas, _size);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await settle(() => !rasters.isBusy && !model.isLoading);
      stable = canvas.images == previous && canvas.pictures == 0 ? stable + 1 : 0;
      if (stable == 3) return canvas;
      previous = canvas.images;
    }
    fail('never settled');
  }

  Future<Uint8List> render() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
    painter.paint(canvas, _size);
    final image = await recorder.endRecording().toImage(_size.width ~/ 1, _size.height ~/ 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    return bytes.buffer.asUint8List();
  }

  int get visibleChunks => rasters.chunksIn(ChunkGrid.rangeFor(viewport.visibleWorld)).length;

  void dispose() {
    rasters.dispose();
    pictures.dispose();
    model.dispose();
  }
}

/// What [db] holds, rasterised afresh from memory (no store).
Future<Uint8List> _truth(AppDatabase db) async {
  final view = _View(db, stored: false);
  await view.warm();
  final bytes = await view.render();
  view.dispose();
  return bytes;
}

void _expectSame(Uint8List actual, Uint8List expected) {
  final (_, off) = imageDiff(actual, expected);
  // PNG keeps colours unpremultiplied: translucent pixels may round.
  expect(off, lessThan(0.001), reason: '${(off * 100).toStringAsFixed(2)} % of pixels differ');
}

Stroke _bar(String id, Offset from, {double length = 900}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xFFC62828,
  width: 60,
  points: [for (var i = 0; i <= 10; i++) StrokePoint(from.dx + length * i / 10, from.dy, 0.5)],
  createdAt: 1 << 40,
);

void main() {
  final ink = scribbles(600, const Rect.fromLTWH(0, 0, 3000, 2000), seed: 5, points: 16);

  test('storage and memory agree on chunk digests (strokes, text, copies)', () {
    final db = AppDatabase.inMemory();
    final view = _View(db, stored: false);
    view.strokes.save(ink.take(200));
    final text = SurfaceElement(
      id: 't',
      surfaceId: 's',
      type: 'text',
      rect: const Rect.fromLTWH(100, 100, 700, 80),
      z: 1,
      createdAt: 1,
      data: const TextData(text: 'Persistent').toJson(),
    );
    final image = SurfaceElement(
      id: 'i',
      surfaceId: 's',
      type: 'image',
      rect: const Rect.fromLTWH(5200, 100, 100, 100),
      z: -1,
      createdAt: 1,
      data: const {'blob': 'ab', 'w': 10, 'h': 10},
    );
    ElementRepository(db, deviceId: 'd').save([text, image]);
    view.model
      ..reload()
      ..ensureLoaded(const Rect.fromLTWH(0, 0, 6000, 3000));
    final range = ChunkGrid.rangeFor(const Rect.fromLTWH(-512, -512, 6000, 4000));
    final stored = view.strokes.chunkDigests('s', range);
    expect(stored, isNotEmpty);
    for (final MapEntry(:key, :value) in stored.entries) {
      expect(view.model.digestOf(key), value, reason: '$key');
    }
    expect(stored.containsKey((x: 10, y: 0)), isTrue);
    expect(stored[(x: 0, y: 0)]!.elements, 1);

    SurfaceCopier(
      view.strokes,
      elements: ElementRepository(db, deviceId: 'd'),
    ).copy(from: 's', to: 'copy');
    final copied = view.strokes.chunkDigests('copy', range);
    final byChunk = <ChunkKey, List<Stroke>>{};
    for (final s in SurfaceCopier(view.strokes).loadAll('copy')) {
      for (final key in StrokeChunks.of(s)) {
        (byChunk[key] ??= []).add(s);
      }
    }
    expect(copied.keys.toSet(), stored.keys.toSet());
    for (final MapEntry(:key, :value) in copied.entries) {
      final strokes = ChunkDigest.of(byChunk[key] ?? const [], const []);
      expect((value.strokes, value.strokeSum), (strokes.strokes, strokes.strokeSum));
      expect((value.elements, value.elementSum), (stored[key]!.elements, stored[key]!.elementSum));
    }
    view.dispose();
    db.close();
  });

  testWidgets('reopening far out draws stored rasters without loading a stroke', (tester) async {
    await tester.runAsync(() async {
      final db = AppDatabase.inMemory();
      final store = MemoryRasterStore();
      StrokeRepository(db, deviceId: 'd').save(ink);

      final first = _View(db, store: store);
      final cold = await first.warm();
      final chunks = first.visibleChunks;
      expect(cold.images, chunks);
      expect(first.model.loadedStrokeCount, greaterThan(0)); // Nothing stored yet.
      expect(store.length, chunks);
      first.dispose();

      final reopened = _View(db, store: store);
      final warm = await reopened.warm();
      expect(warm.images, chunks);
      expect(reopened.model.loadedStrokeCount, 0);
      _expectSame(await reopened.render(), await _truth(db));

      // A pen touching down loads what is visible.
      reopened.model.loadVisible();
      expect(reopened.model.loadedStrokeCount, greaterThan(0));
      reopened.dispose();
      db.close();
    });
  });

  testWidgets('an edit, its undo, a sync and an emptied chunk never show stale rasters', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final db = AppDatabase.inMemory();
      final store = MemoryRasterStore();
      StrokeRepository(db, deviceId: 'd').save(ink);
      final first = _View(db, store: store);
      await first.warm();
      first.dispose();

      // Edit: written in an earlier session.
      final editor = _View(db, store: store, stored: false);
      editor.model.addStroke(_bar('edit', const Offset(100, 300)));
      editor.dispose();
      final afterEdit = _View(db, store: store);
      await afterEdit.warm();
      _expectSame(await afterEdit.render(), await _truth(db));
      // Only the edited chunks were read.
      expect(afterEdit.model.loadedStrokeCount, lessThan(ink.length ~/ 2));

      // Undo, in the open view (zoomed out, after writing).
      afterEdit.model.loadVisible();
      afterEdit.model.addStroke(_bar('undone', const Offset(1200, 900)));
      await afterEdit.warm();
      afterEdit.model.undo();
      afterEdit.model.flush();
      await afterEdit.warm();
      _expectSame(await afterEdit.render(), await _truth(db));
      afterEdit.dispose();
      final reopened = _View(db, store: store);
      await reopened.warm();
      _expectSame(await reopened.render(), await _truth(db));
      expect(reopened.model.loadedStrokeCount, 0); // Undo restored stored content.

      // Sync from another device, while open far out.
      final other = StrokeRepository(db, deviceId: 'other');
      other.save([_bar('remote', const Offset(600, 1500), length: 1500)]);
      reopened.model.reload(); // What a sync's remote changes do.
      await reopened.warm();
      _expectSame(await reopened.render(), await _truth(db));

      // A chunk emptied on another device.
      const emptied = (x: 2, y: 1);
      final ids = [
        for (final s in SurfaceCopier(other).loadAll('s'))
          if (other.loadChunks('s', [emptied]).any((c) => c.id == s.id)) s.id,
      ];
      expect(ids, isNotEmpty);
      other.delete(ids);
      expect(other.populatedChunks('s', const ChunkRange(2, 1, 2, 1)), isEmpty);
      reopened.model.reload();
      final frame = await reopened.warm();
      expect(frame.images, reopened.visibleChunks);
      expect(reopened.rasters.chunksIn(const ChunkRange(2, 1, 2, 1)), isEmpty);
      _expectSame(await reopened.render(), await _truth(db));
      reopened.dispose();
      db.close();
    });
  });

  test('split view: an overview pane loads nothing a close-up pane does not need', () {
    final db = AppDatabase.inMemory();
    final strokes = StrokeRepository(db, deviceId: 'd')..save(ink);
    final model = SurfaceModel(
      surfaceId: 's',
      repository: strokes,
      reader: strokes,
      maxLoadedChunks: 1 << 20,
      rasterStore: MemoryRasterStore(),
    );
    final overview = Object(), closeUp = Object();
    model.showStored(const Rect.fromLTWH(0, 0, 4000, 3000), view: overview);
    model.ensureLoaded(const Rect.fromLTWH(0, 0, 300, 200), view: closeUp);
    final near = model.loadedStrokeCount;
    expect(near, inInclusiveRange(1, ink.length ~/ 3));
    // The overview asks for a chunk without a raster; the close-up keeps
    // what it has.
    model.requestChunks([(x: 4, y: 3)]);
    expect(model.isComplete((x: 4, y: 3)), isTrue);
    expect(model.isComplete((x: 0, y: 0)), isTrue);
    // Writing in the close-up loads nothing more; touching the overview
    // loads all it shows.
    model.loadVisible(view: closeUp);
    expect(model.isComplete((x: 2, y: 2)), isFalse);
    model.loadVisible(view: overview);
    expect(model.loadedStrokeCount, ink.length);
    model.dispose();
    db.close();
  });

  inkSurfaceTests(ink);

  test('digests are 48-bit sums that change with content', () {
    final a = ChunkDigest.of([ink[0], ink[1]], const []);
    final b = ChunkDigest.of([ink[1], ink[0]], const []);
    final c = ChunkDigest.of([ink[0]], const []);
    expect(a, b);
    expect(a == c, isFalse);
    expect(ChunkDigest.ofStroke('x'), lessThan(1 << 48));
  });
}

/// The editor's canvas widget picks stored rasters far out, loads closer in
/// and when a pen touches down.
void inkSurfaceTests(List<Stroke> ink) {
  testWidgets('a canvas far out loads nothing until zoomed in or touched', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final strokes = StrokeRepository(db, deviceId: 'd')..save(ink);
    final model = SurfaceModel(
      surfaceId: 's',
      repository: strokes,
      reader: strokes,
      rasterStore: _PendingStore(),
    );
    addTearDown(model.dispose);
    final viewport = ViewportController(minScale: 0.01)..setView(scale: 0.1, offset: Offset.zero);
    final live = LiveInk();
    final input = InkInputController(
      model: model,
      viewport: viewport,
      tools: ToolSettings(),
      live: live,
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: _size),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: InkSurface(
            model: model,
            viewport: viewport,
            input: input,
            live: live,
            paper: Paper(PaperStyle.blank),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(model.showsStored, isTrue);
    expect(model.loadedStrokeCount, 0);
    viewport.setView(scale: 1, offset: Offset.zero);
    await tester.pump();
    expect(model.showsStored, isFalse);
    final near = model.loadedStrokeCount;
    expect(near, inInclusiveRange(1, ink.length ~/ 2));
    viewport.setView(scale: 0.1, offset: Offset.zero);
    await tester.pump();
    expect(model.showsStored, isTrue);
    expect(model.loadedStrokeCount, near);
    // A pen touching down loads all the view shows.
    final pen = TestPointer(1, PointerDeviceKind.stylus);
    await tester.sendEventToBinding(pen.down(const Offset(200, 150)));
    await tester.sendEventToBinding(pen.up());
    expect(model.showsStored, isFalse);
    expect(model.loadedStrokeCount, greaterThan(near));
    await tester.pumpWidget(const SizedBox());
  });
}

/// A store whose rasters are always still being read.
class _PendingStore implements RasterStore {
  @override
  Future<Uint8List?> read(String name) => Completer<Uint8List?>().future;

  @override
  Future<void> write(String name, Uint8List bytes) async {}

  @override
  Future<int> size() async => 0;

  @override
  Future<void> clear() async {}
}
