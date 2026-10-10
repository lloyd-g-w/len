import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../../data/page_repository.dart';
import '../../../data/stroke_repository.dart';
import '../../../domain/chunk_grid.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../domain/stroke.dart';
import '../../../ink/render/paper_painter.dart';
import '../../../ink/render/stroke_renderer.dart';
import '../../../ink/viewport.dart';

/// The surface a notebook preview shows, with its paper and, for paged
/// notebooks, the page.
typedef PreviewSource = ({String surfaceId, PaperStyle paper, NotebookPage? page});

/// Renders small preview images of notebooks with the editor's own paper
/// and stroke renderers, so previews look exactly like the real thing.
class ThumbnailRenderer {
  ThumbnailRenderer({required this.pages, required this.strokes});

  final PageRepository pages;
  final StrokeRepository strokes;

  /// Width / height of every preview (close to A4 portrait).
  static const double aspect = 0.72;

  /// The world region a canvas preview may show at most: a few chunks
  /// around the content nearest the origin.
  static const int _canvasWindowChunks = 3;

  /// What a preview of [notebook] shows: the first page of a paged
  /// notebook, or the canvas itself. Null for a notebook without pages.
  PreviewSource? sourceOf(Notebook notebook) {
    if (notebook.kind == NotebookKind.canvas) {
      return (surfaceId: notebook.id, paper: notebook.paper, page: null);
    }
    final page = pages.pagesOf(notebook.id).firstOrNull;
    return page == null ? null : (surfaceId: page.id, paper: page.paper, page: page);
  }

  /// Renders a preview [width] pixels wide, or returns null when there is
  /// nothing drawn yet (the library then shows the plain cover). Pass the
  /// [source] when already known, to skip looking it up again.
  ui.Image? render(Notebook notebook, {required int width, PreviewSource? source}) {
    final height = (width / aspect).round();
    final size = Size(width.toDouble(), height.toDouble());
    if (notebook.kind == NotebookKind.canvas) return _renderCanvas(notebook, size);
    final page = (source ?? sourceOf(notebook))?.page;
    if (page == null) return null;
    final ink = _strokesIn(page.id, ChunkGrid.rangeFor(page.bounds));
    if (ink.isEmpty) return null;
    // Top of the page, full width: what you see first when opening it.
    final world = Rect.fromLTWH(0, 0, page.width, page.width / aspect);
    return _paint(size, world, page.paper, ink, color: page.paperColor, page: page.bounds);
  }

  ui.Image? _renderCanvas(Notebook notebook, Size size) {
    final all = strokes.populatedChunks(notebook.id, _everywhere);
    if (all.isEmpty) return null;
    // Frame the content nearest the origin, limited to a small window so
    // a sprawling canvas still shows legible ink.
    final anchor = all.reduce((a, b) => _dist(a) <= _dist(b) ? a : b);
    const r = _canvasWindowChunks ~/ 2;
    final window = ChunkRange(anchor.x - r, anchor.y - r, anchor.x + r, anchor.y + r);
    final ink = _strokesIn(notebook.id, window, among: all);
    if (ink.isEmpty) return null;
    final windowRect = ChunkGrid.rectOf((x: window.minX, y: window.minY))
        .expandToInclude(ChunkGrid.rectOf((x: window.maxX, y: window.maxY)));
    final content = ink
        .map((s) => s.bounds)
        .reduce((a, b) => a.expandToInclude(b))
        .intersect(windowRect);
    return _paint(size, _frame(content, size.aspectRatio), notebook.paper, ink);
  }

  static const _everywhere = ChunkRange(-1 << 40, -1 << 40, 1 << 40, 1 << 40);

  static int _dist(ChunkKey k) => k.x * k.x + k.y * k.y;

  List<Stroke> _strokesIn(String surfaceId, ChunkRange range, {List<ChunkKey>? among}) {
    final keys = (among ?? strokes.populatedChunks(surfaceId, range))
        .where(range.contains)
        .toList();
    return strokes.loadChunks(surfaceId, keys)..sort(Stroke.paintOrder);
  }

  /// [content] padded and widened/heightened to [aspect], never smaller
  /// than a readable minimum (a lone dot should not fill the preview).
  static Rect _frame(Rect content, double aspect) {
    const minWidth = 480.0;
    var w = math.max(content.width * 1.15, minWidth);
    var h = math.max(content.height * 1.15, minWidth / aspect);
    if (w / h > aspect) {
      h = w / aspect;
    } else {
      w = h * aspect;
    }
    return Rect.fromCenter(center: content.center, width: w, height: h);
  }

  ui.Image _paint(
    Size size,
    Rect world,
    PaperStyle paper,
    List<Stroke> ink, {
    PaperColor color = PaperColor.white,
    Rect? page,
  }) {
    final viewport = ViewportController(minScale: 1e-4, maxScale: 1e4)
      ..setSize(size)
      ..contentBounds = world
      ..fitWidth(padding: 0);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    PaperPainter(viewport: viewport, style: paper, paperColor: color, page: page).paint(canvas, size);
    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(viewport.scale);
    if (page != null) canvas.clipRect(page);
    for (final stroke in ink) {
      StrokeRenderer.draw(canvas, stroke);
    }
    canvas.restore();
    viewport.dispose();
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(size.width.round(), size.height.round());
    } finally {
      picture.dispose();
    }
  }
}
