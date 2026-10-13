import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/raster_store.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/document_layout.dart';
import 'package:len/features/editor/document/document_painters.dart';
import 'package:len/features/editor/document/document_surfaces.dart';
import 'package:len/features/editor/document/page_thumbnail_cache.dart';
import 'package:len/ink/lab/perf_probe.dart';
import 'package:len/ink/render/chunk_picture_cache.dart';
import 'package:len/ink/render/chunk_raster_cache.dart';
import 'package:len/ink/render/content_painter.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/tiles/ink_tile_cache.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

import '../support/canvas_fixtures.dart';
import '../support/ink_scene.dart';

/// Committed-ink rendering work per scenario (see docs/INK_LAB.md,
/// *Rendering performance*): frames are painted and rasterised headlessly
/// (CPU, so times are only comparable with each other), with the work
/// counted — chunk pictures replayed as vectors, tiles rendered.
///
/// Run: `tool/light.sh flutter test test/perf/ink_render_perf_test.dart`.
void main() {
  setUpAll(PerfProbe.startCounting);

  // A dense area of handwriting: 1280 × 800 at 2× = 2560 × 1600 device px.
  const view = Size(1280, 800);
  final dense = scribbles(9000, const Rect.fromLTWH(-1500, -1000, 4300, 2800), points: 14);

  testWidgets('pan at 100 % by fractions of a pixel, then rest', (tester) async {
    await tester.runAsync(() async {
      final scene = _scene(dense);
      await scene.warm();
      final run = _Run.of(scene);
      for (var i = 0; i < 40; i++) {
        await run.frame(() => scene.viewport.panBy(const Offset(-6.37, -2.71)));
      }
      await run.report('pan 100 %');
      await run.rest();
      await run.report('pan 100 %, rest');
      scene.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('pinch out to 40 %, rest, pinch in to 250 %, rest', (tester) async {
    await tester.runAsync(() async {
      final scene = _scene(dense);
      await scene.warm();
      final run = _Run.of(scene);
      final focal = view.center(Offset.zero);
      for (var i = 0; i < 30; i++) {
        await run.frame(() => scene.viewport.zoomAt(focal, math.pow(0.4, 1 / 30).toDouble()));
      }
      await run.report('pinch out');
      await run.rest();
      await run.report('pinch out, rest');
      for (var i = 0; i < 30; i++) {
        await run.frame(() => scene.viewport.zoomAt(focal, math.pow(6.25, 1 / 30).toDouble()));
      }
      await run.report('pinch in');
      await run.rest();
      await run.report('pinch in, rest');
      scene.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('pinch out to 12 % across the level-of-detail threshold, rest', (tester) async {
    await tester.runAsync(() async {
      final scene = _scene(dense, lod: true);
      await scene.warm();
      final run = _Run.of(scene);
      final focal = view.center(Offset.zero);
      for (var i = 0; i < 30; i++) {
        await run.frame(() => scene.viewport.zoomAt(focal, math.pow(0.12, 1 / 30).toDouble()));
      }
      await run.report('pinch out to 12 % (LOD)');
      await run.rest();
      await run.report('pinch out to 12 % (LOD), rest');
      scene.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('write 20 strokes on a dense page', (tester) async {
    await tester.runAsync(() async {
      final scene = _scene(dense);
      await scene.warm();
      final run = _Run.of(scene);
      for (var i = 0; i < 20; i++) {
        final at = Offset(100 + (i % 5) * 200.0, 150 + (i ~/ 5) * 150.0);
        await run.frame(() => scene.model.addStroke(_scrawl('w$i', at, i)));
        for (var f = 0; f < 4; f++) {
          await run.frame(() {});
        }
      }
      await run.rest();
      await run.report('writing');
      scene.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('undo a lasso move of 2 000 strokes', (tester) async {
    await tester.runAsync(() async {
      final scene = _scene(dense);
      final visible = scene.viewport.visibleWorld;
      final picked = dense.where((s) => visible.contains(s.bounds.center)).take(2000).toList();
      final moved = [for (final s in picked) _shifted(s, const Offset(80, 40))];
      scene.model.commit(InkEdit(removed: picked, added: moved));
      await scene.warm();
      final run = _Run.of(scene);
      await run.frame(scene.model.undo);
      for (var f = 0; f < 5; f++) {
        await run.frame(() {});
      }
      await run.rest();
      await run.report('undo lasso move');
      scene.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('scroll a notebook of handwritten pages', (tester) async {
    await tester.runAsync(() async {
      final nb = _Notebook(8, scale: 1.53, offset: const Offset(32.7, 24));
      await nb.run.rest();
      await nb.run.report('notebook warm-up');
      // A fling: two pages down in 90 frames, slowing.
      for (var i = 0; i < 90; i++) {
        await nb.run.frame(() => nb.panBy(Offset(0, -61.7 * (1 - i / 90))));
      }
      await nb.run.report('notebook scroll');
      await nb.run.rest();
      await nb.run.report('notebook scroll, rest');
      nb.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('zoom a notebook out to many pages, then scroll', (tester) async {
    await tester.runAsync(() async {
      final nb = _Notebook(16, scale: 0.6, offset: const Offset(200, 24));
      await nb.run.rest();
      await nb.run.report('notebook 60 %');
      // Pinch out to 12 % (six pages on screen) around the top middle.
      for (var i = 0; i < 30; i++) {
        await nb.run.frame(() => nb.zoomAt(const Offset(640, 100), math.pow(0.2, 1 / 30)));
      }
      await nb.run.report('notebook pinch out to 12 %');
      await nb.run.rest();
      await nb.run.report('notebook pinch out to 12 %, rest');
      for (var i = 0; i < 40; i++) {
        await nb.run.frame(() => nb.panBy(const Offset(0, -12.3)));
      }
      await nb.run.report('notebook scroll at 12 %');
      await nb.run.rest();
      await nb.run.report('notebook scroll at 12 %, rest');
      nb.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('page overview: recording and drawing 16 thumbnails', (tester) async {
    await tester.runAsync(() async {
      final db = AppDatabase.inMemory();
      final repository = StrokeRepository(db, deviceId: 'd');
      const page = Size(794, 1123);
      for (var i = 0; i < 16; i++) {
        repository.save([
          for (final s in scribbles(1500, const Rect.fromLTWH(40, 40, 700, 1040), seed: i))
            _onPage(s, 'p$i'),
        ]);
      }
      final copier = SurfaceCopier(repository);
      // Recording a page (fresh strokes, as loaded): outlines vs hairlines.
      Duration record({required bool sketch}) {
        final watch = Stopwatch()..start();
        for (var i = 0; i < 16; i++) {
          final recorder = ui.PictureRecorder();
          ContentPainter.paint(
            Canvas(recorder),
            copier.loadAll('p$i'),
            const [],
            pixelScale: ThumbnailCache.imageScale,
            sketchThin: sketch,
            sketchBelow: ThumbnailCache.sketchBelow,
          );
          recorder.endRecording().dispose();
        }
        return watch.elapsed;
      }

      final load = Stopwatch()..start();
      for (var i = 0; i < 16; i++) {
        copier.loadAll('p$i');
      }
      final loading = load.elapsed;
      record(sketch: true); // Warm up.
      final outlines = record(sketch: false);
      final hairlines = record(sketch: true);
      final cache = ThumbnailCache(copier);
      for (var i = 0; i < 16; i++) {
        cache.inkOf('p$i');
      }
      await settle(() => [for (var i = 0; i < 16; i++) cache.inkOf('p$i')].every((p) => p != null));
      // A frame of the overview: 4 × 4 thumbnails 200 × 283 at 2×.
      Future<Duration> frame({required bool rasters}) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (var i = 0; i < 16; i++) {
          canvas
            ..save()
            ..translate(i % 4 * 400.0, i ~/ 4 * 566.0)
            ..scale(400 / page.width);
          final raster = rasters ? cache.rasterOf('p$i', page, 400, 566) : null;
          if (raster != null) {
            canvas.drawImageRect(
              raster,
              Rect.fromLTWH(0, 0, raster.width.toDouble(), raster.height.toDouble()),
              Offset.zero & page,
              Paint()..filterQuality = FilterQuality.medium,
            );
          } else {
            canvas.drawPicture(cache.inkOf('p$i')!);
          }
          canvas.restore();
        }
        final picture = recorder.endRecording();
        final watch = Stopwatch()..start();
        (await picture.toImage(1600, 2264)).dispose();
        picture.dispose();
        return watch.elapsed;
      }

      final vector = await frame(rasters: false);
      await frame(rasters: true);
      await settle(
        () =>
            [for (var i = 0; i < 16; i++) cache.rasterOf('p$i', page, 400, 566)]
                .every((r) => r != null),
      );
      final images = await frame(rasters: true);
      // ignore: avoid_print
      print(
        'INKPERF overview: 16 pages of 1 500 strokes, loading ${loading.inMilliseconds} ms, '
        'loading and recording them '
        '${outlines.inMilliseconds} ms with outlines, ${hairlines.inMilliseconds} ms with '
        'hairlines; frame raster ${vector.inMilliseconds} ms from pictures, '
        '${images.inMilliseconds} ms from rasters',
      );
      cache.dispose();
      db.close();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('reopen a big canvas at 10 %', (tester) async {
    await tester.runAsync(() async {
      final db = AppDatabase.inMemory();
      final repository = StrokeRepository(db, deviceId: 'd')
        ..save(scribbles(40000, const Rect.fromLTWH(0, 0, 30000, 20000), points: 10));
      final store = MemoryRasterStore();
      Future<void> run(String name, RasterStore? store) async {
        final reads = PerfProbe.counter('lodStoreReads'), hits = PerfProbe.counter('lodStoreHits');
        final rasters = PerfProbe.counter('lodRasters');
        final records = PerfProbe.counter('chunkRecords');
        final writes = PerfProbe.counter('lodStoreWrites');
        final view = _Reopened(repository, store: store, scale: 0.1);
        final (frames, took) = await view.open();
        final chunks = view.rasters.chunksIn(ChunkGrid.rangeFor(view.viewport.visibleWorld));
        // ignore: avoid_print
        print(
          'INKPERF reopen at 10 % ($name): ${chunks.length} chunks complete after $frames frames, '
          '${took.inMilliseconds} ms; strokes loaded=${view.model.loadedStrokeCount} '
          'chunkRecords=${PerfProbe.counter('chunkRecords') - records} '
          'lodRasters=${PerfProbe.counter('lodRasters') - rasters} '
          'store reads=${PerfProbe.counter('lodStoreReads') - reads} '
          'hits=${PerfProbe.counter('lodStoreHits') - hits} '
          'writes=${PerfProbe.counter('lodStoreWrites') - writes}',
        );
        await settle(() => !view.rasters.isBusy); // Writes done.
        view.dispose();
      }

      await run('no store, as before', null);
      await run('first open, storing', store);
      await run('reopened', store);
      // ignore: avoid_print
      print('INKPERF reopen at 10 %: ${store.length} rasters stored');
      db.close();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('pan a big canvas at 6 %', (tester) async {
    await tester.runAsync(() async {
      final big = scribbles(40000, const Rect.fromLTWH(0, 0, 30000, 20000), points: 10);
      final scene = _scene(big, scale: 0.06, lod: true);
      await scene.warm();
      final run = _Run.of(scene);
      for (var i = 0; i < 40; i++) {
        await run.frame(() => scene.viewport.panBy(const Offset(-9.3, -5.1)));
      }
      await run.report('far pan 6 %');
      await run.rest();
      await run.report('far pan 6 %, rest');
      scene.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// A canvas opened at [scale] in a 1280 × 800 view at 2×, as the editor
/// shows it: with a raster [store], zoomed far out, it draws stored rasters
/// and loads only chunks without one.
class _Reopened {
  _Reopened(this.repository, {this.store, required double scale}) {
    model = SurfaceModel(
      surfaceId: 's',
      repository: repository,
      reader: repository,
      maxLoadedChunks: 1 << 20,
      rasterStore: store,
    );
    viewport
      ..setSize(_size)
      ..setView(scale: scale, offset: const Offset(-300, -200));
    if (store != null) {
      model.showStored(viewport.visibleWorld);
    } else {
      model.ensureLoaded(viewport.visibleWorld);
    }
  }

  static const _size = Size(1280, 800);
  final StrokeRepository repository;
  final RasterStore? store;
  late final SurfaceModel model;
  final viewport = ViewportController(minScale: 0.01);
  late final pictures = ChunkPictureCache(model, devicePixelRatio: 2);
  late final rasters = ChunkRasterCache(pictures, maxBytes: 64 << 20);

  /// Frames 16 ms apart until every visible chunk shows its own raster;
  /// returns (frames, wall time).
  Future<(int, Duration)> open() async {
    final watch = Stopwatch()..start();
    final level = ChunkRasterCache.levelFor(ChunkGrid.size * viewport.scale * 2)!;
    for (var frame = 1; frame < 2000; frame++) {
      CommittedInkPainter(
        model: model,
        cache: pictures,
        viewport: viewport,
        rasters: rasters,
        devicePixelRatio: 2,
      ).paint(CountingCanvas(), _size);
      final chunks = rasters.chunksIn(ChunkGrid.rangeFor(viewport.visibleWorld));
      final complete =
          chunks.isNotEmpty &&
          !rasters.isMaking &&
          !model.isLoading &&
          chunks.every((k) {
            final image = rasters.imageFor(k, level);
            return image != null && image.width == level && rasters.overlayOf(k, image).isEmpty;
          });
      if (complete) return (frame, watch.elapsed);
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    fail('never complete');
  }

  void dispose() {
    rasters.dispose();
    pictures.dispose();
    model.dispose();
  }
}

/// A notebook of [count] handwritten A4 pages (1 200 strokes each) in a
/// 1280 × 800 view at 2×, painted as the editor does.
class _Notebook {
  _Notebook(int count, {required double scale, required Offset offset}) {
    pages = [
      for (var i = 0; i < count; i++)
        NotebookPage(
          id: 'p$i',
          notebookId: 'nb',
          sortKey: i.toDouble(),
          width: 794,
          height: 1123,
          paper: Paper(PaperStyle.blank),
        ),
    ];
    for (final page in pages) {
      repository.save([
        for (final s in scribbles(1200, const Rect.fromLTWH(40, 40, 700, 1040), points: 14))
          _onPage(s, page.id),
      ]);
    }
    layout = DocumentLayout.continuous([for (final p in pages) p.size]);
    surfaces = DocumentSurfaces(repository);
    viewport
      ..setSize(_view)
      ..setView(scale: scale, offset: offset);
    _show();
    run = _Run(
      size: _view,
      dpr: 2,
      painter: () => DocumentInkPainter(
        layout: layout,
        pages: pages,
        surfaces: surfaces,
        viewport: viewport,
        devicePixelRatio: 2,
      ),
      tiles: () => [for (final s in surfaces.all) s.tiles],
      busy: () => surfaces.all.any((s) => s.tiles.isBusy || s.rasters.isBusy || s.model.isLoading),
      summary: () => 'pages held=${surfaces.all.length}',
    );
  }

  static const _view = Size(1280, 800);
  final db = AppDatabase.inMemory();
  late final repository = StrokeRepository(db, deviceId: 'd');
  late final List<NotebookPage> pages;
  late final DocumentLayout layout;
  late final DocumentSurfaces surfaces;
  final viewport = ViewportController(minScale: 0.1, maxScale: 8);
  late final _Run run;

  /// Loads the pages in and near the view, as DocumentController does.
  void _show() {
    final ahead = DocumentLayout.lookahead(viewport.visibleWorld);
    surfaces.showPages({
      for (final i in layout.visiblePages(ahead))
        pages[i].id: ahead.shift(-layout.frameOf(i)!.topLeft),
    });
  }

  void panBy(Offset by) {
    viewport.panBy(by);
    _show();
  }

  void zoomAt(Offset focal, num factor) {
    viewport.zoomAt(focal, factor.toDouble());
    _show();
  }

  void dispose() {
    surfaces.dispose();
    db.close();
  }
}

/// A 1280 × 800 view at 2× with the editor's settle delay.
InkScene _scene(List<Stroke> strokes, {double scale = 1, bool lod = false}) => InkScene(
  strokes,
  size: const Size(1280, 800),
  dpr: 2,
  scale: scale,
  lod: lod,
  settleDelay: const Duration(milliseconds: 150),
);

Stroke _scrawl(String id, Offset at, int n) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xFFC62828,
  width: 3,
  points: [
    for (var i = 0; i < 30; i++) StrokePoint(at.dx + i * 4.0, at.dy + 12 * math.sin(i * 0.7), .6),
  ],
  createdAt: (1 << 40) + n,
);

Stroke _onPage(Stroke s, String page) => Stroke(
  id: '$page-${s.id}',
  surfaceId: page,
  tool: s.tool,
  color: s.color,
  width: s.width,
  points: s.points,
  createdAt: s.createdAt,
  style: s.style,
);

Stroke _shifted(Stroke s, Offset by) => Stroke(
  id: '${s.id}m',
  surfaceId: s.surfaceId,
  tool: s.tool,
  color: s.color,
  width: s.width,
  points: [for (final p in s.points) StrokePoint(p.x + by.dx, p.y + by.dy, p.pressure)],
  createdAt: s.createdAt,
  style: s.style,
);

/// Frames of one scenario: per frame its rasterisation time and the
/// vector work it did; between frames the tile renders it caused.
class _Run {
  _Run({
    required this.size,
    required this.dpr,
    required this.painter,
    required this.tiles,
    required this.busy,
    required this.summary,
  }) {
    _mark();
  }

  /// A run over an [InkScene].
  factory _Run.of(InkScene scene) => _Run(
    size: scene.size,
    dpr: scene.dpr,
    painter: scene.painter,
    tiles: () => [scene.tiles],
    busy: () => scene.busy,
    summary: () => 'images=${scene.tiles.imageCount} lod=${scene.rasters?.length ?? 0}',
  );

  final Size size;
  final double dpr;
  final CustomPainter Function() painter;
  final Iterable<InkTileCache> Function() tiles;
  final bool Function() busy;
  final String Function() summary;
  final List<ui.Picture> _pictures = [];

  /// Screens' worth of tile area drawn as vectors.
  double _vectorScreens = 0;

  /// Screens' worth of area left empty until its tiles render.
  double _blankScreens = 0;

  /// Frames showing an image that predates a change.
  int _staleFrames = 0;
  final List<int> _chunkDraws = [];
  int _drawsBefore = 0;
  final Map<String, int> _base = {};
  static const _counters = [
    'chunkDraws',
    'tileRenders',
    'tileAppends',
    'chunkRecords',
    'lodRasters',
  ];

  void _mark() {
    for (final c in _counters) {
      _base[c] = PerfProbe.counter(c);
    }
    _drawsBefore = _base['chunkDraws']!;
  }

  int _count(String name) => PerfProbe.counter(name) - _base[name]!;

  /// Paints one frame after [change]; it is rasterised in [report], so
  /// slow (CPU) rasterisation does not stretch the time between frames.
  Future<void> frame(VoidCallback change) async {
    change();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    painter().paint(canvas, size);
    _pictures.add(recorder.endRecording());
    // Caches not painted this frame keep zeroed stats.
    if (tiles().any((t) => t.lastPaint.staleImages > 0)) _staleFrames++;
    for (final t in tiles()) {
      _vectorScreens += t.lastPaint.vectorPixels / (size.width * size.height * dpr * dpr);
      _blankScreens += t.lastPaint.blankPixels / (size.width * size.height * dpr * dpr);
      t.lastPaint.reset();
    }
    final draws = PerfProbe.counter('chunkDraws');
    _chunkDraws.add(draws - _drawsBefore);
    _drawsBefore = draws;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    // As on a GPU, tile renders started for this frame are done by the
    // next one (here they rasterise on the CPU, many times slower).
    await settle(() => tiles().every((t) => t.rendering == 0));
  }

  /// Frames until no more renders are pending (the view at rest).
  Future<void> rest() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (var i = 0; i < 100 && (busy() || i < 2); i++) {
      await frame(() {});
      await settle(() => !busy());
    }
    await frame(() {});
  }

  Future<void> report(String name) async {
    final rasterUs = <int>[];
    final pixels = size * dpr;
    for (final picture in _pictures) {
      final watch = Stopwatch()..start();
      final image = await picture.toImage(pixels.width.ceil(), pixels.height.ceil());
      rasterUs.add(watch.elapsedMicroseconds);
      image.dispose();
      picture.dispose();
    }
    _pictures.clear();
    final sorted = rasterUs..sort();
    String ms(int us) => (us / 1000).toStringAsFixed(1);
    final p50 = sorted[sorted.length ~/ 2];
    final p90 = sorted[math.min(sorted.length - 1, (sorted.length * .9).floor())];
    // ignore: avoid_print
    print(
      'INKPERF $name: frames=${sorted.length} raster p50/p90/max='
      '${ms(p50)}/${ms(p90)}/${ms(sorted.last)} ms; '
      'vector frames=${_chunkDraws.where((d) => d > 0).length} '
      'chunkDraws=${_chunkDraws.fold(0, (a, b) => a + b)} '
      'vector screens=${_vectorScreens.toStringAsFixed(2)} '
      'blank screens=${_blankScreens.toStringAsFixed(2)} '
      'stale frames=$_staleFrames '
      'tileRenders=${_count('tileRenders')} '
      'tileAppends=${_count('tileAppends')} '
      'chunkRecords=${_count('chunkRecords')} '
      'lodRasters=${_count('lodRasters')} '
      '${summary()}',
    );
    _vectorScreens = 0;
    _blankScreens = 0;
    _staleFrames = 0;
    _chunkDraws.clear();
    _mark();
  }
}
