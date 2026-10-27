import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:len/domain/notebook_page.dart';
import 'package:len/features/documents/pdf/pdf_background_cache.dart';
import 'package:len/features/documents/pdf/pdf_renderer.dart';
import 'package:len/features/documents/pdf/pdf_tiles.dart';
import 'package:len/features/editor/document/page_backgrounds.dart';
import 'package:pdfrx/pdfrx.dart';

/// One render [PdfBackgroundCache] asked [CountingRenderer] for.
class RenderRecord {
  RenderRecord(this.page, this.width, {this.tile, this.viewport});

  final int page;

  /// Whole-page width, or the tile's level.
  final int width;

  /// (col, row) of a tile; null for a whole page.
  final (int, int)? tile;

  /// (x, y, width, height) of a viewport render (an area that isn't a tile);
  /// [tile] is null then.
  final (int, int, int, int)? viewport;

  /// When it was asked for, started on the PDFium queue and done (µs on
  /// [CountingRenderer.clock]).
  int asked = 0, started = -1, done = -1;
  ui.Image? image;

  bool get skipped => image == null;
  int get serviceUs => done - started;
  Object get key => (page, width, tile, viewport);
}

/// A [PdfRenderer] that records every render: what, when, how long it
/// waited and ran, and the images it made (alive until disposed).
class CountingRenderer extends PdfRenderer {
  CountingRenderer(super.blobs, {this.skipLiveDuplicates = false});

  /// What-if for the in-flight dedupe fix: answer null (the cache then
  /// keeps what it has) instead of rendering a key whose image is alive.
  final bool skipLiveDuplicates;

  bool _isLive(Object key) =>
      records.any((r) => r.key == key && r.image != null && !r.image!.debugDisposed);

  final Stopwatch clock = Stopwatch()..start();
  final List<RenderRecord> records = [];

  int get _now => clock.elapsedMicroseconds;

  @override
  Future<ui.Image?> render(
    String sha,
    int index,
    int pixelWidth, {
    bool Function()? stillWanted,
    void Function()? released,
  }) {
    final r = RenderRecord(index, pixelWidth)..asked = _now;
    if (skipLiveDuplicates && _isLive(r.key)) return Future.value();
    records.add(r);
    return super
        .render(
          sha,
          index,
          pixelWidth,
          stillWanted: () {
            r.started = _now;
            return stillWanted?.call() ?? true;
          },
          released: released,
        )
        .then((image) {
          r
            ..done = _now
            ..image = image;
          return image;
        });
  }

  @override
  Future<ui.Image?> renderArea(
    String sha,
    int index, {
    required int fullWidth,
    required int fullHeight,
    required int x,
    required int y,
    required int width,
    required int height,
    bool Function()? stillWanted,
    void Function()? released,
  }) {
    const t = PdfTiling.tileSize;
    final isTile = x % t == 0 && y % t == 0 && width <= t && height <= t;
    final r = RenderRecord(
      index,
      fullWidth,
      tile: isTile ? (x ~/ t, y ~/ t) : null,
      viewport: isTile ? null : (x, y, width, height),
    )..asked = _now;
    if (skipLiveDuplicates && _isLive(r.key)) return Future.value();
    records.add(r);
    return super
        .renderArea(
          sha,
          index,
          fullWidth: fullWidth,
          fullHeight: fullHeight,
          x: x,
          y: y,
          width: width,
          height: height,
          stillWanted: () {
            r.started = _now;
            return stillWanted?.call() ?? true;
          },
          released: released,
        )
        .then((image) {
          r
            ..done = _now
            ..image = image;
          return image;
        });
  }

  /// Whole-page images of [page] still alive (not evicted).
  Iterable<RenderRecord> liveWhole(int page) => records.where(
    (r) =>
        r.page == page &&
        r.tile == null &&
        r.viewport == null &&
        r.image != null &&
        !r.image!.debugDisposed,
  );

  /// Bytes of the images still alive (what the cache holds).
  int get liveBytes => records
      .where((r) => r.image != null && !r.image!.debugDisposed)
      .fold(0, (s, r) => s + r.image!.width * r.image!.height * 4);

  /// Images still alive that the cache no longer holds: a newer render of
  /// the same key replaced them in its map without disposing them (they
  /// live until the GC finalises them), with their bytes.
  ({int count, int bytes}) get orphans {
    final newest = <Object, RenderRecord>{};
    for (final r in records.where((r) => !r.skipped)) {
      newest[r.key] = r;
    }
    var count = 0, bytes = 0;
    for (final r in records) {
      final image = r.image;
      if (image == null || image.debugDisposed || identical(newest[r.key], r)) continue;
      count++;
      bytes += image.width * image.height * 4;
    }
    return (count: count, bytes: bytes);
  }

