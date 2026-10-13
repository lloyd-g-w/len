import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../data/blob_store.dart';
import '../../../domain/notebook_page.dart';
import '../../editor/document/missing_pdf_painter.dart';
import '../../editor/document/page_backgrounds.dart';
import 'pdf_renderer.dart';
import 'pdf_tiles.dart';

/// A whole page rendered [width] pixels wide.
typedef _PageImage = ({PageBackground background, int width});

/// Renders PDF page backgrounds on demand, at a resolution matching the
/// current zoom, and caches the results (least recently used first out).
///
/// Whole pages are rendered up to [PdfTiling.wholePageMax] pixels wide, at
/// widths quantised to steps of √2, so zooming re-renders a page only a few
/// times. Deeper zoom renders just the visible tiles of the page
/// ([PdfTiling]); until they arrive, the best whole-page image and any
/// cached tiles of neighbouring levels are shown, so zooming stays smooth.
///
/// Renders run one at a time on PDFium's worker (never on the UI thread),
/// newest request first: whole pages before tiles, and the tiles in the
/// middle of the view before those at its edges. Requests that no paint
/// repeated for [staleAfter] are dropped. Blobs not yet on this device are
/// fetched through [fetch].
class PdfBackgroundCache extends ChangeNotifier implements PageBackgrounds {
  PdfBackgroundCache({
    required this.blobs,
    required this.fetch,
    PdfRenderer? renderer,
    this.budgetBytes = 160 << 20,
  }) : _renderer = renderer ?? PdfRenderer(blobs);

  final BlobStore blobs;

  /// Downloads a blob; returns whether it is available now.
  final Future<bool> Function(String sha) fetch;

  /// Memory budget for cached images (4 bytes per pixel).
  final int budgetBytes;

  /// How long a request waits for a paint to repeat it before it is dropped.
  static const staleAfter = Duration(seconds: 2);

  final PdfRenderer _renderer;

  /// The renderer, whose open documents the editor also reads text and
  /// links from.
  PdfRenderer get renderer => _renderer;

  /// Page images and tiles, least recently used first.
  final LinkedHashMap<Object, ui.Image> _images = LinkedHashMap();

  /// Pending requests with the time they were last made, oldest first.
  final LinkedHashMap<Object, int> _queue = LinkedHashMap();
  final Stopwatch _clock = Stopwatch()..start();
  bool _working = false;
  final Set<String> _fetching = {};
  final Set<String> _missing = {};
  bool _disposed = false;

  static const int minWidth = 256;
  static const int maxWidth = PdfTiling.wholePageMax;

  /// The rendering width used for a requested [pixelWidth] (whole pages).
  static int bucketFor(double pixelWidth) {
    if (!pixelWidth.isFinite || pixelWidth <= minWidth) return minWidth;
    final steps = (2 * math.log(pixelWidth / minWidth) / math.ln2).ceil();
    return math.min(maxWidth, (minWidth * math.pow(math.sqrt2, steps)).round());
  }

  @override
  ui.Image? imageFor(PageBackground background, double pixelWidth) {
    final key = (background: background, width: bucketFor(pixelWidth));
    final hit = _touch(key);
    if (hit != null) return hit;
    _request(key);
    return _bestFor(background);
  }

  @override
  void paint(
    ui.Canvas canvas,
    PageBackground background,
    ui.Size page,
    ui.Rect visible,
    double pixelsPerUnit,
  ) {
    final pixelWidth = page.width * pixelsPerUnit;
    final base = imageFor(background, math.min(pixelWidth, maxWidth.toDouble()));
    if (base == null && isMissing(background)) {
      paintMissingPdf(canvas, page);
      return;
    }
    if (base != null) _draw(canvas, base, ui.Offset.zero & page, antiAlias: true);
    if (pixelWidth <= maxWidth) return;
    final level = PdfTiling.levelFor(pixelWidth);
    // What is cached meanwhile: coarser levels first, then the finer one.
    for (var width = maxWidth * 2; width <= math.min(level * 2, PdfTiling.maxLevel); width *= 2) {
      if (width != level) _drawTiles(canvas, background, page, visible, width, request: false);
    }
    _drawTiles(canvas, background, page, visible, level, request: true);
  }

  /// Draws the cached tiles of level [width] in [visible]; with [request],
  /// asks for the missing ones (the middle of the view first).
  void _drawTiles(
    ui.Canvas canvas,
    PageBackground background,
    ui.Size page,
    ui.Rect visible,
    int width, {
    required bool request,
  }) {
    final range = PdfTiling.range(page, visible, width);
    if (range == null) return;
    final missing = <PdfTile>[];
    for (var row = range.row0; row <= range.row1; row++) {
      for (var col = range.col0; col <= range.col1; col++) {
        final tile = (background: background, width: width, col: col, row: row);
        final image = request ? _touch(tile) : _images[tile];
        if (image != null) {
          _draw(canvas, image, PdfTiling.rectOf(page, width, col, row));
        } else if (request) {
          missing.add(tile);
        }
      }
    }
    if (missing.isEmpty) return;
    final centre = visible.center;
    double distance(PdfTile t) =>
        (PdfTiling.rectOf(page, width, t.col, t.row).center - centre).distanceSquared;
    missing.sort((a, b) => distance(b).compareTo(distance(a))); // Farthest first…
    for (final tile in missing) {
      _request(tile, page: page); // …so the nearest is the newest request.
    }
  }

