import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An eraser glyph (a tilted block with a band at its tip), drawn to match
/// the rounded Material icons; sized and coloured by [IconTheme].
class EraserIcon extends StatelessWidget {
  const EraserIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _EraserPainter(theme.color ?? Colors.black)),
    );
  }
}

class _EraserPainter extends CustomPainter {
  _EraserPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas
      ..translate(size.width / 2, size.height / 2)
      ..rotate(-math.pi / 4)
      ..scale(s);
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-10, -5, 20, 10),
      const Radius.circular(2.5),
    );
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / s; // 1.5 px on screen, like the symbols
    canvas
      ..drawRRect(body, stroke)
      ..save()
      ..clipRRect(body)
      ..drawRect(const Rect.fromLTWH(-10, -5, 7, 10), Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_EraserPainter old) => old.color != color;
}
