import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/cover_style.dart';

/// Paints the subtle print of a [CoverStyle] over a notebook cover.
class CoverPatternPainter extends CustomPainter {
  const CoverPatternPainter(this.style, {this.opacity = 0.16});

  final CoverStyle style;

  /// Opacity of the white print.
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.max(size.shortestSide / 12, 7.0); // Scales with the cover.
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = math.max(1, unit * 0.08)
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    switch (style) {
      case CoverStyle.plain:
        break;
      case CoverStyle.linen:
        paint.strokeWidth = math.max(0.6, unit * 0.04);
        for (var d = -size.height; d < size.width; d += unit * 0.35) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), paint);
        }
        paint.color = Colors.black.withValues(alpha: opacity * 0.5);
        for (var d = 0.0; d < size.width + size.height; d += unit * 0.35) {
          canvas.drawLine(Offset(d, 0), Offset(d - size.height, size.height), paint);
        }
      case CoverStyle.dots:
        paint.style = PaintingStyle.fill;
        final step = unit * 1.1;
        for (var y = step / 2; y < size.height; y += step) {
          for (var x = step / 2; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), unit * 0.12, paint);
          }
        }
      case CoverStyle.grid:
        paint.color = Colors.white.withValues(alpha: opacity * 0.6);
        final step = unit * 1.1;
        for (var x = step; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case CoverStyle.waves:
        paint.strokeWidth = math.max(1, unit * 0.12);
        for (var y = unit; y < size.height + unit; y += unit * 1.2) {
          final path = Path()..moveTo(0, y);
          var up = true;
          for (var x = 0.0; x <= size.width + unit; x += unit, up = !up) {
            path.quadraticBezierTo(x + unit / 2, y + (up ? -unit : unit) * 0.4, x + unit, y);
          }
          canvas.drawPath(path, paint);
        }
      case CoverStyle.stripes:
        paint
          ..style = PaintingStyle.fill
          ..color = Colors.white.withValues(alpha: opacity * 0.8);
        final band = unit * 0.9;
        for (var d = -size.height; d < size.width; d += band * 2.4) {
          canvas.drawPath(
            Path()
              ..moveTo(d, size.height)
              ..lineTo(d + band, size.height)
              ..lineTo(d + band + size.height, 0)
              ..lineTo(d + size.height, 0)
              ..close(),
            paint,
          );
        }
    }
  }

  @override
  bool shouldRepaint(CoverPatternPainter old) => old.style != style || old.opacity != opacity;
}
