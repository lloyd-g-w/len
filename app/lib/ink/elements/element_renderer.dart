import 'package:flutter/painting.dart';

import '../../domain/surface_element.dart';
import '../../domain/text_data.dart';
import 'text_layout.dart';

/// Paints surface elements in world coordinates.
///
/// Elements are immutable values, so the text layout of each is memoised
/// per instance (like stroke paths) and rebuilt only for a new value.
abstract final class ElementRenderer {
  static final Expando<TextPainter> _layouts = Expando('element layouts');

  static void draw(Canvas canvas, SurfaceElement element) {
    switch (element.knownType) {
      case ElementType.text:
        _drawRotated(canvas, element, () => _drawText(canvas, element));
      case ElementType.image:
      case null:
        break; // Not supported by this version yet; kept, not drawn.
    }
  }

  static void _drawRotated(Canvas canvas, SurfaceElement e, void Function() paint) {
    canvas.save();
    if (e.rotation != 0) {
      final c = e.rect.center;
      canvas
        ..translate(c.dx, c.dy)
        ..rotate(e.rotation)
        ..translate(-c.dx, -c.dy);
    }
    paint();
    canvas.restore();
  }

  static void _drawText(Canvas canvas, SurfaceElement e) {
    final painter = _layouts[e] ??= TextLayout.layout(TextData.fromJson(e.data), e.rect.width);
    painter.paint(canvas, e.rect.topLeft);
  }
}
