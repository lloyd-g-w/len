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

  void _drawOverlay(ui.Canvas canvas, TileView view, InkTile tile) {
    var rect = tile.space.worldRectOf(tile.index);
    if (_clip != null) rect = rect.intersect(_clip!);
    canvas
      ..save()
      ..clipRect(view.toDevice(rect))
      ..translate(view.origin.dx, view.origin.dy)
      ..scale(view.k);
    for (final stroke in tile.overlay) {
      StrokeRenderer.draw(canvas, stroke);
    }
    lastPaint.overlayStrokes += tile.overlay.length;
    canvas.restore();
  }
}
