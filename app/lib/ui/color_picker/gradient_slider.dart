import 'package:flutter/material.dart';

import '../app_theme.dart';

/// A horizontal 0..1 slider drawn as a gradient band (hue or opacity),
/// optionally over a checkerboard for transparency, with the sliders' ink
/// tick for a thumb (DESIGN §6): square-ish ([Radii.xs]), like a ruler.
class GradientSlider extends StatelessWidget {
  const GradientSlider({
    super.key,
    required this.value,
    required this.colors,
    required this.onChanged,
    required this.label,
    this.checkerboard = false,
  });

  /// Thumb position, 0..1.
  final double value;

  /// Track gradient, left to right.
  final List<Color> colors;

  /// Called with the new 0..1 value while tapping or dragging.
  final ValueChanged<double> onChanged;

  /// Accessibility label.
  final String label;

  /// Draws a checkerboard under the track, to show transparency.
  final bool checkerboard;

  /// Height of the slider (its hit area, and its thumb's length).
  static const double height = 28;

  /// Height of the gradient band.
  static const double band = 16;

  /// Width of the thumb's tick.
  static const double tick = 4;

  /// The hue spectrum, for a hue slider.
  static const List<Color> hues = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  void _update(double dx, double width) {
    const inset = tick / 2;
    final track = width - 2 * inset;
    if (track <= 0) return; // Too narrow to have a track.
    onChanged(((dx - inset) / track).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: '${(value * 100).round()}%',
      slider: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final scheme = Theme.of(context).colorScheme;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragDown: (d) => _update(d.localPosition.dx, width),
              // Also fires for taps, so no separate tap handler.
              onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, width),
              child: CustomPaint(
                size: Size(width, height),
                painter: _TrackPainter(
                  value: value,
                  colors: colors,
                  ink: scheme.onSurface,
                  surface: Surfaces.overlay(scheme.brightness),
                  edge: scheme.outlineVariant,
                  checkerboard: checkerboard,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.value,
    required this.colors,
    required this.ink,
    required this.surface,
    required this.edge,
    required this.checkerboard,
  });

  final double value;
  final List<Color> colors;

  /// The tick's colour, the hairline of [surface] around it (so it reads
  /// over any hue) and the band's Rule edge.
  final Color ink;
  final Color surface;
  final Color edge;
  final bool checkerboard;

  @override
  void paint(Canvas canvas, Size size) {
    const t = GradientSlider.tick;
    final band = Rect.fromLTWH(
      0,
      (size.height - GradientSlider.band) / 2,
      size.width,
      GradientSlider.band,
    );
    final track = RRect.fromRectAndRadius(band, const Radius.circular(Radii.xs));
    canvas
      ..save()
      ..clipRRect(track);
    if (checkerboard) _paintChecker(canvas, size);
    canvas
      ..drawRect(band, Paint()..shader = LinearGradient(colors: colors).createShader(band))
      ..restore()
      ..drawRRect(
        track.deflate(Hairline.width / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = Hairline.width
          ..color = edge,
      );

    final x = t / 2 + value * (size.width - t);
    final thumb = Rect.fromCenter(
      center: Offset(x, size.height / 2),
      width: t,
      height: size.height,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(thumb.inflate(Hairline.width), const Radius.circular(Radii.xs)),
        Paint()..color = surface,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(thumb, const Radius.circular(Radii.xs / 2)),
        Paint()..color = ink,
      );
  }

  static void _paintChecker(Canvas canvas, Size size) {
    const cell = 7.0;
    final light = Paint()..color = const Color(0xFFFFFFFF);
    final dark = Paint()..color = const Color(0xFFD9DCE1);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = y.isEven ? 0 : 1; x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.value != value ||
      old.ink != ink ||
      old.surface != surface ||
      old.edge != edge ||
      old.checkerboard != checkerboard ||
      !_sameColors(old.colors, colors);

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
