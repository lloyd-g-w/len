import 'dart:math' as math;
import 'dart:typed_data';

import 'scan_image.dart';

/// What "enhance" needs to know about a page before touching its pixels:
/// the paper's brightness across the page (so shading and uneven light
/// flatten out) and the tone curve. Build it once with [EnhanceMap.of],
/// then run [enhanceRows] over the page in as many bands as convenient.
class EnhanceMap {
  EnhanceMap._(this._block, this._gw, this._gh, this._paper, this._cx0, this._cfx);

  /// Estimates the paper brightness of [image] on a coarse grid: a bright
  /// percentile per block (paper, not ink), spread over neighbouring blocks
  /// (so thick strokes don't count as paper) and smoothed.
  factory EnhanceMap.of(RgbaImage image) {
    final w = image.width, h = image.height;
    final block = math.max(8, (math.max(w, h) / 48).ceil());
    final gw = (w + block - 1) ~/ block, gh = (h + block - 1) ~/ block;
    final raw = Float64List(gw * gh);
    final hist = Int32List(256);
    final stride = block >= 16 ? 2 : 1;
    final px = image.pixels;
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        hist.fillRange(0, 256, 0);
        var n = 0;
        final yEnd = math.min(h, (gy + 1) * block), xEnd = math.min(w, (gx + 1) * block);
        for (var y = gy * block; y < yEnd; y += stride) {
          for (var x = gx * block; x < xEnd; x += stride) {
            final o = (y * w + x) * 4;
            hist[(px[o] * 77 + px[o + 1] * 150 + px[o + 2] * 29) >> 8]++;
            n++;
          }
        }
        raw[gy * gw + gx] = _percentile(hist, n, 0.9).toDouble();
      }
    }
    final paper = _smooth(_dilate(raw, gw, gh), gw, gh);
    // Dark areas (a photo, the table at a page edge) aren't paper: don't
    // stretch them to white.
    final floor = math.max(1.0, 0.4 * paper.reduce(math.max));
    for (var i = 0; i < paper.length; i++) {
      if (paper[i] < floor) paper[i] = floor;
    }
    final cx0 = Int32List(w), cfx = Float32List(w);
    for (var x = 0; x < w; x++) {
      final (i, f) = _cell((x + 0.5) / block - 0.5, gw);
      cx0[x] = i;
      cfx[x] = f;
    }
    return EnhanceMap._(block, gw, gh, paper, cx0, cfx);
  }

  final int _block, _gw, _gh;
  final Float64List _paper;
  final Int32List _cx0;
  final Float32List _cfx;

  /// Output grey by the pixel's brightness relative to the paper's
  /// (0..255 for 0..1): levels (black at 30 %, white at 88 %), then a
  /// gamma that keeps faint strokes visible but dark.
  static final Uint8List _curve = () {
    const black = 0.3, white = 0.88, gamma = 1.3;
    final lut = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      final t = ((i / 255 - black) / (white - black)).clamp(0.0, 1.0);
      lut[i] = (math.pow(t, gamma) * 255).round();
    }
    return lut;
  }();
}

/// Turns rows [y0, y1) of [img] into the document look, in place: grey
/// (R = G = B), paper white, ink dark. [map] comes from `EnhanceMap.of`
/// on the same image.
void enhanceRows(RgbaImage img, EnhanceMap map, int y0, int y1) {
  final w = img.width, px = img.pixels, gw = map._gw;
  final paper = map._paper, cx0 = map._cx0, cfx = map._cfx, curve = EnhanceMap._curve;
  final row = Float64List(gw);
  for (var y = y0; y < y1; y++) {
    final (gy, fy) = _cell((y + 0.5) / map._block - 0.5, map._gh);
    final gy1 = gy + 1 < map._gh ? gy + 1 : gy;
    for (var gx = 0; gx < gw; gx++) {
      final a = paper[gy * gw + gx];
      row[gx] = a + (paper[gy1 * gw + gx] - a) * fy;
    }
    var o = y * w * 4;
    for (var x = 0; x < w; x++) {
      final i = cx0[x];
      final a = row[i];
      final bg = i + 1 < gw ? a + (row[i + 1] - a) * cfx[x] : a;
      final lum = (px[o] * 77 + px[o + 1] * 150 + px[o + 2] * 29) >> 8;
      var t = (lum * 255 / bg).toInt();
      if (t > 255) t = 255;
      final v = curve[t];
      px[o] = v;
      px[o + 1] = v;
      px[o + 2] = v;
      o += 4;
    }
  }
}

/// The grid cell left of / above position [p] (in cells) and the fraction
/// towards the next one, clamped to the [n] cells.
(int, double) _cell(double p, int n) {
  if (p <= 0) return (0, 0);
  if (p >= n - 1) return (n - 1, 0);
  final i = p.floor();
  return (i, p - i);
}

int _percentile(Int32List hist, int n, double q) {
  final target = (n * q).ceil();
  var sum = 0;
  for (var v = 0; v < 256; v++) {
    sum += hist[v];
    if (sum >= target) return v;
  }
  return 255;
}

/// 3 × 3 maximum.
Float64List _dilate(Float64List g, int w, int h) => _neighbourhood(g, w, h, max: true);

/// 3 × 3 mean.
Float64List _smooth(Float64List g, int w, int h) => _neighbourhood(g, w, h, max: false);

/// The maximum or mean of each cell's 3 × 3 neighbourhood (clipped at the
/// grid's edges).
Float64List _neighbourhood(Float64List g, int w, int h, {required bool max}) {
  final out = Float64List(g.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var top = 0.0, sum = 0.0, n = 0;
      for (var j = math.max(0, y - 1); j <= math.min(h - 1, y + 1); j++) {
        for (var i = math.max(0, x - 1); i <= math.min(w - 1, x + 1); i++) {
          final v = g[j * w + i];
          if (v > top) top = v;
          sum += v;
          n++;
        }
      }
      out[y * w + x] = max ? top : sum / n;
    }
  }
  return out;
}
