import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../render/dashes.dart';
import '../viewport.dart';
import 'lasso_path.dart';
import 'selection_chrome.dart';
import 'selection_controller.dart';
import 'selection_frame.dart';

/// Paints the lasso being drawn and the current selection: its content
/// (one cached picture under the gesture's transform — a drag never
/// rebuilds stroke paths) and the dashed frame with its handles.
class SelectionPainter extends CustomPainter {
  SelectionPainter({
    required this.selection,
    required this.lasso,
    required this.viewport,
    required this.accent,
    required this.handleFill,
    this.clip,
  }) : super(repaint: Listenable.merge([selection, lasso, viewport]));

  final SelectionController selection;
  final LassoPath lasso;
  final ViewportController viewport;
  final Color accent;
  final Color handleFill;

  /// World-space clip (the page) for the selected content.
  final Rect? clip;

  @override
  void paint(Canvas canvas, Size size) {
    _paintContent(canvas);
    _paintLasso(canvas);
    final frame = selection.frame;
    if (frame != null && !selection.isEmpty) _paintFrame(canvas, frame);
  }

  void _paintContent(Canvas canvas) {
    final picture = selection.picture;
    if (picture == null) return;
    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(viewport.scale);
    if (clip != null) canvas.clipRect(clip!);
    canvas
      ..transform(selection.preview.matrix4)
      ..drawPicture(picture)
      ..restore();
  }

  void _paintLasso(Canvas canvas) {
    if (lasso.points.length < 2) return;
    final pts = [for (final p in lasso.points) viewport.toScreen(p)];
    canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = accent.withValues(alpha: 0.07));
    drawDashed(
      canvas,
      pts,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintFrame(Canvas canvas, SelectionFrame frame) {
    final outline = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final corners = [for (final c in frame.corners) viewport.toScreen(c)];
    drawDashed(canvas, corners, outline, close: true);

    final handles = SelectionChrome.handles(frame, viewport);
    final rotate = handles.remove(SelectionHandle.rotate)!;
    final topMid = viewport.toScreen(frame.at(const Offset(0.5, 0)));
    canvas.drawLine(topMid, rotate, outline);

    final fill = Paint()..color = handleFill;
    final shadow = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    for (final entry in handles.entries) {
      final r = entry.key.isCorner ? 6.5 : 5.0;
      canvas
        ..drawCircle(entry.value + const Offset(0, 1), r, shadow)
        ..drawCircle(entry.value, r, fill)
        ..drawCircle(entry.value, r, outline);
    }
    // Rotate handle: a filled accent knob with a circular-arrow glyph.
    canvas
      ..drawCircle(rotate + const Offset(0, 1), 9, shadow)
      ..drawCircle(rotate, 9, Paint()..color = accent);
    final glyph = Paint()
      ..color = handleFill
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final arc = Rect.fromCircle(center: rotate, radius: 4.5);
    canvas.drawArc(arc, -math.pi * 0.35, math.pi * 1.5, false, glyph);
    final tip = rotate + Offset.fromDirection(-math.pi * 0.35, 4.5);
    canvas
      ..drawLine(tip, tip + const Offset(2.8, -0.6), glyph)
      ..drawLine(tip, tip + const Offset(0.6, -2.8), glyph);
  }

  @override
  bool shouldRepaint(SelectionPainter old) =>
      old.selection != selection ||
      old.lasso != lasso ||
      old.viewport != viewport ||
      old.accent != accent ||
      old.handleFill != handleFill ||
      old.clip != clip;
}
