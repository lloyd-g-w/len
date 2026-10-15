import 'dart:ui';

import '../../domain/chunk_grid.dart';
import '../lab/perf_probe.dart';
import 'chunk_raster_cache.dart';
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
    final rect = ChunkGrid.rectOf(key);
    // Strokes committed since the raster was made, until it is redone:
    // highlights beneath it (the pen ink covers them), pen ink over it.
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
