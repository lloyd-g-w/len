part of 'ink_tile_cache.dart';

final ui.Paint _exactPaint = ui.Paint()..filterQuality = ui.FilterQuality.none;
final ui.Paint _scaledPaint = ui.Paint()..filterQuality = ui.FilterQuality.medium;

/// Device pixels of [rects] (world) within the view's clip.
double _pixels(List<ui.Rect> rects, TileView view) {
  var sum = 0.0;
  for (final rect in rects) {
    final area = view.clip == null ? rect : rect.intersect(view.clip!);
    if (!area.isEmpty) sum += area.width * area.height * view.k * view.k;
  }
  return sum;
}

/// Drawing tile images and overlays.
extension _Drawing on InkTileCache {
  /// Paints the tiles of [space] over [area] (the visible world in [view]),
  /// scaled unless they are of the view's zoom ([same]); requests those to
  /// render. Returns the world rects to draw as vectors and the tiles with
  /// strokes to draw over them.
  ({List<ui.Rect> missing, List<InkTile> overlays}) _paintTiles(
    ui.Canvas canvas,
    TileView view,
    TileSpace space,
    ui.Rect area, {
    required bool same,
  }) {
    // Where tile (0, 0) of [space] sits, on whole device pixels.
    final x0 = (view.origin.dx - space.phase.dx).roundToDouble();
    final y0 = (view.origin.dy - space.phase.dy).roundToDouble();
    final missing = <ui.Rect>[];
    final overlays = <InkTile>[];
    for (final index in space.covering(area)) {
      final tile = _tiles[index] ??= InkTile(pool, space, index);
      final rect = space.worldRectOf(index);
      tile.blank ??= model.chunksIn(ChunkGrid.rangeFor(rect)).isEmpty;
      if (tile.blank! && tile.overlay.isEmpty) continue;
      final image = tile.image;
      if (image != null) {
        final dst = same
            ? ui.Rect.fromLTWH(
                index.x * TileSpace.size + x0,
                index.y * TileSpace.size + y0,
                TileSpace.size.toDouble(),
                TileSpace.size.toDouble(),
              )
            : view.toDevice(rect);
        if (tile.underlay.isNotEmpty) _drawUnderlay(canvas, view, tile);
        _drawImage(canvas, image, dst, exact: same);
        pool.touch(tile);
        lastPaint.images++;
        if (tile.stale) {
          lastPaint.staleImages++;
          _request(index, 1);
        }
        if (tile.overlay.isNotEmpty) overlays.add(tile);
        continue;
      }
      _request(index, 1);
      if (tile.edited) {
        missing.add(rect); // Shown as it now is at once.
        continue;
      }
      final uncovered = _drawOld(canvas, view, rect);
      if (_oldSpace == null && !_holdForLoad) {
        missing.addAll(uncovered); // A first show.
      } else {
        // Not rendered since a zoom (a rim zooming out exposed), or
        // waiting for the surface to load: empty for the frame or two
        // until it is, rather than frames of vectors.
        lastPaint.blankPixels += _pixels(uncovered, view);
      }
    }
    return (missing: missing, overlays: overlays);
  }

  List<ui.Rect> _paintStandIn(ui.Canvas canvas, TileView view, ui.Rect world) {
    final space = _space;
    if (space == null || view.clip != _clip) return [world];
    final area = view.clip == null ? world : world.intersect(view.clip!);
    if (area.isEmpty) return const [];
    final uncovered = <ui.Rect>[];
    for (final index in space.covering(area)) {
      final rect = space.worldRectOf(index).intersect(area);
      final tile = _tiles[index];
      final image = tile?.image;
      if (tile != null && image != null && !tile.stale) {
        _drawImage(canvas, image, view.toDevice(space.worldRectOf(index)), exact: false);
        if (tile.overlay.isNotEmpty) _drawOverlay(canvas, view, tile);
        lastPaint.images++;
      } else if (tile == null || tile.blank != true || tile.overlay.isNotEmpty) {
        uncovered.addAll(_drawOld(canvas, view, rect));
      }
    }
    return uncovered;
  }

  void _drawImage(ui.Canvas canvas, ui.Image image, ui.Rect dst, {required bool exact}) {
    final src = ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, exact ? _exactPaint : _scaledPaint);
  }

  /// Draws the tiles of the previous space over [rect] (scaled); returns
  /// the parts of [rect] they do not cover.
  List<ui.Rect> _drawOld(ui.Canvas canvas, TileView view, ui.Rect rect) {
    final old = _oldSpace;
    if (old == null) return [rect];
    final uncovered = <ui.Rect>[];
    var clipped = false;
    for (final index in old.covering(rect)) {
      final tile = _old[index];
      final image = tile?.image;
      if (tile == null || (image == null && tile.blank != true)) {
        uncovered.add(old.worldRectOf(index).intersect(rect));
        continue;
      }
      if (image == null) continue; // Blank.
      if (!clipped) {
        clipped = true;
        canvas
          ..save()
          ..clipRect(view.toDevice(rect));
      }
      _drawImage(canvas, image, view.toDevice(old.worldRectOf(index)), exact: false);
      pool.touch(tile);
      lastPaint.images++;
    }
    if (clipped) canvas.restore();
    return uncovered;
  }

  /// Draws the strokes appended to [tile] since its image (over it).
  void _drawOverlay(ui.Canvas canvas, TileView view, InkTile tile) {
    _drawStrokes(canvas, view, tile, tile.overlay);
    lastPaint.overlayStrokes += tile.overlay.length;
  }

  /// Draws the highlighter strokes added to [tile] since its image
  /// (beneath it).
  void _drawUnderlay(ui.Canvas canvas, TileView view, InkTile tile) {
    _drawStrokes(canvas, view, tile, tile.underlay);
    lastPaint.underlayStrokes += tile.underlay.length;
  }

  void _drawStrokes(ui.Canvas canvas, TileView view, InkTile tile, List<Stroke> strokes) {
    var rect = tile.space.worldRectOf(tile.index);
    if (_clip != null) rect = rect.intersect(_clip!);
    canvas
      ..save()
      ..clipRect(view.toDevice(rect))
      ..translate(view.origin.dx, view.origin.dy)
      ..scale(view.k);
    for (final stroke in strokes) {
      StrokeRenderer.draw(canvas, stroke);
    }
    canvas.restore();
  }
}
