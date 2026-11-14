import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/render/content_painter.dart';
import '../../../ink/render/paper_painter.dart';
import '../document/page_painting.dart';

/// A page of a paged notebook as an area capture draws it: laid out at
/// [frame] (document coordinates) with its content and its background
/// (a PDF page or scan, already rendered; disposed by the caller).
class CapturePage {
  const CapturePage(
    this.page,
    this.frame, {
    required this.strokes,
    this.elements = const [],
    this.background,
  });

  final NotebookPage page;
  final Rect frame;
  final List<Stroke> strokes;
  final List<SurfaceElement> elements;
  final ui.Image? background;
}

/// A piece of an infinite canvas: its paper and the content near the
/// captured area, in world coordinates.
class CaptureCanvas {
  const CaptureCanvas({
    required this.paper,
    required this.paperColor,
    required this.strokes,
    this.elements = const [],
  });

  final Paper paper;
  final PaperColor paperColor;
  final List<Stroke> strokes;
  final List<SurfaceElement> elements;
}

/// Renders a rectangle of a notebook as it looks on screen, without the
/// editor's chrome: paper, template, backgrounds, images, ink, shapes and
/// text, through the painters thumbnails and PNG export use
/// ([paintWholePage]). Between the pages of a paged notebook the image is
/// transparent.
abstract final class AreaImage {
  /// Pixels per unit a capture aims for (as PNG export, 288 dpi), or the
  /// screen's when it shows the area larger.
  static const double baseScale = 3;

  /// The most pixels per unit (deep zoom).
  static const double maxScale = 8;

  /// The longest side of a capture, in pixels (an image Len stores
  /// unchanged, `ImageImport.maxEdge`).
  static const int maxPixels = 4096;

  /// Pixels per unit for capturing [area] shown at [screenScale] device
  /// pixels per unit: at least [baseScale], at most [maxScale], and no
  /// more than [maxPixels] on the long side.
  static double scaleFor(Size area, {double screenScale = 0}) {
    final wanted = math.min(maxScale, math.max(baseScale, screenScale));
    final longest = math.max(area.width, area.height);
    return longest <= 0 ? wanted : math.min(wanted, maxPixels / longest);
  }

  /// The image's size in pixels for [area] at [scale].
  static (int, int) pixelSize(Rect area, double scale) =>
      (math.max(1, (area.width * scale).round()), math.max(1, (area.height * scale).round()));

  /// Paints [area] (document or world coordinates) onto [canvas], already
  /// scaled by [scale] pixels per unit and with [area]'s top left at its
  /// origin: the laid-out [pages], or the [board] of an infinite canvas.
  static void paint(
    Canvas canvas,
    Rect area, {
    required double scale,
    List<CapturePage> pages = const [],
    CaptureCanvas? board,
    ElementImages? images,
  }) {
    canvas
      ..save()
      ..clipRect(Offset.zero & area.size)
      ..translate(-area.left, -area.top);
    for (final p in pages) {
      if (!p.frame.overlaps(area)) continue;
      canvas
        ..save()
        ..translate(p.frame.left, p.frame.top);
      paintWholePage(
        canvas,
        p.page,
        strokes: p.strokes,
        elements: p.elements,
        scale: scale,
        background: p.background,
        images: images,
        showBookmark: true,
      );
      canvas.restore();
    }
    if (board != null) _paintBoard(canvas, area, board, scale, images);
    canvas.restore();
  }

  /// As [paintWholePage] does for an exported canvas, but in world
  /// coordinates: the pattern runs from the world's origin, as on screen.
  static void _paintBoard(
    Canvas canvas,
    Rect area,
    CaptureCanvas board,
    double scale,
    ElementImages? images,
  ) {
    PaperRenderer.paintSheet(canvas, area, board.paperColor, scale: scale, shadow: false);
    PaperRenderer.paintPattern(
      canvas,
      board.paper,
      board.paperColor,
      area,
      scale: scale,
      images: images == null ? null : paperImagesOf(images),
    );
    ContentPainter.paint(canvas, board.strokes, board.elements, images: images, pixelScale: scale);
  }

  /// [area] as an image at [scale] pixels per unit (see [paint]); the
  /// caller disposes it.
  static Future<ui.Image> render(
    Rect area, {
    required double scale,
    List<CapturePage> pages = const [],
    CaptureCanvas? board,
    ElementImages? images,
  }) async {
    final (width, height) = pixelSize(area, scale);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(width / area.width, height / area.height);
    paint(canvas, area, scale: scale, pages: pages, board: board, images: images);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }
}
