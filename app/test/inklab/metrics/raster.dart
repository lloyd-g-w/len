import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'outline_geometry.dart';

/// Anti-aliased coverage (0..1 per pixel) of filled polygons, non-zero
/// winding — what the screen shows of opaque ink, computed in pure Dart
/// (deterministic, no GPU) so tests can diff frames pixel by pixel.
class Coverage {
  Coverage(this.left, this.top, this.width, this.height) : values = Float32List(width * height);

  /// Pixel grid origin (in the polygons' units, one unit = one pixel).
  final int left, top;
  final int width, height;
  final Float32List values;

  double at(int x, int y) {
    final cx = x - left, cy = y - top;
    if (cx < 0 || cy < 0 || cx >= width || cy >= height) return 0;
    return values[cy * width + cx];
  }

  /// Covers the union of [contours] (non-zero winding) with [subRows]
  /// sub-scanlines per pixel row and exact horizontal coverage.
  void fill(List<Contour> contours, {int subRows = 5}) {
    final edges = <_Edge>[];
    for (final c in contours) {
      for (var i = 0; i < c.length; i++) {
        final a = c[i], b = c[(i + 1) % c.length];
        if (a.dy == b.dy) continue;
        edges.add(_Edge(a, b, left, top));
      }
    }
    edges.sort((a, b) => a.y0.compareTo(b.y0));
    final diff = Float32List(width + 2), direct = Float32List(width + 1);
    final active = <_Edge>[];
    final crossings = <(double, int)>[];
    var next = 0;
    final w = 1 / subRows;
    for (var row = 0; row < height; row++) {
      diff.fillRange(0, diff.length, 0);
      direct.fillRange(0, direct.length, 0);
      for (var s = 0; s < subRows; s++) {
        final y = row + (s + 0.5) * w;
        while (next < edges.length && edges[next].y0 <= y) {
          active.add(edges[next++]);
        }
        active.removeWhere((e) => e.y1 <= y);
        crossings.clear();
        for (final e in active) {
          if (e.y0 <= y) crossings.add((e.xAt(y), e.dir));
        }
        crossings.sort((a, b) => a.$1.compareTo(b.$1));
        var winding = 0;
        for (var i = 0; i < crossings.length; i++) {
          final before = winding;
          winding += crossings[i].$2;
          if (before == 0 && winding != 0) {
            // Span starts; find where winding returns to zero.
            var j = i + 1;
            var wj = winding;
            while (j < crossings.length) {
              wj += crossings[j].$2;
              if (wj == 0) break;
              j++;
            }
            if (j >= crossings.length) break;
            _span(crossings[i].$1, crossings[j].$1, w, diff, direct);
            i = j;
            winding = 0;
          }
        }
      }
      var acc = 0.0;
      final o = row * width;
      for (var x = 0; x < width; x++) {
        acc += diff[x];
        values[o + x] = math.min(1, acc + direct[x]);
      }
    }
  }

  void _span(double xa, double xb, double weight, Float32List diff, Float32List direct) {
    xa = xa.clamp(0, width.toDouble());
    xb = xb.clamp(0, width.toDouble());
    if (xb <= xa) return;
    final ia = xa.floor(), ib = xb.floor();
    if (ia == ib) {
      if (ia < width) direct[ia] += (xb - xa) * weight;
      return;
    }
    direct[ia] += (ia + 1 - xa) * weight;
    diff[ia + 1] += weight;
    diff[ib] -= weight;
    if (ib < width) direct[ib] += (xb - ib) * weight;
  }

  /// A raster covering [bounds] (pixel units), padded by [pad] pixels.
  static Coverage around(Rect bounds, {int pad = 2}) {
    final l = bounds.left.floor() - pad, t = bounds.top.floor() - pad;
    final r = bounds.right.ceil() + pad, b = bounds.bottom.ceil() + pad;
    return Coverage(l, t, math.max(1, r - l), math.max(1, b - t));
  }
}

/// Bounds of [contours] (empty rect for none).
Rect boundsOf(Iterable<Contour> contours) {
  var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
  for (final c in contours) {
    for (final p in c) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
  }
  return l.isFinite ? Rect.fromLTRB(l, t, r, b) : Rect.zero;
}

/// Fills [contours] into a fresh raster spanning [bounds].
Coverage rasterize(List<Contour> contours, Rect bounds) => Coverage.around(bounds)..fill(contours);

class _Edge {
  _Edge(Offset a, Offset b, int left, int top)
    : dir = a.dy < b.dy ? 1 : -1,
      y0 = math.min(a.dy, b.dy) - top,
      y1 = math.max(a.dy, b.dy) - top,
      _x0 = (a.dy < b.dy ? a.dx : b.dx) - left,
      _slope = (b.dx - a.dx) / (b.dy - a.dy);

  final int dir;
  final double y0, y1, _x0, _slope;

  double xAt(double y) => _x0 + (y - y0) * _slope;
}
