import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/notebook_page.dart';

/// One square tile of a PDF page rendered [width] pixels wide.
typedef PdfTile = ({PageBackground background, int width, int col, int row});

/// Geometry of tiled PDF rendering for deep zoom.
///
/// Up to [PdfTiling.wholePageMax] pixels wide a page is rendered as one
/// image; beyond that only the tiles in view are rendered, at *levels*
/// whose page widths are powers of two ([levelFor]), each cut into
/// [tileSize]-pixel squares (the last row and column are smaller).
abstract final class PdfTiling {
  /// Side of a tile in pixels.
  static const int tileSize = 512;

  /// The widest page rendered as a single image.
  static const int wholePageMax = 2048;

  /// The widest tiled level (≈ 16× zoom of an A4 page at 3× pixel ratio).
  static const int maxLevel = 65536;

  /// The tiled level (page width in pixels) for a page shown [pixelWidth]
  /// pixels wide: the smallest power of two at least as wide (so tiles are
  /// never blurry), above [wholePageMax], at most [maxLevel].
  static int levelFor(double pixelWidth) {
    var level = wholePageMax * 2;
    while (level < pixelWidth && level < maxLevel) {
      level *= 2;
    }
    return level;
  }

  /// The page's height in pixels at [width] for a page of [page] units.
  static int heightAt(int width, Size page) =>
      math.max(1, (width * page.height / page.width).round());

  /// Columns and rows (inclusive) of the tiles at level [width] that
  /// intersect [visible] (page units) of a page of [page] units; null if
  /// none do.
  static ({int col0, int col1, int row0, int row1})? range(Size page, Rect visible, int width) {
    final area = visible.intersect(Offset.zero & page);
    if (area.isEmpty) return null;
    final k = width / page.width; // Pixels per page unit.
    final cols = (width / tileSize).ceil(), rows = (heightAt(width, page) / tileSize).ceil();
    int cell(double v, int count) => (v * k / tileSize).floor().clamp(0, count - 1);
    return (
      col0: cell(area.left, cols),
      col1: cell(math.max(area.left, area.right - 1e-6), cols),
      row0: cell(area.top, rows),
      row1: cell(math.max(area.top, area.bottom - 1e-6), rows),
    );
  }

  /// The pixel rectangle of tile ([col], [row]) at level [width].
  static ({int x, int y, int width, int height}) pixels(Size page, int width, int col, int row) {
    final height = heightAt(width, page);
    final x = col * tileSize, y = row * tileSize;
    return (
      x: x,
      y: y,
      width: math.min(tileSize, width - x),
      height: math.min(tileSize, height - y),
    );
  }

  /// Where tile ([col], [row]) at level [width] goes, in page units.
  static Rect rectOf(Size page, int width, int col, int row) {
    final p = pixels(page, width, col, row);
    final kx = page.width / width, ky = page.height / heightAt(width, page);
    return Rect.fromLTWH(p.x * kx, p.y * ky, p.width * kx, p.height * ky);
  }
}
