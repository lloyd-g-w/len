import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/surface_copier.dart';
import '../../../domain/image_data.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/fonts/text_fonts.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/render/content_painter.dart';
import '../../../ink/render/raster_batch.dart';

/// Recorded ink, text and images of pages for thumbnails, loaded on first
/// use, and rasterised at the size they are shown ([rasterOf]): a frame of
/// the page overview draws images, not every outline of every page.
/// Notifies when a page's picture was dropped because one of its images
/// finished decoding (it is then recorded again, sharper) and when a
/// raster is ready.
class ThumbnailCache extends ChangeNotifier {
  ThumbnailCache(this.copier, {this.images, this.defer, RasterBatch? batch})
    : batch = batch ?? RasterBatch.shared {
    _imageChanges = images?.changes.listen(_onImage);
    defer?.addListener(_deferChanged);
    TextFonts.changes.addListener(_onFonts);
  }

  final SurfaceCopier copier;

  /// Makes the rasters (in the JavaScript build, many to an atlas).
  final RasterBatch batch;

  /// While true (the grid scrolls fast), nothing is recorded or
  /// rasterised: pages wait in the queue, those scrolled past leave it
  /// ([hidden]), and the ones on screen are recorded once it turns false.
  final ValueListenable<bool>? defer;

  bool get _deferring => defer?.value ?? false;

  /// Pages recorded so far (for benchmarks and tests).
  @visibleForTesting
  int recordings = 0;

  /// Whether [pageId]'s picture is there (for benchmarks and tests; unlike
  /// [inkOf], asks for nothing).
  @visibleForTesting
  bool isRecorded(String pageId) => _ink.containsKey(pageId);

  /// Decoded bitmaps for image elements.
  final ElementImages? images;

  /// Device pixels per page unit images are decoded for (thumbnails are a
  /// few hundred pixels wide).
  static const double imageScale = 0.75;

  /// Recorded pages, least recently used first (at most [maxPages]).
  final Map<String, ui.Picture> _ink = {};

  /// Pages to record (again), in the order they were asked for.
  final Set<String> _queue = {};
  Timer? _loading;
  bool _disposed = false;

  /// Ink narrower than this many pixels at [imageScale] (the regular pens,
  /// under 3.3 units) is drawn as plain lines: thumbnails show it at most
  /// that wide.
  static const double sketchBelow = 2.5;

  /// How many pages' pictures are kept.
  static const int maxPages = 160;

  /// Time spent recording pages between frames.
  static const Duration frameBudget = Duration(milliseconds: 6);

  /// Image blobs drawn into each page's picture.
  final Map<String, Set<String>> _blobs = {};
  StreamSubscription<String>? _imageChanges;

  /// The page's content as a picture in page units; null until it is
  /// recorded. Pages are read from the database between frames, a few at
  /// a time (listeners hear when more are ready), so scrolling through a
  /// long notebook never stalls on the queries.
  ui.Picture? inkOf(String pageId) {
    final picture = _ink.remove(pageId);
    if (picture != null) _ink[pageId] = picture; // Most recently used.
    if (picture == null) _enqueue(pageId);
    return picture;
  }

  /// Records a page's picture again after it changed (the old one shows
  /// meanwhile).
  void invalidate(String pageId) {
    _blobs.remove(pageId);
    if (_ink.containsKey(pageId)) _enqueue(pageId);
  }

  /// The page changed while thumbnails stay open (a page sidebar beside
  /// the page being written on): recorded again if a thumbnail shows it
  /// (the old picture stands in meanwhile), else forgotten, to be recorded
  /// when it shows again.
  void changed(String pageId) {
    if (_showing.containsKey(pageId)) return invalidate(pageId);
    _queue.remove(pageId);
    _blobs.remove(pageId);
    _ink.remove(pageId)?.dispose();
    _dropRaster(pageId);
  }

  /// How many thumbnails show each page ([shown] / [hidden]).
  final Map<String, int> _showing = {};

  /// A thumbnail of [pageId] is on screen (until [hidden]).
  void shown(String pageId) => _showing.update(pageId, (n) => n + 1, ifAbsent: () => 1);

  /// A thumbnail of [pageId] is gone. When none is left, the page is no
  /// longer recorded if it still waits: scrolling fast through a long
  /// notebook records only the pages it stops at.
  void hidden(String pageId) {
    final n = (_showing[pageId] ?? 1) - 1;
    if (n > 0) {
      _showing[pageId] = n;
    } else {
      _showing.remove(pageId);
      _queue.remove(pageId);
    }
  }

  void _enqueue(String pageId) {
    _queue.add(pageId);
    if (!_deferring) _loading ??= Timer(Duration.zero, _loadSome);
  }

  void _deferChanged() {
    if (_disposed || _deferring) return;
    if (_queue.isNotEmpty) _loading ??= Timer(Duration.zero, _loadSome);
    notifyListeners(); // Rasters held back are asked for again.
  }

  void _loadSome() {
    _loading = null;
    if (_disposed || _deferring) return;
    final watch = Stopwatch()..start();
    while (_queue.isNotEmpty && watch.elapsed < frameBudget) {
      final pageId = _queue.first;
      _queue.remove(pageId);
      _ink.remove(pageId)?.dispose();
      _ink[pageId] = _record(pageId);
      recordings++;
    }
    while (_ink.length > maxPages) {
      final oldest = _ink.keys.first;
      _ink.remove(oldest)?.dispose();
      _blobs.remove(oldest);
      _dropRaster(oldest);
    }
    if (_queue.isNotEmpty) _loading = Timer(Duration.zero, _loadSome);
    notifyListeners();
  }

