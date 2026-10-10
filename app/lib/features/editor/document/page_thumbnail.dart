import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/surface_copier.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/render/stroke_renderer.dart';
import 'page_backgrounds.dart';
import 'page_painting.dart';

/// Recorded ink and text of pages for thumbnails, loaded on first use.
class ThumbnailCache {
  ThumbnailCache(this.copier);

  final SurfaceCopier copier;
  final Map<String, ui.Picture> _ink = {};

  /// The page's ink as a picture in page units.
  ui.Picture inkOf(String pageId) =>
      _ink[pageId] ??= _record(copier.loadAll(pageId), copier.loadAllElements(pageId));

  /// Drops a page's picture after it changed.
  void invalidate(String pageId) => _ink.remove(pageId)?.dispose();

  static ui.Picture _record(List<Stroke> strokes, List<SurfaceElement> elements) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final s in strokes..sort(Stroke.drawOrder)) {
      StrokeRenderer.draw(canvas, s);
    }
    paintElements(canvas, elements);
    return recorder.endRecording();
  }

  void dispose() {
    for (final p in _ink.values) {
      p.dispose();
    }
    _ink.clear();
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
      child: CustomPaint(
        painter: _ThumbnailPainter(
          page,
          cache.inkOf(page.id),
          backgrounds,
          MediaQuery.devicePixelRatioOf(context),
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
