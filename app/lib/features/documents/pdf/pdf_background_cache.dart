import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../data/blob_store.dart';
import '../../../domain/notebook_page.dart';
import '../../../platform/physical_memory.dart';
import '../../editor/document/missing_pdf_painter.dart';
import '../../editor/document/page_backgrounds.dart';
import 'pdf_renderer.dart';
import 'pdf_tiles.dart';

part 'pdf_background_queue.dart';

/// A whole page rendered [width] pixels wide.
typedef _PageImage = ({PageBackground background, int width});

/// A queued render: when it was last asked for ([at], ms) and in which
/// [frame], its [tier] ([_PdfBackgroundQueue.painted], `tile`, `ahead`) and
/// its [rank] within the tier (lower first).
typedef _Pending = ({int at, int frame, int tier, int rank});

/// Renders PDF page backgrounds on demand, at a resolution matching the
/// current zoom, and caches the results (least recently used first out).
///
/// Whole pages are rendered up to [PdfTiling.wholePageWidth] pixels wide, at
/// widths quantised to steps of 2^¼ ([bucketFor]; an image up to √2 wider
/// is reused), so zooming re-renders a page only a few times. Deeper zoom
/// renders the view in one call ([PdfViewport], sharp soon after a pinch
/// settles) and the visible tiles of the page ([PdfTiling], for panning);
/// until they arrive, the best whole-page image and any cached tiles of
/// neighbouring levels are shown, so zooming stays smooth.
///
/// Renders run one at a time on PDFium's worker (never on the UI thread):
/// the pages in view first, the most central one first (the `rank` the
/// painter gives), then thumbnails, then viewport renders, then the tiles
/// in view (the middle of the view before its edges), then the pages just
/// outside the view
/// ([prefetch]; the side the view moves to first). A request for an image
/// being rendered joins that render. Requests that no paint repeated for
/// [staleAfter] are dropped, prefetches as soon as a frame no longer asks
/// for them. Blobs not yet on this device are fetched through [fetch].
class PdfBackgroundCache extends ChangeNotifier implements PageBackgrounds {
  PdfBackgroundCache({
    required this.blobs,
    required this.fetch,
    this.onFetched,
    PdfRenderer? renderer,
    int? budgetBytes,
  }) : budgetBytes = budgetBytes ?? defaultBudget,
       _renderer = renderer ?? PdfRenderer(blobs);

  final BlobStore blobs;

  /// Downloads a blob; returns whether it is available now.
  final Future<bool> Function(String sha) fetch;

  /// Told when [fetch] brought a blob (what else read the PDF while it was
  /// missing, its text and links, may read it again).
  final void Function(String sha)? onFetched;

  /// Memory budget for cached images (4 bytes per pixel).
  final int budgetBytes;

  /// The default [budgetBytes]: 1/32 of the device's memory (256 MB on an
  /// 8 GB tablet: ten pages 1722 px wide, or 60 tiles), at least 160 MB
  /// (a screen of tiles and the pages around it) and at most 512 MB.
  static int get defaultBudget => budgetFor(physicalMemoryBytes);

  /// [defaultBudget] for a device with [physicalBytes] of memory (null:
  /// unknown).
  static int budgetFor(int? physicalBytes) =>
      ((physicalBytes ?? 0) ~/ 32).clamp(minBudget, maxBudget);

  static const int minBudget = 160 << 20;
  static const int maxBudget = 512 << 20;

  /// How long a request waits for a paint to repeat it before it is dropped.
  static const staleAfter = Duration(seconds: 2);

  final PdfRenderer _renderer;

  /// The renderer, whose open documents the editor also reads text and
  /// links from.
  PdfRenderer get renderer => _renderer;

  /// Page images and tiles, least recently used first.
  final LinkedHashMap<Object, ui.Image> _images = LinkedHashMap();

