import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../domain/chunk_grid.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/render/chunk_raster_cache.dart';
import '../../../ink/render/ink_painters.dart';
import '../../../ink/render/lod_painting.dart';
import '../../../ink/render/paper_painter.dart';
import '../../../ink/render/tiles/tile_space.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
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
  canvas.drawPath(path, Paint()..color = Palette.bookmark);
}

/// Paints the desk, the visible pages' paper (resting on it with a contact
/// shadow), backgrounds and templates.
class DocumentPaperPainter extends CustomPainter {
  DocumentPaperPainter({
    required this.layout,
    required this.pages,
    required this.viewport,
    required this.desk,
    required this.shadows,
    required this.devicePixelRatio,
    this.backgrounds,
    this.paperImages,
    Listenable? paperImagesChanged,
  }) : super(repaint: Listenable.merge([viewport, ?backgrounds, ?paperImagesChanged]));

  final DocumentLayout layout;
  final List<NotebookPage> pages;
  final ViewportController viewport;
  final Color desk;

  /// The pages' contact shadow ([Shadows.low]), in screen pixels.
  final List<BoxShadow> shadows;
  final double devicePixelRatio;
  final PageBackgrounds? backgrounds;

  /// Decoded image templates.
  final PaperImageLookup? paperImages;

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
      for (final shadow in shadows) {
        canvas.drawRect(
          local.shift(shadow.offset / scale).inflate(shadow.spreadRadius / scale),
          Paint()
            ..color = shadow.color
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma / scale),
        );
      }
      PaperRenderer.paintSheet(canvas, local, page.paperColor, scale: scale, shadow: false);
      canvas.clipRect(local);
      final area = visible.shift(-frame.topLeft).intersect(local);
      final background = page.background;
      if (background != null && !area.isEmpty) {
        backgrounds?.paint(canvas, background, frame.size, area, scale * devicePixelRatio);
      }
      if (!area.isEmpty) {
        PaperRenderer.paintPattern(
          canvas,
          page.paper,
          page.paperColor,
          area,
          page: local,
          scale: scale,
          images: paperImages == null
              ? null
              : (blob, _) => paperImages!(blob, frame.width * scale * devicePixelRatio),
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
      !listEquals(old.shadows, shadows) ||
      old.devicePixelRatio != devicePixelRatio ||
      old.backgrounds != backgrounds ||
      old.paperImages != paperImages;
}

/// Paints the committed ink of the visible pages from their tile caches
/// (chunk pictures where no tile is rendered yet), or zoomed out far from
/// their level-of-detail rasters.
class DocumentInkPainter extends CustomPainter {
  DocumentInkPainter({
    required this.layout,
    required this.pages,
    required this.surfaces,
    required this.viewport,
    this.devicePixelRatio = 1,
    this.self = const {},
  }) : super(
         repaint: Listenable.merge([
           viewport,
           surfaces,
           surfaces.rendered,
           ForeignLiftedChanges(surfaces.lifted, () => surfaces.lastLiftedOwner, self),
         ]),
       );

  final DocumentLayout layout;
  final List<NotebookPage> pages;
  final DocumentSurfaces surfaces;
  final ViewportController viewport;
  final double devicePixelRatio;

  /// This view's own selection and text editor: what they lift out of a
  /// page they draw themselves; other owners' (another view of the
  /// notebook) is drawn here.
  final Set<Object?> self;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = viewport.visibleWorldFor(size);
    final scale = viewport.scale;
    TileView viewOf(Rect frame, Rect world) => TileView(
      k: scale * devicePixelRatio,
      origin: (viewport.offset + frame.topLeft * scale) * devicePixelRatio,
      visible: world.shift(-frame.topLeft),
      clip: Offset.zero & frame.size,
    );
    // Zoomed out far (many pages on screen): level-of-detail rasters, one
    // image per chunk, instead of tiles replaying every page's ink.
    final level = ChunkRasterCache.levelFor(ChunkGrid.size * scale * devicePixelRatio);
    final shown = layout.visiblePages(visible).toSet();
    // Pages about to scroll into view: their tiles (or rasters) are
    // rendered ahead.
    final ahead = DocumentLayout.lookahead(visible);
    for (final index in layout.visiblePages(ahead)) {
      if (shown.contains(index)) continue;
      final surface = surfaces.peek(pages[index].id);
      if (surface == null) continue;
      final view = viewOf(layout.frameOf(index)!, ahead);
      if (level == null) {
        surface.tiles.prefetch(view);
      } else if (!surface.model.isLoading) {
        final area = view.visible.intersect(view.clip!);
        for (final key in surface.model.chunksIn(ChunkGrid.rangeFor(area))) {
          surface.rasters.imageFor(key, level);
        }
      }
    }
    for (final index in shown) {
      final surface = surfaces.peek(pages[index].id);
      if (surface == null) continue;
      final frame = layout.frameOf(index)!;
      final view = viewOf(frame, visible);
      if (surface.model.chunksIn(ChunkGrid.rangeFor(view.visible)).isNotEmpty) {
        surface.cache.setScale(scale); // Image resolution.
        if (level == null) {
          paintTiled(canvas, surface.tiles, view, devicePixelRatio);
        } else {
          paintLod(
            canvas,
            rasters: surface.rasters,
            view: view,
            level: level,
            devicePixelRatio: devicePixelRatio,
            tiles: surface.tiles,
          );
        }
      }
      // Over the ink, as the owner's own view shows it.
      if (surface.model.hasLiftedExcept(self)) {
        canvas
          ..save()
          ..translate(viewport.offset.dx, viewport.offset.dy)
          ..scale(scale)
          ..translate(frame.left, frame.top)
          ..clipRect(Offset.zero & frame.size);
        surface.model.paintLifted(canvas, except: self);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(DocumentInkPainter old) =>
      old.layout != layout ||
      old.pages != pages ||
      old.surfaces != surfaces ||
      old.viewport != viewport ||
      old.devicePixelRatio != devicePixelRatio ||
      !setEquals(old.self, self);
}
