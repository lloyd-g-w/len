import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/surface_copier.dart';
import '../../../domain/image_data.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/render/content_painter.dart';
import '../../../ink/render/paper_painter.dart';
import 'page_backgrounds.dart';
import 'page_painting.dart';

/// Recorded ink, text and images of pages for thumbnails, loaded on first
/// use. Notifies when a page's picture was dropped because one of its
/// images finished decoding (it is then recorded again, sharper).
class ThumbnailCache extends ChangeNotifier {
  ThumbnailCache(this.copier, {this.images}) {
    _imageChanges = images?.changes.listen(_onImage);
  }

  final SurfaceCopier copier;

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

  void _enqueue(String pageId) {
    _queue.add(pageId);
    _loading ??= Timer(Duration.zero, _loadSome);
  }

  void _loadSome() {
    _loading = null;
    if (_disposed) return;
    final watch = Stopwatch()..start();
    while (_queue.isNotEmpty && watch.elapsed < frameBudget) {
      final pageId = _queue.first;
      _queue.remove(pageId);
      _ink.remove(pageId)?.dispose();
      _ink[pageId] = _record(pageId);
    }
    while (_ink.length > maxPages) {
      final oldest = _ink.keys.first;
      _ink.remove(oldest)?.dispose();
      _blobs.remove(oldest);
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
    ContentPainter.paint(
      Canvas(recorder),
      strokes,
      elements,
      images: images,
      pixelScale: imageScale,
    );
    return recorder.endRecording();
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

  @override
  void dispose() {
    _disposed = true;
    _loading?.cancel();
    unawaited(_imageChanges?.cancel());
    for (final p in _ink.values) {
      p.dispose();
    }
    _ink.clear();
    super.dispose();
  }
}

/// A read-only miniature of a page: paper, background, template and ink.
class PageThumbnail extends StatelessWidget {
  const PageThumbnail({super.key, required this.page, required this.cache, this.backgrounds});

  final NotebookPage page;
  final ThumbnailCache cache;
  final PageBackgrounds? backgrounds;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: page.width / page.height,
      child: ListenableBuilder(
        listenable: cache,
        builder: (context, _) => CustomPaint(
          painter: _ThumbnailPainter(
            page,
            cache.inkOf(page.id),
            backgrounds,
            MediaQuery.devicePixelRatioOf(context),
            cache.paperImage,
          ),
        ),
      ),
    );
  }
}

class _ThumbnailPainter extends CustomPainter {
  _ThumbnailPainter(this.page, this.ink, this.backgrounds, this.dpr, this.paperImage)
    : super(repaint: backgrounds);

  final NotebookPage page;
  final ui.Picture? ink;
  final PageBackgrounds? backgrounds;
  final double dpr;
  final PaperImageLookup paperImage;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / page.width;
    final bg = page.background;
    final image = bg == null ? null : backgrounds?.imageFor(bg, size.width * dpr);
    canvas
      ..save()
      ..scale(scale);
    paintWholePage(
      canvas,
      page,
      strokes: const [],
      scale: scale,
      background: image,
      miniature: true,
      paperImages: (blob, _) => paperImage(blob, size.width * dpr),
    );
    if (ink case final ink?) {
      canvas
        ..clipRect(Offset.zero & page.size)
        ..drawPicture(ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbnailPainter old) =>
      old.page != page || old.ink != ink || old.backgrounds != backgrounds || old.dpr != dpr;
}