  /// Pending requests, oldest first.
  final LinkedHashMap<Object, _Pending> _queue = LinkedHashMap();

  /// Frames painted so far ([beginFrame]).
  int _frame = 0;

  /// The page painted at rank 0 last, where its visible part was, and
  /// whether the view last moved towards later pages.
  PageBackground? _lead;
  ui.Offset? _leadCentre;
  bool _forward = true;

  /// The request being rendered (or its blob fetched): asking for it again
  /// joins it.
  final Set<Object> _inFlight = {};
  final Stopwatch _clock = Stopwatch()..start();
  bool _working = false;

  /// Renders whose images are still being made or stored.
  int _finishing = 0;
  final Set<String> _fetching = {};
  final Set<String> _missing = {};
  bool _disposed = false;

  static const int minWidth = 256;
  static const int maxWidth = PdfTiling.wholePageMax;

  /// Width steps per doubling: 2^¼ ≈ 1.19× apart (256, 304, 362, 431,
  /// 512, … 1448, 1722, 2048), so a page is rendered at most 19% wider than
  /// shown (a 1600-px tablet page renders at 1722, not 2048).
  static const int stepsPerDoubling = 4;

  /// How much wider than needed a cached page may be and still be used
  /// (no new render): zooming out by up to this much reuses it.
  static const double reuseUpTo = math.sqrt2;

  /// The rendering width used for a requested [pixelWidth] (whole pages),
  /// at most [max].
  static int bucketFor(double pixelWidth, {int max = maxWidth}) {
    if (!pixelWidth.isFinite || pixelWidth <= minWidth) return math.min(minWidth, max);
    // Less a hair, so a width on a step (1024) is that step.
    final steps = (stepsPerDoubling * math.log(pixelWidth / minWidth) / math.ln2 - 1e-9).ceil();
    return math.min(max, (minWidth * math.pow(2, steps / stepsPerDoubling)).round());
  }

  /// Rank of thumbnails ([imageFor]): after the pages painted in view.
  static const _thumbnailRank = 1 << 20;

  @override
  ui.Image? imageFor(PageBackground background, double pixelWidth) =>
      _imageFor(background, pixelWidth, maxWidth, _thumbnailRank);

  ui.Image? _imageFor(PageBackground background, double pixelWidth, int max, int rank) {
    final key = (background: background, width: bucketFor(pixelWidth, max: max));
    final hit = _touch(key) ?? _wideEnough(key);
    if (hit != null) return hit;
    if (!_renderingWideEnough(key)) _request(key, tier: _PdfBackgroundQueue.painted, rank: rank);
    return _bestFor(background);
  }

  /// Starts a frame: the pages prefetched for the previous one that this
  /// one doesn't ask for again are dropped. A paint at rank 0 calls it.
  void beginFrame() {
    _frame++;
    _queue.removeWhere((_, p) => p.tier == _PdfBackgroundQueue.ahead);
  }

  @override
  void prefetch(
    PageBackground background,
    ui.Size page,
    double pixelsPerUnit, {
    required bool after,
  }) {
    if (_disposed || isMissing(background)) return;
    final width = bucketFor(page.width * pixelsPerUnit, max: PdfTiling.wholePageWidth(page));
    final key = (background: background, width: width);
    // Kept: it is about to be shown.
    if (_touch(key) != null || _wideEnough(key) != null || _renderingWideEnough(key)) return;
    _request(key, tier: _PdfBackgroundQueue.ahead, rank: after == _forward ? 0 : 1);
  }

  /// Follows which way the view moves from where the [visible] part of the
  /// page at rank 0 goes (or which page is at rank 0).
  void _track(PageBackground background, ui.Rect visible) {
    final centre = visible.center, lead = _lead, before = _leadCentre;
    if (lead == background && before != null) {
      final moved = (centre.dx - before.dx) + (centre.dy - before.dy);
      if (moved.abs() > 1e-6) _forward = moved > 0;
    } else if (lead != null && lead.blob == background.blob) {
      _forward = background.pageIndex > lead.pageIndex;
    }
    _lead = background;
    _leadCentre = centre;
  }

