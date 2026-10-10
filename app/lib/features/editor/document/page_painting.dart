import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../../domain/notebook_page.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/elements/element_renderer.dart';
import '../../../ink/render/paper_painter.dart';
import '../../../ink/render/stroke_renderer.dart';
import 'document_painters.dart';

/// Paints a complete page — paper, background, template, bookmark, ink and
/// elements (text boxes, above the ink) —
/// in page units onto [canvas], which must already be scaled by [scale]
/// device pixels per unit. Used for thumbnails and raster export.
void paintWholePage(
  Canvas canvas,
  NotebookPage page, {
  required List<Stroke> strokes,
  List<SurfaceElement> elements = const [],
  required double scale,
  ui.Image? background,
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
  for (final stroke in [...strokes]..sort(Stroke.drawOrder)) {
    StrokeRenderer.draw(canvas, stroke);
  }
  paintElements(canvas, elements);
  canvas.restore();
}

/// Paints [elements] in stacking order (world = page units).
void paintElements(Canvas canvas, List<SurfaceElement> elements) {
  for (final element in [...elements]..sort(SurfaceElement.paintOrder)) {
    ElementRenderer.draw(canvas, element);
  }
}

/// Renders a page to an image [scale] pixels per page unit.
Future<ui.Image> renderPageImage(
  NotebookPage page, {
  required List<Stroke> strokes,
  List<SurfaceElement> elements = const [],
  required double scale,
  ui.Image? background,
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
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage((page.width * scale).ceil(), (page.height * scale).ceil());
  } finally {
    picture.dispose();
  }
}
