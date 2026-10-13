import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/raster_store.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/ink/lab/perf_probe.dart';
import 'package:len/ink/render/chunk_picture_cache.dart';
import 'package:len/ink/render/chunk_raster_cache.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';

import '../support/canvas_fixtures.dart';
import '../support/ink_scene.dart';

/// Stored level-of-detail rasters far out (docs/INK_LAB.md, *Headless
/// benchmark*, round 6): a canvas at 5 % shows ≈ 1 600 chunks. Counts how
/// many store reads run at once, how soon the middle of the screen shows,
/// reads wasted on chunks panned away from, and writes made while frames
/// were being painted.
///
/// Run: `tool/light.sh flutter test test/perf/lod_store_perf_test.dart`.
void main() {
  setUpAll(PerfProbe.startCounting);

  testWidgets('reopen a big canvas at 5 %', (tester) async {
    await tester.runAsync(() async {
      final db = AppDatabase.inMemory();
      final repository = StrokeRepository(db, deviceId: 'd')
        ..save(scribbles(16000, const Rect.fromLTWH(0, 0, 30000, 20000), points: 8));
      final store = _DiskLike();

      final first = _View(repository, store);
      final opened = await first.open();
      await settle(() => !first.rasters.isBusy);
      // ignore: avoid_print
      print(
        'INKPERF 5 % first open: ${opened.chunks} chunks after ${opened.frames} frames; '
        'writes while painting=${opened.writesWhilePainting}, after=${store.writes - opened.writesWhilePainting}',
      );
      first.dispose();

      store.reset();
      final reopened = _View(repository, store);
      final again = await reopened.open();
      // ignore: avoid_print
      print(
        'INKPERF 5 % reopened: middle after ${again.middleFrame} frames, all ${again.chunks} '
        'after ${again.frames} frames, ${again.took.inMilliseconds} ms; reads=${store.reads}, '
        'at once ≤ ${store.peak}',
      );
      reopened.dispose();

      store.reset();
      final panned = _View(repository, store);
      final away = await panned.open(
        onFrame: (frame) {
          if (frame == 3) panned.viewport.panBy(const Offset(-900, -500));
        },
      );
      final visible = {
        for (final key in ChunkGrid.rangeFor(panned.viewport.visibleWorld).keys) key,
      };
      final wasted = store.names.where((name) => !visible.contains(_chunkOf(name))).length;
      // ignore: avoid_print
      print(
        'INKPERF 5 % reopened, panned away at frame 3: all ${away.chunks} after ${away.frames} '
        'frames; reads=${store.reads}, of chunks out of view=$wasted',
      );
      panned.dispose();
      db.close();
    });
  }, timeout: const Timeout(Duration(minutes: 4)));
}

ChunkKey _chunkOf(String name) {
  final parts = name.split('_');
  return (x: int.parse(parts[1]), y: int.parse(parts[2]));
}

/// Rasters in memory, read with a disk-like delay; counts reads at once.
class _DiskLike implements RasterStore {
  final _inner = MemoryRasterStore();
  int reading = 0, peak = 0, reads = 0, writes = 0;
  final List<String> names = [];

  void reset() {
    peak = reads = writes = 0;
    names.clear();
  }

  @override
  Future<Uint8List?> read(String name) async {
    reads++;
    names.add(name);
    peak = math.max(peak, ++reading);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    reading--;
    return _inner.read(name);
  }

  @override
  Future<void> write(String name, Uint8List bytes) {
    writes++;
    return _inner.write(name, bytes);
  }
}

/// A canvas opened at 5 % in a 1280 × 800 view at 2×, as the editor does.
class _View {
  _View(StrokeRepository repository, this.store) {
    model = SurfaceModel(
      surfaceId: 's',
      repository: repository,
      reader: repository,
      maxLoadedChunks: 1 << 20,
      rasterStore: store,
    );
    viewport
      ..setSize(_size)
      ..setView(scale: 0.05, offset: const Offset(-100, -60));
    model.showStored(viewport.visibleWorld);
  }

  static const _size = Size(1280, 800);
  final _DiskLike store;
  late final SurfaceModel model;
  final viewport = ViewportController(minScale: 0.01);
  late final pictures = ChunkPictureCache(model, devicePixelRatio: 2);
  late final rasters = ChunkRasterCache(pictures, maxBytes: 64 << 20);

  /// Frames 16 ms apart until every visible chunk shows its own raster.
  Future<({int frames, int? middleFrame, int chunks, Duration took, int writesWhilePainting})>
  open({void Function(int frame)? onFrame}) async {
    final watch = Stopwatch()..start();
    final level = ChunkRasterCache.levelFor(ChunkGrid.size * viewport.scale * 2)!;
    int? middle;
    for (var frame = 1; frame < 4000; frame++) {
      onFrame?.call(frame);
      model.showStored(viewport.visibleWorld);
      CommittedInkPainter(
        model: model,
        cache: pictures,
        viewport: viewport,
        rasters: rasters,
        devicePixelRatio: 2,
      ).paint(CountingCanvas(), _size);
      bool own(ChunkKey k) {
        final image = rasters.imageFor(k, level);
        return image != null && image.width == level && rasters.overlayOf(k, image).isEmpty;
      }

      final centre = viewport.visibleWorld.center;
      if (middle == null && own(ChunkGrid.keyAt(centre.dx, centre.dy))) middle = frame;
      final chunks = rasters.chunksIn(ChunkGrid.rangeFor(viewport.visibleWorld));
      if (chunks.isNotEmpty && !rasters.isMaking && !model.isLoading && chunks.every(own)) {
        return (
          frames: frame,
          middleFrame: middle,
          chunks: chunks.length,
          took: watch.elapsed,
          writesWhilePainting: store.writes,
        );
      }
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