  @override
  void paint(
    ui.Canvas canvas,
    PageBackground background,
    ui.Size page,
    ui.Rect visible,
    double pixelsPerUnit, {
    int rank = 0,
  }) {
    if (rank == 0) {
      beginFrame();
      _track(background, visible);
    }
    final pixelWidth = page.width * pixelsPerUnit;
    final whole = PdfTiling.wholePageWidth(page);
    final base = _imageFor(background, pixelWidth, whole, rank);
    if (base == null && isMissing(background)) {
      paintMissingPdf(canvas, page);
      return;
    }
    if (base != null) _draw(canvas, base, ui.Offset.zero & page, antiAlias: true);
    if (pixelWidth <= whole) return;
    final level = PdfTiling.levelFor(pixelWidth, above: whole);
    // What is cached meanwhile: coarser levels first, then the finer one.
    for (
      var width = PdfTiling.levelFor(0, above: whole);
      width <= math.min(level * 2, PdfTiling.maxLevel);
      width *= 2
    ) {
      if (width != level) _drawTiles(canvas, background, page, visible, width, request: false);
    }
    final viewport = _viewportOf(background);
    final viewportImage = viewport == null ? null : _touch(viewport);
    // Under the tiles: they cover it as they come (PDFium's area renders
    // can differ from the tiles' by a fraction of a pixel at the edges).
    if (viewportImage != null) {
      _draw(canvas, viewportImage, PdfTiling.viewportRect(page, viewport!));
    }
    final complete = _drawTiles(canvas, background, page, visible, level, request: true);
    if (!complete) _requestViewport(background, page, visible, level, viewport, rank);
  }

  /// The viewport each page's last paint wanted.
  final Map<PageBackground, PdfViewport> _viewportAsked = {};

  /// The viewport render of [background] cached (one per page at most).
  PdfViewport? _viewportOf(PageBackground background) {
    for (final key in _images.keys) {
      if (key is PdfViewport && key.background == background) return key;
    }
    return null;
  }

  /// Asks for one render of [visible] (and a margin) at level [width],
  /// unless [cached] already covers it: sharp in one PDFium call while the
  /// tiles under it fill in. Replaces the page's earlier viewport request,
  /// so during a pinch only the latest view waits.
  void _requestViewport(
    PageBackground background,
    ui.Size page,
    ui.Rect visible,
    int width,
    PdfViewport? cached,
    int rank,
  ) {
    if (cached != null && cached.width == width) {
      final need = PdfTiling.viewportPixels(page, visible, width, margin: false);
      if (need == null ||
          need.x >= cached.x &&
              need.y >= cached.y &&
              need.x + need.w <= cached.x + cached.w &&
              need.y + need.h <= cached.y + cached.h) {
        return;
      }
    }
    final p = PdfTiling.viewportPixels(page, visible, width);
    if (p == null || p.w * p.h * 4 > PdfTiling.viewportMaxBytes) return;
    final PdfViewport key = (background: background, width: width, x: p.x, y: p.y, w: p.w, h: p.h);
    // Only once the view holds still for a frame: during a pinch each
    // frame's view is different, and rendering them would delay the last.
    final steady = _viewportAsked[background] == key;
    _viewportAsked[background] = key;
    if (!steady || _inFlight.contains(key)) return;
    _queue.removeWhere((k, _) {
      final drop = k is PdfViewport && k.background == background && k != key;
      if (drop) _tilePages.remove(k);
      return drop;
    });
    _request(key, page: page, tier: _PdfBackgroundQueue.viewport, rank: rank);
  }

