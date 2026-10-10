import 'package:flutter/material.dart';

/// A horizontal 0..1 slider drawn as a rounded gradient track (hue or
/// opacity), optionally over a checkerboard for transparency.
class GradientSlider extends StatelessWidget {
  const GradientSlider({
    super.key,
    required this.value,
    required this.colors,
    required this.thumbColor,
    required this.onChanged,
    required this.label,
    this.checkerboard = false,
  });

  /// Thumb position, 0..1.
  final double value;

  /// Track gradient, left to right.
  final List<Color> colors;

  /// Fill of the thumb (usually the colour at [value]).
  final Color thumbColor;

  /// Called with the new 0..1 value while tapping or dragging.
  final ValueChanged<double> onChanged;

  /// Accessibility label.
  final String label;

  /// Draws a checkerboard under the track, to show transparency.
  final bool checkerboard;

  /// Height of the slider (and diameter of its thumb).
  static const double height = 28;

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
    const inset = height / 2;
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
                  thumbColor: thumbColor,
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
    required this.thumbColor,
    required this.checkerboard,
  });

  final double value;
  final List<Color> colors;
  final Color thumbColor;
  final bool checkerboard;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final track = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));
    canvas
      ..save()
      ..clipRRect(track);
    if (checkerboard) _paintChecker(canvas, size);
    canvas
      ..drawRect(
        Offset.zero & size,
        Paint()..shader = LinearGradient(colors: colors).createShader(Offset.zero & size),
      )
      ..restore()
      ..drawRRect(
        track,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x22000000),
      );

    final center = Offset(r + value * (size.width - 2 * r), r);
    canvas
      ..drawCircle(center, r - 1, Paint()..color = const Color(0x33000000))
      ..drawCircle(center, r - 2, Paint()..color = Colors.white)
      ..drawCircle(center, r - 6, Paint()..color = thumbColor);
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
      old.thumbColor != thumbColor ||
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