  /// Draws [image] into [rect]; tiles without [antiAlias], so neighbours
  /// meet without seams.
  static void _draw(ui.Canvas canvas, ui.Image image, ui.Rect rect, {bool antiAlias = false}) =>
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        ui.Paint()
          ..filterQuality = ui.FilterQuality.medium
          ..isAntiAlias = antiAlias,
      );

  /// How many tiles are cached (for tests).
  @visibleForTesting
  int get debugTileCount => _images.keys.whereType<PdfTile>().length;

  @override
  bool isMissing(PageBackground background) => _missing.contains(background.blob);

  /// The PDFs (blob ids) that couldn't be had so far.
  Set<String> get missingBlobs => Set.unmodifiable(_missing);

  /// Forgets that blobs were unavailable, e.g. after a sync.
  void retryMissing() {
    if (_disposed || _missing.isEmpty) return; // (A relink may finish after the editor closed.)
    _missing.clear();
    notifyListeners();
  }

  ui.Image? _touch(Object key) {
    final hit = _images.remove(key);
    if (hit != null) _images[key] = hit; // Most recently used.
    return hit;
  }

  ui.Image? _bestFor(PageBackground background) {
    ui.Image? best;
    for (final MapEntry(:key, :value) in _images.entries) {
      if (key is! _PageImage || key.background != background) continue;
      if (best == null || value.width > best.width) best = value;
    }
    return best;
  }

  /// Page sizes (units) of tiles waiting to be rendered.
  final Map<PdfTile, ui.Size> _tilePages = {};

  void _request(Object key, {ui.Size? page}) {
    if (_disposed) return;
    _queue.remove(key);
    _queue[key] = _clock.elapsedMilliseconds;
    if (key is PdfTile && page != null) _tilePages[key] = page;
    if (!_working) unawaited(_work());
  }

  /// The next request to serve: the newest whole page, else the newest tile;
  /// stale requests are dropped on the way.
  Object? _next() {
    final now = _clock.elapsedMilliseconds;
    _queue.removeWhere((key, at) {
      final stale = now - at > staleAfter.inMilliseconds;
      if (stale && key is PdfTile) _tilePages.remove(key);
      return stale;
    });
    Object? next;
    for (final key in _queue.keys) {
      if (key is _PageImage) next = key; // The newest whole page…
    }
    next ??= _queue.isEmpty ? null : _queue.keys.last; // …else the newest tile.
    if (next != null) _queue.remove(next);
    return next;
  }

  Future<void> _work() async {
    _working = true;
    try {
      while (!_disposed) {
        final key = _next();
        if (key == null) break;
        await _render(key);
      }
    } finally {
      _working = false;
    }
  }

  Future<void> _render(Object key) async {
    final background = switch (key) {
      final _PageImage p => p.background,
      final PdfTile t => t.background,
      _ => throw ArgumentError(key),
    };
    final sha = background.blob;
    try {
      if (!await blobs.has(sha)) {
        if (_missing.contains(sha) || !_fetching.add(sha)) return;
        final bool ok;
        try {
          ok = await fetch(sha);
        } finally {
          _fetching.remove(sha); // Also when it threw: [retryMissing] retries.
        }
        if (!ok) _missing.add(sha);
        if (!_disposed) notifyListeners(); // Repaint re-requests the image.
        return;
      }
      final image = switch (key) {
        final _PageImage p => await _renderer.render(sha, background.pageIndex, p.width),
        final PdfTile t => await _renderTile(t),
        _ => null,
      };
      if (image == null) return;
      if (_disposed) {
        image.dispose();
        return;
      }
      _images[key] = image;
      _evict();
      notifyListeners();
    } catch (e) {
      debugPrint('Cannot render PDF page ${background.pageIndex} of $sha: $e');
      _missing.add(sha);
      if (!_disposed) notifyListeners(); // Show the placeholder.
    }
  }

  Future<ui.Image?> _renderTile(PdfTile tile) async {
    final page = _tilePages.remove(tile);
    if (page == null) return null;
    final area = PdfTiling.pixels(page, tile.width, tile.col, tile.row);
    return _renderer.renderArea(
      tile.background.blob,
      tile.background.pageIndex,
      fullWidth: tile.width,
      fullHeight: PdfTiling.heightAt(tile.width, page),
      x: area.x,
      y: area.y,
      width: area.width,
      height: area.height,
    );
  }

  void _evict() {
    var bytes = _images.values.fold<int>(0, (sum, i) => sum + i.width * i.height * 4);
    while (bytes > budgetBytes && _images.length > 1) {
      final oldest = _images.keys.first;
      final image = _images.remove(oldest)!;
      bytes -= image.width * image.height * 4;
      image.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _queue.clear();
    _renderer.dispose();
    super.dispose();
  }
}
