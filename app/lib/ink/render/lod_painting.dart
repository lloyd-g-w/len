import 'dart:ui';

import '../../domain/chunk_grid.dart';
import '../lab/perf_probe.dart';
import 'chunk_raster_cache.dart';
import 'raster_batch.dart';
import 'stroke_renderer.dart';
import 'tiles/ink_tile_cache.dart';
import 'tiles/tile_space.dart';

/// Chunks without a raster that one frame may record as vectors when they
/// must be drawn from them (edited, see [ChunkRasterCache.needsVectors]),
/// so a whole screen of uncached chunks never stalls a frame.
const int lodFreshRecordingsPerFrame = 8;

final Paint _imagePaint = Paint()
  ..filterQuality = FilterQuality.medium
  // Unsmoothed edges: neighbouring chunks tile without seams.
  ..isAntiAlias = false;

/// Paints the ink in [view] (device pixels; [canvas] in logical pixels)
/// from the level-of-detail rasters of [rasters] at [level], one image per
/// chunk, so a zoomed-out frame costs as many images as chunks on screen
/// however much ink they hold.
///
/// Chunks without a raster yet (queued) show what [tiles] still hold of
/// them (the closer zoom's images, scaled); where they hold nothing, only
/// edited chunks are drawn from vectors — the others stay empty for the
/// frame or two until their raster is made.
void paintLod(
  Canvas canvas, {
  required ChunkRasterCache rasters,
  required TileView view,
  required int level,
  required double devicePixelRatio,
  InkTileCache? tiles,
}) {
  final pictures = rasters.pictures;
  final area = view.clip == null ? view.visible : view.visible.intersect(view.clip!);
  if (area.isEmpty) return;
  void toWorld() {
    canvas
      ..save()
      ..scale(1 / devicePixelRatio)
      ..translate(view.origin.dx, view.origin.dy)
      ..scale(view.k);
    if (view.clip != null) canvas.clipRect(view.clip!);
  }

  final missing = <ChunkKey>[];
  toWorld();
  for (final key in rasters.chunksIn(ChunkGrid.rangeFor(area))) {
    final image = rasters.imageFor(key, level);
    if (image == null) {
      missing.add(key);
      continue;
    }
    _drawRaster(canvas, rasters, key, image);
  }
  canvas.restore();
  if (missing.isEmpty) return;

  var uncovered = [for (final key in missing) ChunkGrid.rectOf(key)];
  if (tiles != null) {
    final clip = Path();
    var bounds = uncovered.first;
    for (final rect in uncovered) {
      clip.addRect(view.toDevice(rect));
      bounds = bounds.expandToInclude(rect);
    }
    canvas
      ..save()
      ..scale(1 / devicePixelRatio)
      ..clipPath(clip, doAntiAlias: false);
    uncovered = tiles.paintStandIn(canvas, view, bounds);
    canvas.restore();
  }
  if (uncovered.isEmpty) return;
  var fresh = lodFreshRecordingsPerFrame;
  toWorld();
  for (final key in missing) {
    if (!rasters.needsVectors(key)) continue;
    final rect = ChunkGrid.rectOf(key);
    final parts = [
      for (final r in uncovered)
        if (r.overlaps(rect)) r.intersect(rect),
    ];
    if (parts.isEmpty) continue;
    final picture = pictures.peek(key) ?? (fresh-- > 0 ? pictures.pictureFor(key) : null);
    if (picture == null) continue;
    final clip = Path();
    for (final part in parts) {
      clip.addRect(part);
    }
    canvas
      ..save()
      ..clipPath(clip, doAntiAlias: false)
      ..drawPicture(picture)
      ..restore();
    PerfProbe.count('chunkDraws');
  }
  canvas.restore();
}

/// Draws [image], [key]'s raster, over its chunk ([canvas] in world
/// units), with the strokes committed since it was made, until it is
/// redone: highlights beneath it (the pen ink covers them), pen ink over
/// it.
void _drawRaster(Canvas canvas, ChunkRasterCache rasters, ChunkKey key, RasterImage image) {
  final rect = ChunkGrid.rectOf(key);
  final added = rasters.overlayOf(key, image);
  void draw(bool highlights) {
    canvas
      ..save()
      ..clipRect(rect);
    for (final stroke in added) {
      if (stroke.tool.isHighlighter == highlights) StrokeRenderer.draw(canvas, stroke);
    }
    canvas.restore();
  }

  if (added.any((s) => s.tool.isHighlighter)) draw(true);
  canvas.drawImageRect(image.image, image.source, rect, _imagePaint);
  if (added.any((s) => !s.tool.isHighlighter)) draw(false);
}

/// Draws the level-of-detail rasters [rasters] holds of the chunks in
/// [world] (rects in world units, clipped to them; [canvas] in device
/// pixels) as stand-ins: zooming in from the level of detail, the tiles
/// of the new zoom are not rendered yet, and the rasters showed the ink a
/// frame ago — without them it vanished for a frame or two. Nothing is
/// asked for. Returns the parts of [world] with ink and no raster.
List<Rect> paintRasterStandIn(
  Canvas canvas,
  ChunkRasterCache rasters,
  TileView view,
  List<Rect> world,
) {
  final uncovered = <Rect>[];
  final clip = Path();
  final drawn = <(ChunkKey, RasterImage)>[];
  for (final rect in world) {
    final area = view.clip == null ? rect : rect.intersect(view.clip!);
    if (area.isEmpty) continue;
    for (final key in rasters.pictures.model.chunksIn(ChunkGrid.rangeFor(area))) {
      final part = ChunkGrid.rectOf(key).intersect(area);
      if (part.isEmpty) continue;
      final image = rasters.peekFinest(key);
      if (image == null) {
        uncovered.add(part);
        continue;
      }
      clip.addRect(part);
      if (!drawn.any((d) => d.$1 == key)) drawn.add((key, image));
    }
  }
  if (drawn.isEmpty) return uncovered;
  canvas
    ..save()
    ..translate(view.origin.dx, view.origin.dy)
    ..scale(view.k)
    ..clipPath(clip, doAntiAlias: false);
  for (final (key, image) in drawn) {
    _drawRaster(canvas, rasters, key, image);
  }
  canvas.restore();
  PerfProbe.count('lodStandIns', drawn.length);
  return uncovered;
}