  /// How long the first `open` took (µs; PDFium opens and measures every
  /// page), and when it was asked (µs on [clock]).
  int? firstOpenUs, firstOpenAt;

  @override
  Future<PdfDocument> open(String sha) {
    if (firstOpenAt != null) return super.open(sha);
    firstOpenAt = _now;
    final w = Stopwatch()..start();
    return super.open(sha).then((d) {
      firstOpenUs = w.elapsedMicroseconds;
      return d;
    });
  }

  /// Renders of the same key done more than once (re-rendered after an
  /// eviction, or asked twice).
  int get duplicates {
    final seen = <Object>{};
    var n = 0;
    for (final r in records.where((r) => !r.skipped)) {
      if (!seen.add(r.key)) n++;
    }
    return n;
  }
}

/// What a frame showed of a page.
enum Shown { sharp, fallback, blank }

/// Classifies how [page] painted at [pixelWidth] (whole pages only).
Shown shownOf(CountingRenderer r, int page, double pixelWidth, {int max = 2048}) {
  final want = PdfBackgroundCache.bucketFor(pixelWidth, max: max);
  final live = r.liveWhole(page).toList();
  if (live.any((x) => x.width >= want)) return Shown.sharp;
  return live.isEmpty ? Shown.blank : Shown.fallback;
}

/// A stack of [count] pages of [size] (world units) with [gap] between,
/// as the paged editor lays them out.
class PageStack {
  PageStack(this.count, this.size, {this.gap = 24});
  final int count;
  final ui.Size size;
  final double gap;

  double topOf(int i) => i * (size.height + gap);
  ui.Rect frameOf(int i) => ui.Offset(0, topOf(i)) & size;

  Iterable<int> visible(ui.Rect world) sync* {
    for (var i = 0; i < count; i++) {
      if (frameOf(i).overlaps(world)) yield i;
    }
  }
}

/// Paints the visible pages of [stack] through [cache] like
/// `DocumentPaperPainter` does: [world] is the visible area (world
/// units), [ppu] device pixels per world unit.
void paintFrame(
  PdfBackgroundCache cache,
  PageStack stack,
  List<PageBackground> backgrounds,
  ui.Rect world,
  double ppu, {
  bool prefetch = true,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final shown = stack.visible(world).toList();
  final ranks = centralRanks([for (final i in shown) stack.frameOf(i)], world);
  for (final (k, i) in shown.indexed) {
    final frame = stack.frameOf(i);
    canvas
      ..save()
      ..scale(ppu)
      ..translate(frame.left - world.left, frame.top - world.top);
    cache.paint(
      canvas,
      backgrounds[i],
      stack.size,
      world.shift(-frame.topLeft).intersect(ui.Offset.zero & stack.size),
      ppu,
      rank: ranks[k],
    );
    canvas.restore();
  }
  // As the painter does: the pages just outside the view.
  if (prefetch && shown.isNotEmpty) {
    for (final (i, after) in [(shown.last + 1, true), (shown.first - 1, false)]) {
      if (i >= 0 && i < stack.count && i < backgrounds.length) {
        cache.prefetch(backgrounds[i], stack.size, ppu, after: after);
      }
    }
  }
  recorder.endRecording().dispose();
}

/// Stats of a list of numbers.
String stats(List<num> xs, {String unit = 'ms'}) {
  if (xs.isEmpty) return 'n=0';
  final s = [...xs]..sort();
  num at(double q) => s[math.min(s.length - 1, (q * s.length).floor())];
  String f(num v) => v is double ? v.toStringAsFixed(1) : '$v';
  return 'n=${s.length} min ${f(s.first)} p50 ${f(at(0.5))} p90 ${f(at(0.9))} '
      'max ${f(s.last)} $unit';
}

/// Peak resident set size sampler (MB).
class RssPeak {
  RssPeak() {
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => sample());
  }
  late final Timer _timer;
  int peak = ProcessInfo.currentRss;
  final int start = ProcessInfo.currentRss;
  void sample() => peak = math.max(peak, ProcessInfo.currentRss);
  int get deltaMb => (peak - start) >> 20;
  void stop() => _timer.cancel();
}

/// The longest gaps between event-loop turns while it runs (ms): what
/// blocked the UI isolate.
class TurnProbe {
  TurnProbe() {
    _tick();
  }
  final List<int> turns = [];
  final Stopwatch _w = Stopwatch()..start();
  bool _stopped = false;
  void _tick() {
    if (_stopped) return;
    turns.add(_w.elapsedMilliseconds);
    _w.reset();
    Timer.run(_tick);
  }

  void stop() => _stopped = true;
  int get longest => turns.fold(0, math.max);
  int over(int ms) => turns.where((t) => t > ms).length;
}
