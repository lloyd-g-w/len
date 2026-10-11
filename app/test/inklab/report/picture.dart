import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../metrics/outline_geometry.dart';
import '../metrics/raster.dart';

/// Report colours (ARGB).
abstract final class Ink {
  static const int paper = 0xFFFFFFFF;
  static const int ink = 0xFF5A6273;
  static const int inkLight = 0xFFD5D9E0;
  static const int truth = 0xFF00A050;
  static const int raw = 0xFFE0302A;
  static const int centre = 0xFF2F6FE0;
  static const int changed = 0xFFE0302A;
  static const int nearTip = 0xFF3D8BFF;
  static const int pop = 0xFFC020C0;
  static const int overlay = 0x802F6FE0;
  static const int gap = 0xFFFF9900;
}

/// A small software canvas for report images: anti-aliased fills of
/// [Coverage] rasters, thin lines and dots, written as PNG. Pure Dart, so
/// the pictures are deterministic and need no GPU.
class Picture {
  Picture(this.width, this.height, {int background = Ink.paper})
    : _rgb = Float32List(width * height * 3) {
    for (var i = 0; i < width * height; i++) {
      _rgb[i * 3] = _r(background);
      _rgb[i * 3 + 1] = _g(background);
      _rgb[i * 3 + 2] = _b(background);
    }
  }

  final int width, height;
  final Float32List _rgb;

  static double _a(int c) => (c >>> 24) / 255;
  static double _r(int c) => ((c >> 16) & 0xFF) / 255;
  static double _g(int c) => ((c >> 8) & 0xFF) / 255;
  static double _b(int c) => (c & 0xFF) / 255;

  /// Blends [color] into pixel ([x], [y]) with extra opacity [alpha].
  void blend(int x, int y, int color, double alpha) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final a = (alpha * _a(color)).clamp(0.0, 1.0);
    if (a <= 0) return;
    final i = (y * width + x) * 3;
    _rgb[i] += (_r(color) - _rgb[i]) * a;
    _rgb[i + 1] += (_g(color) - _rgb[i + 1]) * a;
    _rgb[i + 2] += (_b(color) - _rgb[i + 2]) * a;
  }

  /// Fills [contours] (already in this picture's pixels) with [color].
  void fill(List<Contour> contours, int color) {
    final view = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final visible = [
      for (final c in contours)
        if (boundsOf([c]).overlaps(view)) c,
    ];
    if (visible.isEmpty) return;
    final cov = Coverage(0, 0, width, height)..fill(visible);
    paint(cov, color);
  }

  /// Paints [cov] (whose grid is this picture's pixels) in [color].
  void paint(Coverage cov, int color) {
    for (var y = 0; y < cov.height; y++) {
      for (var x = 0; x < cov.width; x++) {
        final v = cov.values[y * cov.width + x];
        if (v > 0) blend(x + cov.left, y + cov.top, color, v);
      }
    }
  }

  /// An anti-aliased polyline [thickness] pixels wide.
  void line(List<Offset> points, int color, {double thickness = 1}) {
    final h = thickness / 2;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final x0 = (math.min(a.dx, b.dx) - h - 1).floor(), x1 = (math.max(a.dx, b.dx) + h + 1).ceil();
      final y0 = (math.min(a.dy, b.dy) - h - 1).floor(), y1 = (math.max(a.dy, b.dy) + h + 1).ceil();
      if (x1 < 0 || y1 < 0 || x0 >= width || y0 >= height) continue;
      for (var y = math.max(0, y0); y <= math.min(height - 1, y1); y++) {
        for (var x = math.max(0, x0); x <= math.min(width - 1, x1); x++) {
          final d = _segDist(Offset(x + 0.5, y + 0.5), a, b);
          final cover = (h + 0.5 - d).clamp(0.0, 1.0);
          // Joints: keep the darker of overlapping segments (no double blend).
          if (cover > 0 && (i == 1 || _segDist(Offset(x + 0.5, y + 0.5), points[i - 2], a) > h)) {
            blend(x, y, color, cover);
          }
        }
      }
    }
  }

  /// An anti-aliased filled circle.
  void dot(Offset c, double radius, int color) {
    for (var y = (c.dy - radius - 1).floor(); y <= (c.dy + radius + 1).ceil(); y++) {
      for (var x = (c.dx - radius - 1).floor(); x <= (c.dx + radius + 1).ceil(); x++) {
        final d = (Offset(x + 0.5, y + 0.5) - c).distance;
        blend(x, y, color, (radius + 0.5 - d).clamp(0.0, 1.0));
      }
    }
  }

  /// A one-pixel frame around the picture.
  void frame(int color) {
    for (var x = 0; x < width; x++) {
      blend(x, 0, color, 1);
      blend(x, height - 1, color, 1);
    }
    for (var y = 0; y < height; y++) {
      blend(0, y, color, 1);
      blend(width - 1, y, color, 1);
    }
  }

  /// Copies [other] in at ([left], [top]).
  void place(Picture other, int left, int top) {
    for (var y = 0; y < other.height; y++) {
      for (var x = 0; x < other.width; x++) {
        final tx = left + x, ty = top + y;
        if (tx < 0 || ty < 0 || tx >= width || ty >= height) continue;
        final s = (y * other.width + x) * 3, d = (ty * width + tx) * 3;
        _rgb[d] = other._rgb[s];
        _rgb[d + 1] = other._rgb[s + 1];
        _rgb[d + 2] = other._rgb[s + 2];
      }
    }
  }

  /// Writes the picture as a PNG to [path].
  void save(String path) {
    final out = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 3;
        out.setPixelRgb(x, y, _byte(_rgb[i]), _byte(_rgb[i + 1]), _byte(_rgb[i + 2]));
      }
    }
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(out));
  }

  static int _byte(double v) => (v.clamp(0.0, 1.0) * 255).round();

  static double _segDist(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

/// Tiles [pictures] in a grid [columns] wide with [gap] pixels between.
Picture sheet(List<Picture> pictures, {int columns = 4, int gap = 6}) {
  if (pictures.isEmpty) return Picture(1, 1);
  final cw = pictures.map((p) => p.width).reduce(math.max);
  final ch = pictures.map((p) => p.height).reduce(math.max);
  final cols = math.min(columns, pictures.length);
  final rows = (pictures.length / cols).ceil();
  final out = Picture(cols * (cw + gap) + gap, rows * (ch + gap) + gap, background: 0xFFEEF0F3);
  for (var i = 0; i < pictures.length; i++) {
    out.place(pictures[i], gap + (i % cols) * (cw + gap), gap + (i ~/ cols) * (ch + gap));
  }
  return out;
}

/// Maps logical screen px to picture px: `(p − origin) × scale`.
class View {
  const View(this.origin, this.scale);

  /// A view of [area] (logical px) [scale] picture px per logical px.
  View.of(Rect area, this.scale) : origin = area.topLeft;

  final Offset origin;
  final double scale;

  Offset call(Offset p) => (p - origin) * scale;

  /// Picture size for [area] at this scale.
  static (int, int) sizeOf(Rect area, double scale) =>
      (math.max(1, (area.width * scale).ceil()), math.max(1, (area.height * scale).ceil()));
}
