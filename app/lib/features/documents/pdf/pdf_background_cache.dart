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
/// widths quantised to steps of √2, so zooming re-renders a page only a few
/// times. Deeper zoom renders just the visible tiles of the page
/// ([PdfTiling]); until they arrive, the best whole-page image and any
/// cached tiles of neighbouring levels are shown, so zooming stays smooth.
///
/// Renders run one at a time on PDFium's worker (never on the UI thread):
/// the pages in view first, the most central one first (the `rank` the
/// painter gives), then thumbnails, then the tiles in view (the middle of
/// the view before its edges), then the pages just outside the view
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
    this.budgetBytes = 160 << 20,
  }) : _renderer = renderer ?? PdfRenderer(blobs);

  final BlobStore blobs;

  /// Downloads a blob; returns whether it is available now.
  final Future<bool> Function(String sha) fetch;

  /// Told when [fetch] brought a blob (what else read the PDF while it was
  /// missing, its text and links, may read it again).
  final void Function(String sha)? onFetched;

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
  final Set<String> _fetching = {};
  final Set<String> _missing = {};
  bool _disposed = false;

  static const int minWidth = 256;
  static const int maxWidth = PdfTiling.wholePageMax;

  /// The rendering width used for a requested [pixelWidth] (whole pages),
  /// at most [max].
  static int bucketFor(double pixelWidth, {int max = maxWidth}) {
    if (!pixelWidth.isFinite || pixelWidth <= minWidth) return math.min(minWidth, max);
    final steps = (2 * math.log(pixelWidth / minWidth) / math.ln2).ceil();
    return math.min(max, (minWidth * math.pow(math.sqrt2, steps)).round());
  }

  /// Rank of thumbnails ([imageFor]): after the pages painted in view.
  static const _thumbnailRank = 1 << 20;

  @override
  ui.Image? imageFor(PageBackground background, double pixelWidth) =>
      _imageFor(background, pixelWidth, maxWidth, _thumbnailRank);

  ui.Image? _imageFor(PageBackground background, double pixelWidth, int max, int rank) {
    final key = (background: background, width: bucketFor(pixelWidth, max: max));
    final hit = _touch(key);
    if (hit != null) return hit;
    _request(key, tier: _PdfBackgroundQueue.painted, rank: rank);
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
    if (_touch(key) != null) return; // Kept: it is about to be shown.
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
      // …so the nearest is the newest request.
      _request(tile, page: page, tier: _PdfBackgroundQueue.tile);
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

  /// Whether renders (or downloads) are queued or running (for tests).
  @visibleForTesting
  bool get isBusy => _working || _queue.isNotEmpty;

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

  /// Page sizes (units) of tiles waiting to be rendered.
  final Map<PdfTile, ui.Size> _tilePages = {};

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
        if (_disposed) return;
        if (ok) onFetched?.call(sha);
        notifyListeners(); // Repaint re-requests the image.
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
    _renderer.dispose();
    super.dispose();
  }
}