  /// Whether the [visible] part of [background] (a page of [page] units
  /// shown [pixelsPerUnit]) is drawn at full sharpness: by the whole-page
  /// image or, zoomed in, by a viewport render or all the tiles (for
  /// tests and benchmarks).
  @visibleForTesting
  bool debugIsSharp(
    PageBackground background,
    ui.Size page,
    ui.Rect visible,
    double pixelsPerUnit,
  ) {
    final pixelWidth = page.width * pixelsPerUnit;
    final whole = PdfTiling.wholePageWidth(page);
    if (pixelWidth <= whole) {
      final width = bucketFor(pixelWidth, max: whole);
      return _images.keys.any(
        (k) => k is _PageImage && k.background == background && k.width >= width,
      );
    }
    final level = PdfTiling.levelFor(pixelWidth, above: whole);
    final v = _viewportOf(background);
    final need = PdfTiling.viewportPixels(page, visible, level, margin: false);
    if (need == null) return true;
    if (v != null &&
        v.width == level &&
        need.x >= v.x &&
        need.y >= v.y &&
        need.x + need.w <= v.x + v.w &&
        need.y + need.h <= v.y + v.h) {
      return true;
    }
    final range = PdfTiling.range(page, visible, level)!;
    for (var row = range.row0; row <= range.row1; row++) {
      for (var col = range.col0; col <= range.col1; col++) {
        if (!_images.containsKey((background: background, width: level, col: col, row: row))) {
          return false;
        }
      }
    }
    return true;
  }

  /// Draws the cached tiles of level [width] in [visible]; with [request],
  /// asks for the missing ones (the middle of the view first). Whether
  /// none was missing.
  bool _drawTiles(
    ui.Canvas canvas,
    PageBackground background,
    ui.Size page,
    ui.Rect visible,
    int width, {
    required bool request,
  }) {
    final range = PdfTiling.range(page, visible, width);
    if (range == null) return true;
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
    if (missing.isEmpty) return true;
    final centre = visible.center;
    double distance(PdfTile t) =>
        (PdfTiling.rectOf(page, width, t.col, t.row).center - centre).distanceSquared;
    missing.sort((a, b) => distance(b).compareTo(distance(a))); // Farthest first…
    for (final tile in missing) {
      // …so the nearest is the newest request.
      _request(tile, page: page, tier: _PdfBackgroundQueue.tile);
    }
    return false;
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

  /// Whether renders (or downloads) are queued or running (for tests).
  @visibleForTesting
  bool get isBusy => _working || _finishing > 0 || _queue.isNotEmpty;

  /// Bytes of the images cached (4 per pixel; for tests).
  @visibleForTesting
  int get debugImageBytes => _images.values.fold(0, (sum, i) => sum + i.width * i.height * 4);

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

  /// Page sizes (units) of tiles and viewports waiting to be rendered.
  final Map<Object, ui.Size> _tilePages = {};

  /// Renders [key]; calls [released] once the renderer can start the next.
  Future<void> _render(Object key, void Function() released) async {
    final background = switch (key) {
      final _PageImage p => p.background,
      final PdfTile t => t.background,
      final PdfViewport v => v.background,
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
        if (_disposed) return;
        if (ok) onFetched?.call(sha);
        notifyListeners(); // Repaint re-requests the image.
        return;
      }
      final image = switch (key) {
        final _PageImage p => await _renderer.render(
          sha,
          background.pageIndex,
          p.width,
          released: released,
        ),
        final PdfTile t => await _renderTile(t, released),
        final PdfViewport v => await _renderViewport(v, released),
        _ => null,
      };
      if (image == null) return;
      if (_disposed) {
        image.dispose();
        return;
      }
      _store(key, image);
      notifyListeners();
    } catch (e) {
      debugPrint('Cannot render PDF page ${background.pageIndex} of $sha: $e');
      _missing.add(sha);
      if (!_disposed) notifyListeners(); // Show the placeholder.
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
    _viewportAsked.clear();
    _renderer.dispose();
    super.dispose();
  }
}
