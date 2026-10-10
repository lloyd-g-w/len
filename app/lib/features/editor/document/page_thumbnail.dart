import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/surface_copier.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/render/content_painter.dart';
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

  final Map<String, ui.Picture> _ink = {};

  /// Image blobs drawn into each page's picture.
  final Map<String, Set<String>> _blobs = {};
  StreamSubscription<String>? _imageChanges;

  /// The page's content as a picture in page units.
  ui.Picture inkOf(String pageId) => _ink[pageId] ??= _record(pageId);

  /// Drops a page's picture after it changed.
  void invalidate(String pageId) {
    _ink.remove(pageId)?.dispose();
    _blobs.remove(pageId);
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

  void _onImage(String blob) {
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
          ),
        ),
      ),
    );
  }
}

class _ThumbnailPainter extends CustomPainter {
  _ThumbnailPainter(this.page, this.ink, this.backgrounds, this.dpr) : super(repaint: backgrounds);

  final NotebookPage page;
  final ui.Picture ink;
  final PageBackgrounds? backgrounds;
  final double dpr;

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
    );
    canvas
      ..clipRect(Offset.zero & page.size)
      ..drawPicture(ink)
      ..restore();
  }

  @override
  bool shouldRepaint(_ThumbnailPainter old) =>
      old.page != page || old.ink != ink || old.backgrounds != backgrounds || old.dpr != dpr;
}
