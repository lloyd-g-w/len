import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../render/dashes.dart';
import '../shapes/shape_handles.dart';
import '../viewport.dart';
import 'lasso_path.dart';
import 'selection_chrome.dart';
import 'selection_controller.dart';
import 'selection_frame.dart';

/// Paints the lasso being drawn and the current selection: its content
/// (one cached picture under the gesture's transform — a drag never
/// rebuilds stroke paths) and the dashed frame with its handles; a single
/// shape shows its own points as handles instead of the frame's (lines
/// and arrows show no frame at all).
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

  /// World-space clip for the selected content: the pages it may show on
  /// (a selection can span pages and be dragged from one to another).
  final List<Rect>? clip;

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
    final clip = this.clip;
    if (clip != null) {
      final pages = Path();
      for (final page in clip) {
        pages.addRect(page);
      }
      canvas.clipPath(pages);
    }
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

  Paint get _outline => Paint()
    ..color = accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  static final Paint _shadow = Paint()
    ..color = const Color(0x33000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

  /// A round handle of radius [r] at [at]: paper, ringed in the accent.
  void _knob(Canvas canvas, Offset at, double r) => canvas
    ..drawCircle(at + const Offset(0, 1), r, _shadow)
    ..drawCircle(at, r, Paint()..color = handleFill)
    ..drawCircle(at, r, _outline);

  void _paintFrame(Canvas canvas, SelectionFrame frame) {
    final outline = _outline;
    final shape = selection.shape;
    final handles = SelectionChrome.handles(frame, viewport, shape: shape);
    if (shape == null || shape.kind.isClosed) {
      final corners = [for (final c in frame.corners) viewport.toScreen(c)];
      drawDashed(canvas, corners, outline, close: true);
    }
    final rotate = handles.remove(SelectionHandle.rotate);
    if (rotate != null) {
      final topMid = viewport.toScreen(frame.at(const Offset(0.5, 0)));
      canvas.drawLine(topMid, rotate, outline);
    }
    for (final entry in handles.entries) {
      _knob(canvas, entry.value, entry.key.isCorner ? 6.5 : 5.0);
    }
    if (shape != null) {
      for (final (i, p) in SelectionChrome.shapeHandles(shape, viewport).indexed) {
        if (ShapeHandles.isInner(shape, i)) {
          // The star's inner radius: a small solid dot, apart from its points.
          canvas
            ..drawCircle(p + const Offset(0, 1), 4.5, _shadow)
            ..drawCircle(p, 4.5, Paint()..color = accent);
        } else {
          _knob(canvas, p, 6.5);
        }
      }
    }
    if (rotate != null) _paintRotate(canvas, rotate);
  }

  /// The rotate handle: a filled accent knob with a circular-arrow glyph.
  void _paintRotate(Canvas canvas, Offset rotate) {
    final shadow = _shadow;
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
      !listEquals(old.clip, clip);
}
