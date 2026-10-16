import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';

/// An eraser glyph (a tilted block with a band at its tip), drawn like the
/// Sharp symbols beside it: 1.5-px strokes, square corners, mitred joins.
/// Sized and coloured by [IconTheme]; its `fill` (the active tool) fills
/// the block.
class EraserIcon extends StatelessWidget {
  const EraserIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _EraserPainter(theme.color ?? Tones.light.ink, filled: (theme.fill ?? 0) >= 0.5),
      ),
    );
  }
}

class _EraserPainter extends CustomPainter {
  _EraserPainter(this.color, {required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas
      ..translate(size.width / 2, size.height / 2)
      ..rotate(-math.pi / 4)
      ..scale(s);
    const body = Rect.fromLTWH(-9.5, -4.75, 19, 9.5);
    final fill = Paint()..color = color;
    canvas
      ..drawRect(
        body,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.miter
          ..strokeWidth = 1.5 / s, // 1.5 px on screen, like the symbols
      )
      ..drawRect(filled ? body : Rect.fromLTRB(body.left, body.top, -3, body.bottom), fill);
  }

  @override
  bool shouldRepaint(_EraserPainter old) => old.color != color || old.filled != filled;
}
