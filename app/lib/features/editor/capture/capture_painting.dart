import 'package:flutter/rendering.dart';

import '../../../ui/app_theme.dart';

/// Dims all but the [area] marked, edged in the accent.
class CaptureAreaPainter extends CustomPainter {
  CaptureAreaPainter({required this.area, required this.scrim, required this.edge});

  final Rect? area;
  final Color scrim;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    final area = this.area;
    final path = Path()..addRect(all);
    if (area != null) {
      path
        ..addRect(area)
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, Paint()..color = scrim);
    if (area == null) return;
    canvas.drawRect(
      area,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = Hairline.rule,
    );
  }

  @override
  bool shouldRepaint(CaptureAreaPainter old) =>
      old.area != area || old.scrim != scrim || old.edge != edge;
}

/// Places the result bar centred below the area, else above it, else
/// inside its bottom; always within [free].
class CaptureBarLayout extends SingleChildLayoutDelegate {
  CaptureBarLayout(this.area, this.free);

  final Rect area;
  final Rect free;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final room = free.deflate(Gaps.sm);
    final maxX = room.right - childSize.width;
    final x = (area.center.dx - childSize.width / 2).clamp(
      room.left,
      maxX < room.left ? room.left : maxX,
    );
    var y = area.bottom + Gaps.sm;
    if (y + childSize.height > room.bottom) y = area.top - Gaps.sm - childSize.height;
    if (y < room.top) y = (area.bottom - Gaps.sm - childSize.height).clamp(room.top, room.bottom);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(CaptureBarLayout old) => old.area != area || old.free != free;
}
