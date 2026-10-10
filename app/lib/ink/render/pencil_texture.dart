import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A procedurally generated, tileable graphite grain used to texture pencil
/// strokes.
///
/// The texture is an alpha mask (white with varying opacity) created once,
/// synchronously, from a recorded picture; strokes tint it with their
/// colour through a colour filter. The same seed is used everywhere, so a
/// pencil stroke looks identical on every device. The grain is anchored to
/// world coordinates, so it does not "swim" when panning, and adjacent
/// chunk pictures line up seamlessly.
abstract final class PencilTexture {
  /// Texture size in pixels (a power of two keeps tiling cheap).
  static const int size = 128;

  /// World units covered by one texel.
  static const double texel = 0.32;

  static ui.Image? _image;

  /// The shared grain image.
  static ui.Image get image => _image ??= _generate();

  /// A shader painting the grain in world coordinates.
  static ui.Shader shader() => ui.ImageShader(
    image,
    ui.TileMode.repeated,
    ui.TileMode.repeated,
    Float64List.fromList([
      texel, 0, 0, 0, //
      0, texel, 0, 0, //
      0, 0, 1, 0, //
      0, 0, 0, 1, //
    ]),
    filterQuality: ui.FilterQuality.low,
  );

  /// Builds the mask: a mostly solid base with paper-tooth "valleys" where
  /// the graphite skips, plus fine speckle. Grouping texels by alpha level
  /// lets each level be drawn with a single `drawRawPoints` call.
  static ui.Image _generate() {
    final random = math.Random(0x1E4);
    final coarse = _valueNoise(random, cells: 16);
    const levels = 8;
    final buckets = List.generate(levels, (_) => <double>[]);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final tooth = coarse(x / size, y / size); // 0..1, smooth
        final speck = random.nextDouble();
        // Valleys of the paper tooth hold less graphite; speckle breaks up
        // the edges so the stroke reads as grainy rather than blotchy.
        var a = 0.92 - 0.55 * math.pow(tooth, 2.2) - 0.35 * speck * speck;
        a = a.clamp(0.08, 1.0);
        final level = (a * (levels - 1)).round();
        buckets[level].addAll([x + 0.5, y + 0.5]);
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..strokeWidth = 1
      ..strokeCap = ui.StrokeCap.square
      ..isAntiAlias = false;
    for (var l = 0; l < levels; l++) {
      if (buckets[l].isEmpty) continue;
      paint.color = ui.Color.fromARGB((255 * l / (levels - 1)).round(), 255, 255, 255);
      canvas.drawRawPoints(ui.PointMode.points, Float32List.fromList(buckets[l]), paint);
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return image;
  }

  /// Tileable bilinear value noise on a `cells × cells` lattice.
  static double Function(double u, double v) _valueNoise(math.Random random, {required int cells}) {
    final lattice = List.generate(cells * cells, (_) => random.nextDouble());
    double at(int x, int y) => lattice[(y % cells) * cells + (x % cells)];
    double smooth(double t) => t * t * (3 - 2 * t);
    return (u, v) {
      final fx = u * cells, fy = v * cells;
      final x0 = fx.floor(), y0 = fy.floor();
      final tx = smooth(fx - x0), ty = smooth(fy - y0);
      final top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * tx;
      final bottom = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * tx;
      return top + (bottom - top) * ty;
    };
  }
}
