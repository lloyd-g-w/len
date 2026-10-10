import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../../domain/notebook_page.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/render/content_painter.dart';
import '../../../ink/render/paper_painter.dart';
import 'document_painters.dart';

/// Paints a complete page — paper, background, template, bookmark, ink and
/// elements (images beneath the ink, text above) — in page units onto
/// [canvas], which must already be scaled by [scale] device pixels per
/// unit. Used for thumbnails and raster export. Images are drawn from
/// [images] as far as they are decoded (placeholders otherwise).
void paintWholePage(
  Canvas canvas,
  NotebookPage page, {
  required List<Stroke> strokes,
  List<SurfaceElement> elements = const [],
  required double scale,
  ui.Image? background,
  ElementImages? images,
  bool miniature = false,
  bool showBookmark = false,
}) {
  final rect = Offset.zero & page.size;
  canvas
    ..save()
    ..clipRect(rect);
  PaperRenderer.paintSheet(canvas, rect, page.paperColor, scale: scale, shadow: false);
  if (background != null) paintBackgroundImage(canvas, background, rect);
  PaperRenderer.paintPattern(
    canvas,
    page.paper,
    page.paperColor,
    rect,
    page: rect,
    scale: scale,
    always: miniature,
  );
  if (showBookmark && page.bookmarked) paintBookmark(canvas, page.size);
  ContentPainter.paint(canvas, strokes, elements, images: images, pixelScale: scale);
  canvas.restore();
}

/// Renders a page to an image [scale] pixels per page unit.
Future<ui.Image> renderPageImage(
  NotebookPage page, {
  required List<Stroke> strokes,
  List<SurfaceElement> elements = const [],
  required double scale,
  ui.Image? background,
  ElementImages? images,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  paintWholePage(
    canvas,
    page,
    strokes: strokes,
    elements: elements,
    scale: scale,
    background: background,
    images: images,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage((page.width * scale).ceil(), (page.height * scale).ceil());
  } finally {
    picture.dispose();
  }
}
