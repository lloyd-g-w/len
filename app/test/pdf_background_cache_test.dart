import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/features/documents/pdf/pdf_background_cache.dart';
import 'package:len/features/documents/pdf/pdf_renderer.dart';
import 'package:len/features/documents/pdf/pdf_tiles.dart';

const a4 = Size(794, 1123);

/// One render the cache asked [_FakeRenderer] for.
class _Render {
  _Render(this.page, this.width, {this.tile = false});
  final int page;
  final int width;
  final bool tile;
  final done = Completer<ui.Image?>();
  ui.Image? image;
}

/// A renderer that makes blank images of the asked size, either at once or
/// when the test completes them ([hold]), and remembers every image it
/// made, so the test can tell which ones were disposed.
class _FakeRenderer extends PdfRenderer {
  _FakeRenderer(super.blobs, {this.hold = false});

  final bool hold;
  final renders = <_Render>[];

  Iterable<ui.Image> get images => [for (final r in renders) ?r.image];
  Iterable<ui.Image> get live => images.where((i) => !i.debugDisposed);
  int get liveBytes => live.fold(0, (s, i) => s + i.width * i.height * 4);

  Future<ui.Image?> _make(_Render r, int width, int height) {
    renders.add(r);
    Future<void> finish() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder);
      final picture = recorder.endRecording();
      r.image = picture.toImageSync(width, height);
      picture.dispose();
      r.done.complete(r.image);
    }

    if (!hold) unawaited(finish());
    _finishers[r] = finish;
    return r.done.future;
  }

  final _finishers = <_Render, Future<void> Function()>{};

  /// Finishes the held renders.
  Future<void> release() async {
    for (final r in renders.where((r) => !r.done.isCompleted).toList()) {
      await _finishers[r]!();
    }
  }

  @override
  Future<ui.Image?> render(String sha, int index, int pixelWidth, {bool Function()? stillWanted}) =>
      _make(_Render(index, pixelWidth), pixelWidth, (pixelWidth * a4.height / a4.width).round());

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
  }) => _make(_Render(index, fullWidth, tile: true), width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppServices services;
  late String sha;

  setUp(() async {
    services = AppServices.create(AppDatabase.inMemory());
    sha = await services.blobs.putBytes(Uint8List(8), mime: 'application/pdf');
  });
  tearDown(() => services.dispose());

  PdfBackgroundCache cacheOver(
    _FakeRenderer renderer, {
    int budget = 160 << 20,
    bool owned = true,
  }) {
    final cache = PdfBackgroundCache(
      blobs: services.blobs,
      fetch: (_) async => true,
      renderer: renderer,
      budgetBytes: budget,
    );
    if (owned) addTearDown(cache.dispose);
    return cache;
  }

  PageBackground page(int i) => PageBackground.pdf(blob: sha, pageIndex: i);

  void paint(PdfBackgroundCache cache, int index, Rect visible, double ppu) {
    final recorder = ui.PictureRecorder();
    cache.paint(Canvas(recorder), page(index), a4, visible, ppu);
    recorder.endRecording().dispose();
  }

  Future<void> settle(PdfBackgroundCache cache) async {
    for (var i = 0; i < 1000 && cache.isBusy; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a page or tile being rendered is rendered once, however often it is painted', () async {
    final renderer = _FakeRenderer(services.blobs, hold: true);
    final cache = cacheOver(renderer);
    // Zoomed in: the whole page (2048) and the tiles in view.
    const ppu = 6.0;
    const visible = Rect.fromLTWH(200, 300, 260, 400);
    for (var frame = 0; frame < 30; frame++) {
      paint(cache, 0, visible, ppu);
      await Future<void>.delayed(Duration.zero);
      if (frame % 5 == 4) {
        // One render lands now and then: the cache notifies and is painted again.
        final pending = renderer.renders.where((r) => !r.done.isCompleted).firstOrNull;
        if (pending != null) await renderer._finishers[pending]!();
      }
    }
    for (var i = 0; i < 50 && cache.isBusy; i++) {
      await renderer.release();
      paint(cache, 0, visible, ppu);
      await Future<void>.delayed(Duration.zero);
    }
    await settle(cache);
    final keys = [for (final r in renderer.renders) (r.page, r.width, r.tile, r.image?.width)];
    expect(renderer.renders.where((r) => !r.tile), hasLength(1));
    expect(renderer.renders.where((r) => r.tile), isNotEmpty);
    // No key twice (tiles of one level differ by their position, so compare counts).
    final tiles = renderer.renders.where((r) => r.tile).length;
    final range = PdfTiling.range(a4, visible, PdfTiling.levelFor(a4.width * ppu))!;
    final inView = (range.col1 - range.col0 + 1) * (range.row1 - range.row0 + 1);
    expect(tiles, lessThanOrEqualTo(inView), reason: '$keys');
    // Every image made is the cache's: none is replaced and left alive.
    expect(renderer.live.length, renderer.renders.length);
  });

  test('evicted images are disposed; dispose frees the rest', () async {
    final renderer = _FakeRenderer(services.blobs);
    // Pages 362 px wide (≈ 0.74 MB each), a 3 MB budget.
    final cache = cacheOver(renderer, budget: 3 << 20, owned: false);
    const ppu = 362 / 794;
    for (var i = 0; i < 12; i++) {
      paint(cache, i, Offset.zero & a4, ppu);
      await settle(cache);
    }
    expect(renderer.renders, hasLength(12));
    final disposed = renderer.images.where((i) => i.debugDisposed).length;
    expect(disposed, greaterThanOrEqualTo(8));
    expect(renderer.liveBytes, lessThanOrEqualTo(3 << 20));
    expect(cache.debugImageBytes, renderer.liveBytes);
    // The most recent pages are the ones kept.
    expect(renderer.renders.last.image!.debugDisposed, isFalse);
    expect(renderer.renders.first.image!.debugDisposed, isTrue);
    cache.dispose();
    expect(renderer.live, isEmpty);
  });

  test('a 100-page scroll keeps the live image bytes within the budget', () async {
    final renderer = _FakeRenderer(services.blobs);
    const budget = 8 << 20; // 5 pages 512 px wide (1.5 MB each).
    final cache = cacheOver(renderer, budget: budget);
    // A desktop column 400 px wide: about 1.4 pages in view.
    const ppu = 400 / 794;
    const viewHeight = 800 / ppu;
    const pitch = 1123 + 24.0;
    var peak = 0;
    for (var top = 0.0; top < 100 * pitch; top += pitch / 6) {
      for (var i = (top / pitch).floor(); i * pitch < top + viewHeight; i++) {
        final frameTop = i * pitch;
        final visible = Rect.fromLTWH(
          0,
          top - frameTop,
          a4.width,
          viewHeight,
        ).intersect(Offset.zero & a4);
        if (!visible.isEmpty) paint(cache, i, visible, ppu);
      }
      await Future<void>.delayed(Duration.zero);
      peak = math.max(peak, renderer.liveBytes);
    }
    await settle(cache);
    expect(renderer.renders.length, inInclusiveRange(100, 102));
    expect(peak, lessThanOrEqualTo(budget));
    expect(renderer.liveBytes, cache.debugImageBytes);
  });
}
