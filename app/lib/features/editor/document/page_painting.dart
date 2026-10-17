import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../../domain/image_data.dart';
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
/// [images] as far as they are decoded (placeholders otherwise). With
/// [worldOrigin], the page is the part of an infinite canvas whose top-left
/// is there, and the pattern is aligned as on the canvas. With [sketchThin],
/// ink thinner than a hairline at [scale] is drawn as plain lines
/// (`ContentPainter`).
void paintWholePage(
  Canvas canvas,
  NotebookPage page, {
  required List<Stroke> strokes,
  List<SurfaceElement> elements = const [],
  required double scale,
  ui.Image? background,
  ElementImages? images,
  PaperImageLookup? paperImages,
  bool miniature = false,
  bool showBookmark = false,
  Offset? worldOrigin,
  bool sketchThin = false,
}) {
  final rect = Offset.zero & page.size;
  canvas
    ..save()
    ..clipRect(rect);
  PaperRenderer.paintSheet(canvas, rect, page.paperColor, scale: scale, shadow: false);
  if (background != null) paintBackgroundImage(canvas, background, rect);
  final lookup = paperImages ?? (images == null ? null : paperImagesOf(images));
  if (worldOrigin case final origin?) {
    // A piece of an infinite canvas: its pattern runs from the world's
    // origin, as on screen, not from this rectangle's corner.
    canvas
      ..save()
      ..translate(-origin.dx, -origin.dy);
    PaperRenderer.paintPattern(
      canvas,
      page.paper,
      page.paperColor,
      rect.shift(origin),
      scale: scale,
      thumbnail: miniature,
      images: lookup,
    );
    canvas.restore();
  } else {
    PaperRenderer.paintPattern(
      canvas,
      page.paper,
      page.paperColor,
      rect,
      page: rect,
      scale: scale,
      thumbnail: miniature,
      images: lookup,
    );
  }
  if (showBookmark && page.bookmarked) paintBookmark(canvas, page.size);
  ContentPainter.paint(
    canvas,
    strokes,
    elements,
    images: images,
    pixelScale: scale,
    sketchThin: sketchThin,
  );
  canvas.restore();
}

/// Image templates looked up in [images] (decoding them if needed).
PaperImageLookup paperImagesOf(ElementImages images) =>
    (blob, width) => images.imageFor(ImageData(blob: blob, width: 0, height: 0), width);

/// Renders a page to an image [scale] pixels per page unit.
Future<ui.Image> renderPageImage(
  NotebookPage page, {
  required List<Stroke> strokes,
  List<SurfaceElement> elements = const [],
  required double scale,
  ui.Image? background,
  ElementImages? images,
  Offset? worldOrigin,
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
    worldOrigin: worldOrigin,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage((page.width * scale).ceil(), (page.height * scale).ceil());
  } finally {
    picture.dispose();
  }
}
