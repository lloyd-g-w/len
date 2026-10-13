import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/shapes/shape_builder.dart';
import '../../../ink/tool_settings.dart';

const IconData lassoIcon = Symbols.highlight_alt_rounded;
const IconData textIcon = Symbols.text_fields_rounded;
const IconData laserIcon = Symbols.ads_click_rounded;

/// A shape drawn with the same outline the Shape tool produces, in the
/// ambient icon colour.
class ShapeGlyph extends StatelessWidget {
  const ShapeGlyph(this.kind, {super.key, this.size = 19});

  final ShapeKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ShapeGlyphPainter(kind, color)),
    );
  }
}

class _ShapeGlyphPainter extends CustomPainter {
  _ShapeGlyphPainter(this.kind, this.color);

  final ShapeKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.width * 0.12;
    final open = !kind.isClosed;
    // Lines and arrows run corner to corner; closed shapes fill the box.
    final a = Offset(inset, open ? size.height - inset : inset);
    final b = Offset(size.width - inset, open ? inset : size.height - inset);
    final pts = ShapeBuilder.outline(kind, a, b);
    canvas.drawPath(
      Path()..addPolygon(pts, false),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        // 1.5 px, matching the Symbols at weight 300.
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ShapeGlyphPainter old) => old.kind != kind || old.color != color;
}
