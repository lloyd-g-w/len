import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The slider's thumb (DESIGN §6): an ink tick, [width] × [height], like
/// the mark on a ruler, with a hairline of the surface around it so it
/// reads where it crosses the track. Disabled, it fades with the track.
class RuleThumbShape extends SliderComponentShape {
  const RuleThumbShape({this.width = 4, this.height = 20});

  final double width;
  final double height;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(width, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final enabled = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    ).evaluate(enableAnimation);
    // Pressed or dragged, the tick grows a little: the feedback is the mark
    // itself, not a halo.
    final grow = 1 + 0.15 * activationAnimation.value;
    final rect = Rect.fromCenter(center: center, width: width, height: height * grow);
    final outline = sliderTheme.overlappingShapeStrokeColor;
    if (outline != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(Hairline.width), const Radius.circular(Radii.xs)),
        Paint()..color = outline,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(Radii.xs / 2)),
      Paint()..color = enabled ?? const Color(0xFF000000),
    );
  }
}

/// A slider overlay that paints nothing but keeps [radius] of room at each
/// end of the track, so the thumb is never cut off (the focus ring and the
/// thumb's growth give the feedback).
class QuietSliderOverlay extends SliderComponentShape {
  const QuietSliderOverlay({this.radius = 10});

  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {}
}
