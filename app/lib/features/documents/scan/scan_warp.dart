import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'scan_geometry.dart';
import 'scan_image.dart';

export 'scan_image.dart';

/// Fills rows [y0, y1) of [dst] (the flattened page) from [src]: each output
/// pixel centre is mapped through [pageToSrc] and sampled bilinearly
/// (clamped to the source's edges); alpha is opaque. Where the page is much
/// smaller than the quad it comes from (shrinking by 2× or more), each pixel
/// averages a grid of 2 × 2 or 3 × 3 samples against aliasing.
void warpRows(RgbaImage src, Homography pageToSrc, RgbaImage dst, int y0, int y1) {
  final m = pageToSrc.m;
  final m0 = m[0], m1 = m[1], m2 = m[2], m3 = m[3], m4 = m[4], m5 = m[5];
  final m6 = m[6], m7 = m[7], m8 = m[8];
  final ss = _supersampling(src, pageToSrc, dst);
  final sw = src.width, sh = src.height, sp = src.pixels, dp = dst.pixels;
  final maxX = sw - 1.0, maxY = sh - 1.0;
  final inv = 1 / (ss * ss);
  final step = 1 / ss;
  for (var y = y0; y < y1; y++) {
    var o = y * dst.width * 4;
    for (var x = 0; x < dst.width; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (var j = 0; j < ss; j++) {
        final v = y + (j + 0.5) * step;
        for (var i = 0; i < ss; i++) {
          final u = x + (i + 0.5) * step;
          final w = m6 * u + m7 * v + m8;
          // Source pixel i covers [i, i + 1): its centre is at i + 0.5.
          var sx = (m0 * u + m1 * v + m2) / w - 0.5;
          var sy = (m3 * u + m4 * v + m5) / w - 0.5;
          if (!(sx > 0)) sx = 0; // Also catches NaN.
          if (sx > maxX) sx = maxX;
          if (!(sy > 0)) sy = 0;
          if (sy > maxY) sy = maxY;
          final ix = sx.toInt(), iy = sy.toInt();
          final fx = sx - ix, fy = sy - iy;
          final p00 = (iy * sw + ix) * 4;
          final p01 = ix < sw - 1 ? p00 + 4 : p00;
          final p10 = iy < sh - 1 ? p00 + sw * 4 : p00;
          final p11 = ix < sw - 1 ? p10 + 4 : p10;
          final w00 = (1 - fx) * (1 - fy), w01 = fx * (1 - fy);
          final w10 = (1 - fx) * fy, w11 = fx * fy;
          r += sp[p00] * w00 + sp[p01] * w01 + sp[p10] * w10 + sp[p11] * w11;
          g += sp[p00 + 1] * w00 + sp[p01 + 1] * w01 + sp[p10 + 1] * w10 + sp[p11 + 1] * w11;
          b += sp[p00 + 2] * w00 + sp[p01 + 2] * w01 + sp[p10 + 2] * w10 + sp[p11 + 2] * w11;
        }
      }
      dp[o] = (r * inv + 0.5).toInt();
      dp[o + 1] = (g * inv + 0.5).toInt();
      dp[o + 2] = (b * inv + 0.5).toInt();
      dp[o + 3] = 255;
      o += 4;
    }
  }
}

/// Samples per axis: how many source pixels one page pixel spans, on
/// average (1 up to a 2× shrink, at most 3).
int _supersampling(RgbaImage src, Homography pageToSrc, RgbaImage dst) {
  final w = dst.width.toDouble(), h = dst.height.toDouble();
  final quad = Quad(
    pageToSrc.map(const Offset(0, 0)),
    pageToSrc.map(Offset(w, 0)),
    pageToSrc.map(Offset(w, h)),
    pageToSrc.map(Offset(0, h)),
  );
  final ratio = math.sqrt(quad.area / (w * h));
  return ratio.isFinite ? ratio.floor().clamp(1, 3) : 1;
}
