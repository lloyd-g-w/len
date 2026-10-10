import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../domain/chunk_grid.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/render/paper_painter.dart';
import '../../../ink/viewport.dart';
import 'document_layout.dart';
import 'document_surfaces.dart';
import 'page_backgrounds.dart';

/// Draws a page's background image (e.g. a PDF page) into [rect].
void paintBackgroundImage(Canvas canvas, ui.Image image, Rect rect) {
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    rect,
    Paint()..filterQuality = FilterQuality.medium,
  );
}

/// Draws the bookmark ribbon at a page's top-right corner (page units).
void paintBookmark(Canvas canvas, Size page) {
  const width = 22.0, height = 38.0;
  final x = page.width - 56;
  final path = Path()
    ..moveTo(x, 0)
    ..lineTo(x + width, 0)
    ..lineTo(x + width, height)
    ..lineTo(x + width / 2, height - 8)
    ..lineTo(x, height)
    ..close();
  canvas.drawPath(path, Paint()..color = const Color(0xFFE8590C));
}

/// Paints the desk, the visible pages' paper, backgrounds and templates.
class DocumentPaperPainter extends CustomPainter {
  DocumentPaperPainter({
    required this.layout,
    required this.pages,
    required this.viewport,
    required this.desk,
    required this.devicePixelRatio,
    this.backgrounds,
  }) : super(repaint: Listenable.merge([viewport, ?backgrounds]));

  final DocumentLayout layout;
  final List<NotebookPage> pages;
  final ViewportController viewport;
  final Color desk;
  final double devicePixelRatio;
  final PageBackgrounds? backgrounds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = desk);
    final visible = viewport.visibleWorldFor(size);
    final scale = viewport.scale;
    for (final index in layout.visiblePages(visible)) {
      final page = pages[index];
      final frame = layout.frameOf(index)!;
      final local = Offset.zero & frame.size;
      canvas
        ..save()
        ..translate(viewport.offset.dx, viewport.offset.dy)
        ..scale(scale)
        ..translate(frame.left, frame.top);
      PaperRenderer.paintSheet(canvas, local, page.paperColor, scale: scale);
      canvas.clipRect(local);
      final background = page.background;
      if (background != null) {
        final pixelWidth = frame.width * scale * devicePixelRatio;
        final image = backgrounds?.imageFor(background, pixelWidth);
        if (image != null) paintBackgroundImage(canvas, image, local);
      }
      final area = visible.shift(-frame.topLeft).intersect(local);
      if (!area.isEmpty) {
        PaperRenderer.paintPattern(
          canvas,
          page.paper,
          page.paperColor,
          area,
          page: local,
          scale: scale,
        );
      }
      if (page.bookmarked) paintBookmark(canvas, frame.size);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(DocumentPaperPainter old) =>
      old.layout != layout ||
      old.pages != pages ||
      old.viewport != viewport ||
      old.desk != desk ||
      old.devicePixelRatio != devicePixelRatio ||
      old.backgrounds != backgrounds;
}

/// Paints the committed ink of the visible pages from their chunk caches.
class DocumentInkPainter extends CustomPainter {
  DocumentInkPainter({
    required this.layout,
    required this.pages,
    required this.surfaces,
    required this.viewport,
  }) : super(repaint: Listenable.merge([viewport, surfaces]));

  final DocumentLayout layout;
  final List<NotebookPage> pages;
  final DocumentSurfaces surfaces;
  final ViewportController viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = viewport.visibleWorldFor(size);
    for (final index in layout.visiblePages(visible)) {
      final surface = surfaces.peek(pages[index].id);
      if (surface == null) continue;
      final frame = layout.frameOf(index)!;
      final local = visible.shift(-frame.topLeft);
      final chunks = surface.model.chunksIn(ChunkGrid.rangeFor(local));
      if (chunks.isEmpty) continue;
      canvas
        ..save()
        ..translate(viewport.offset.dx, viewport.offset.dy)
        ..scale(viewport.scale)
        ..translate(frame.left, frame.top)
        ..clipRect(Offset.zero & frame.size);
      for (final key in chunks) {
        canvas.drawPicture(surface.cache.pictureFor(key));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(DocumentInkPainter old) =>
      old.layout != layout ||
      old.pages != pages ||
      old.surfaces != surfaces ||
      old.viewport != viewport;
}
