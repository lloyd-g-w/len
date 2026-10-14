import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// 8-bit grey raster helpers for `QuadDetector` (row major, one byte per
/// pixel).
abstract final class GreyOps {
  /// [grey] shrunk by the integer [factor], each pixel the mean of a
  /// factor × factor block (partial blocks at the right and bottom dropped).
  static Uint8List shrink(Uint8List grey, int width, int height, int factor) {
    if (factor <= 1) return grey;
    final w = width ~/ factor, h = height ~/ factor, n = factor * factor;
    final out = Uint8List(w * h);
    final sums = Int32List(w);
    for (var y = 0; y < h; y++) {
      sums.fillRange(0, w, 0);
      for (var j = 0; j < factor; j++) {
        final row = (y * factor + j) * width;
        for (var x = 0; x < w; x++) {
          var s = 0;
          final o = row + x * factor;
          for (var i = 0; i < factor; i++) {
            s += grey[o + i];
          }
          sums[x] += s;
        }
      }
      for (var x = 0; x < w; x++) {
        out[y * w + x] = (sums[x] + n ~/ 2) ~/ n;
      }
    }
    return out;
  }

  /// A 3 × 3 box blur (edges clamped).
  static Uint8List blur(Uint8List g, int w, int h) {
    final tmp = Uint16List(w * h), out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final r = y * w;
      for (var x = 0; x < w; x++) {
        tmp[r + x] = g[r + math.max(0, x - 1)] + g[r + x] + g[r + math.min(w - 1, x + 1)];
      }
    }
    for (var y = 0; y < h; y++) {
      final up = math.max(0, y - 1) * w, r = y * w, down = math.min(h - 1, y + 1) * w;
      for (var x = 0; x < w; x++) {
        out[r + x] = (tmp[up + x] + tmp[r + x] + tmp[down + x] + 4) ~/ 9;
      }
    }
    return out;
  }

  /// Sobel gradient magnitude (|gx| + |gy|) / 8, 0 on the border.
  static Uint8List sobel(Uint8List g, int w, int h) {
    final out = Uint8List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final o = y * w + x;
        final a = g[o - w - 1], b = g[o - w], c = g[o - w + 1];
        final d = g[o - 1], f = g[o + 1];
        final p = g[o + w - 1], q = g[o + w], r = g[o + w + 1];
        final gx = (c + 2 * f + r) - (a + 2 * d + p);
        final gy = (p + 2 * q + r) - (a + 2 * b + c);
        out[o] = math.min(255, (gx.abs() + gy.abs()) >> 3);
      }
    }
    return out;
  }

  /// Otsu's threshold of [g]: values above it form the bright class. Also
  /// returns the two classes' means.
  static ({int threshold, double low, double high}) otsu(Uint8List g) {
    final hist = Int32List(256);
    for (final v in g) {
      hist[v]++;
    }
    final total = g.length;
    var sumAll = 0.0;
    for (var i = 0; i < 256; i++) {
      sumAll += i * hist[i];
    }
    var best = -1.0, threshold = 0, wB = 0, sumB = 0.0;
    var low = 0.0, high = 0.0;
    for (var t = 0; t < 255; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB, mF = (sumAll - sumB) / wF;
      final between = wB.toDouble() * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = t;
        low = mB;
        high = mF;
      }
    }
    return (threshold: threshold, low: low, high: high);
  }

  /// The 8-connected regions of non-zero [mask] pixels whose bounding box
  /// covers at least [minBox] pixels, each as the corners of its rows'
  /// outermost pixel squares (enough for a convex hull).
  static List<List<Offset>> regions(Uint8List mask, int w, int h, int minBox) {
    final labels = Int32List(w * h);
    final stack = Int32List(w * h);
    final rowMin = Int32List(h)..fillRange(0, h, w), rowMax = Int32List(h)..fillRange(0, h, -1);
    final outlines = <List<Offset>>[];
    var next = 0;
    for (var start = 0; start < w * h; start++) {
      if (mask[start] == 0 || labels[start] != 0) continue;
      final label = ++next;
      var top = 0, minX = w, maxX = -1, minY = h, maxY = -1;
      labels[start] = label;
      stack[top++] = start;
      while (top > 0) {
        final p = stack[--top];
        final x = p % w, y = p ~/ w;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (x < rowMin[y]) rowMin[y] = x;
        if (x > rowMax[y]) rowMax[y] = x;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= w) continue;
            final q = ny * w + nx;
            if (mask[q] != 0 && labels[q] == 0) {
              labels[q] = label;
              stack[top++] = q;
            }
          }
        }
      }
      if ((maxX - minX + 1) * (maxY - minY + 1) >= minBox) {
        outlines.add([
          for (var y = minY; y <= maxY; y++) ...[
            Offset(rowMin[y].toDouble(), y.toDouble()),
            Offset(rowMin[y].toDouble(), y + 1.0),
            Offset(rowMax[y] + 1.0, y.toDouble()),
            Offset(rowMax[y] + 1.0, y + 1.0),
          ],
        ]);
      }
      rowMin.fillRange(minY, maxY + 1, w);
      rowMax.fillRange(minY, maxY + 1, -1);
    }
    return outlines;
  }
}