  ui.Picture _record(String pageId) {
    final strokes = copier.loadAll(pageId);
    final elements = copier.loadAllElements(pageId);
    final blobs = {
      for (final e in elements)
        if (e.knownType == ElementType.image && e.data['blob'] is String) e.data['blob']! as String,
    };
    if (blobs.isNotEmpty) _blobs[pageId] = blobs;
    final recorder = ui.PictureRecorder();
    // Thin ink needs no outlines at this size (they take ~0.3 ms per stroke
    // to build, on this thread).
    ContentPainter.paint(
      Canvas(recorder),
      strokes,
      elements,
      images: images,
      pixelScale: imageScale,
      sketchThin: true,
      sketchBelow: sketchBelow,
    );
    return recorder.endRecording();
  }

  /// Rasters of the recorded pages, least recently used first.
  final Map<String, _Raster> _rasters = {};
  int _rasterBytes = 0;
  int _rastering = 0;

  /// Memory the rasters may take.
  static const int maxRasterBytes = 48 << 20;

  /// Rasters being made at once: batched, as many as a screen shows (one
  /// read-back for those sharing an atlas).
  int get _maxRastering => batch.batching ? 32 : 2;

  /// The page's content as an image [width] × [height] pixels, once
  /// rasterised from its picture ([inkOf]), which stands in meanwhile (an
  /// older image stands in after the page changed). Safe while painting:
  /// listeners hear when the raster is ready. A raster of another page
  /// shape (a new PDF under the page) would stretch the content: none
  /// stands in then.
  RasterImage? rasterOf(String pageId, Size page, int width, int height) {
    final picture = _ink[pageId];
    var raster = _rasters.remove(pageId);
    if (raster != null) _rasters[pageId] = raster; // Most recently used.
    if (raster != null && raster.page != page) raster = null;
    if (picture == null || width <= 0 || height <= 0) return raster?.image;
    final current =
        raster != null &&
        identical(raster.picture, picture) &&
        raster.image.width >= width - 1 &&
        raster.image.width <= width * 2;
    if (!current &&
        !_deferring &&
        _rastering < _maxRastering &&
        !_pendingRasters.contains(pageId)) {
      _rasterise(pageId, picture, page, width, height);
    }
    return raster?.image;
  }

  final Set<String> _pendingRasters = {};

  void _rasterise(String pageId, ui.Picture picture, Size page, int width, int height) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(width / page.width, height / page.height)
      ..clipRect(Offset.zero & page)
      ..drawPicture(picture);
    final scaled = recorder.endRecording();
    _rastering++;
    _pendingRasters.add(pageId);
    unawaited(
      batch
          .rasterize(scaled, width, height)
          .then((image) {
            if (_disposed || !identical(_ink[pageId], picture)) {
              image.dispose(); // Changed or dropped meanwhile: asked again.
              return;
            }
            _dropRaster(pageId);
            _rasters[pageId] = _Raster(picture, page, image);
            _rasterBytes += image.bytes;
            while (_rasterBytes > maxRasterBytes && _rasters.length > 1) {
              _dropRaster(_rasters.keys.first);
            }
          })
          .whenComplete(() {
            scaled.dispose();
            _rastering--;
            _pendingRasters.remove(pageId);
            if (!_disposed) notifyListeners(); // Repaint (and ask for the next).
          }),
    );
  }

  void _dropRaster(String pageId) {
    final raster = _rasters.remove(pageId);
    if (raster == null) return;
    _rasterBytes -= raster.image.bytes;
    raster.image.dispose();
  }

  /// Image templates drawn by thumbnails (redrawn once decoded).
  final Set<String> _paperBlobs = {};

  /// An image template's bitmap for a thumbnail [pixelWidth] wide.
  ui.Image? paperImage(String blob, double pixelWidth) {
    _paperBlobs.add(blob);
    return images?.imageFor(ImageData(blob: blob, width: 0, height: 0), pixelWidth);
  }

  void _onImage(String blob) {
    if (_paperBlobs.contains(blob)) {
      notifyListeners();
      return;
    }
    final pages = [
      for (final entry in _blobs.entries)
        if (entry.value.contains(blob)) entry.key,
    ];
    if (pages.isEmpty) return;
    pages.forEach(invalidate);
    notifyListeners();
  }

  /// A user font loaded or went: pages are recorded again (text in it may
  /// be on any).
  void _onFonts() {
    if (_disposed) return;
    [..._ink.keys].forEach(invalidate);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loading?.cancel();
    defer?.removeListener(_deferChanged);
    TextFonts.changes.removeListener(_onFonts);
    unawaited(_imageChanges?.cancel());
    for (final p in _ink.values) {
      p.dispose();
    }
    _ink.clear();
    for (final id in [..._rasters.keys]) {
      _dropRaster(id);
    }
    super.dispose();
  }
}

/// A page's raster and the picture it was made from.
class _Raster {
  _Raster(this.picture, this.page, this.image);

  final ui.Picture picture;

  /// The page size it was made for.
  final Size page;
  final RasterImage image;
}
