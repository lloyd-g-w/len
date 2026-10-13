import 'dart:math' as math;
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
import 'package:len/ink/lab/perf_probe.dart';
import 'package:len/ink/render/tiles/ink_tile_cache.dart';
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
      final db = AppDatabase.inMemory();
      final repository = StrokeRepository(db, deviceId: 'd');
      final pages = [
        for (var i = 0; i < 8; i++)
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
      final layout = DocumentLayout.continuous([for (final p in pages) p.size]);
      final surfaces = DocumentSurfaces(repository);
      final viewport = ViewportController(minScale: 0.1, maxScale: 8)
        ..setSize(view)
        ..setView(scale: 1.53, offset: const Offset(32.7, 24));
      void show() {
        // As DocumentController does.
        final ahead = DocumentLayout.lookahead(viewport.visibleWorld);
        surfaces.showPages({
          for (final i in layout.visiblePages(ahead))
            pages[i].id: ahead.shift(-layout.frameOf(i)!.topLeft),
        });
      }

      show();
      final run = _Run(
        size: view,
        dpr: 2,
        painter: () => DocumentInkPainter(
          layout: layout,
          pages: pages,
          surfaces: surfaces,
          viewport: viewport,
          devicePixelRatio: 2,
        ),
        tiles: () => [for (final s in surfaces.all) s.tiles],
        busy: () => surfaces.all.any((s) => s.tiles.isBusy || s.model.isLoading),
        summary: () => 'pages held=${surfaces.all.length}',
      );
      await run.rest();
      await run.report('notebook warm-up');
      // A fling: two pages down in 90 frames, slowing.
      for (var i = 0; i < 90; i++) {
        await run.frame(() {
          viewport.panBy(Offset(0, -61.7 * (1 - i / 90)));
          show();
        });
      }
      await run.report('notebook scroll');
      await run.rest();
      await run.report('notebook scroll, rest');
      surfaces.dispose();
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

  /// Frames showing an image that predates a change.
  int _staleFrames = 0;
  final List<int> _chunkDraws = [];
  int _drawsBefore = 0;
  final Map<String, int> _base = {};
  static const _counters = ['chunkDraws', 'tileRenders', 'tileAppends', 'chunkRecords'];

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
      'stale frames=$_staleFrames '
      'tileRenders=${_count('tileRenders')} '
      'tileAppends=${_count('tileAppends')} '
      'chunkRecords=${_count('chunkRecords')} '
      '${summary()}',
    );
    _vectorScreens = 0;
    _staleFrames = 0;
    _chunkDraws.clear();
    _mark();
  }
}
