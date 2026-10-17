import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../domain/shape_geometry.dart';
import '../render/dashes.dart';
import '../shapes/shape_builder.dart';
import '../shapes/shape_handles.dart';
import '../viewport.dart';
import 'connectors.dart';
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
    this.handleScale = 1,
  }) : super(repaint: Listenable.merge([selection, lasso, viewport]));

  final SelectionController selection;
  final LassoPath lasso;
  final ViewportController viewport;
  final Color accent;
  final Color handleFill;

  /// How much larger than with a pointer handles are drawn ([touchScale]
  /// on touch-first devices, where fingers cover them; they are reached
  /// from further away there too, `SelectionChrome.shapeHitRadius`).
  final double handleScale;

  /// [handleScale] on touch-first devices.
  static const double touchScale = 1.25;

  /// World-space clip for the selected content: the pages it may show on
  /// (a selection can span pages and be dragged from one to another).
  final List<Rect>? clip;

  @override
  void paint(Canvas canvas, Size size) {
    _paintContent(canvas);
    _paintLasso(canvas);
    final frame = selection.frame;
    if (frame != null && !selection.isEmpty) _paintFrame(canvas, frame);
    if (selection.attachHint case final hint?) _paintAttachHint(canvas, hint);
  }

  /// The shape a line's end is about to attach to: its outline in the
  /// accent (over a paper band), a solid dot where the end goes.
  void _paintAttachHint(Canvas canvas, AttachHint hint) {
    final outline = [
      for (final p in ShapeBuilder.outline(hint.target.shape!)) viewport.toScreen(p),
    ];
    final line = Path()..addPolygon(outline, false);
    canvas
      ..drawPath(line, _halo..strokeWidth = 5)
      ..drawPath(line, _outline..strokeWidth = 2.5);
    final at = viewport.toScreen(hint.point);
    canvas
      ..drawCircle(at + const Offset(0, 1), 5.5 * handleScale, _shadow)
      ..drawCircle(at, 5.5 * handleScale, Paint()..color = handleFill)
      ..drawCircle(at, 4 * handleScale, Paint()..color = accent);
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
      ..save()
      ..transform(selection.preview.matrix4)
      ..drawPicture(picture)
      ..restore();
    if (selection.followers case final followers?) canvas.drawPicture(followers);
    canvas.restore();
  }

  void _paintLasso(Canvas canvas) {
    if (lasso.points.length < 2) return;
    final pts = [for (final p in lasso.points) viewport.toScreen(p)];
    canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = accent.withValues(alpha: 0.07));
    drawDashed(canvas, pts, _halo);
    drawDashed(canvas, pts, _outline);
  }

  Paint get _outline => Paint()
    ..color = accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  /// Under every accent line: a band of [handleFill] (paper), so the line
  /// keeps its contrast on dark paper, images and ink (UX_AUDIT R23-6: the
  /// accent alone is 2.9:1 on Dark paper).
  Paint get _halo => Paint()
    ..color = handleFill
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.5;

  static final Paint _shadow = Paint()
    ..color = const Color(0x33000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

  /// A round handle of radius [r] at [at]: paper, ringed in the accent.
  void _knob(Canvas canvas, Offset at, double r) => canvas
    ..drawCircle(at + const Offset(0, 1), r * handleScale, _shadow)
    ..drawCircle(at, r * handleScale, Paint()..color = handleFill)
    ..drawCircle(at, r * handleScale, _outline);

  void _paintFrame(Canvas canvas, SelectionFrame frame) {
    final outline = _outline;
    final shape = selection.shape;
    final handles = SelectionChrome.handles(frame, viewport, shape: shape);
    final corners = shape == null || shape.isClosed
        ? [for (final c in frame.corners) viewport.toScreen(c)]
        : null;
    final rotate = handles.remove(SelectionHandle.rotate);
    final topMid = rotate == null ? null : viewport.toScreen(frame.at(const Offset(0.5, 0)));
    // Every band before any line: a band over a line it meets (the rotate
    // stem over the frame's top) would notch it.
    for (final paint in [_halo, outline]) {
      if (corners != null) drawDashed(canvas, corners, paint, close: true);
      if (rotate != null) canvas.drawLine(topMid!, rotate, paint);
    }
    for (final entry in handles.entries) {
      _knob(canvas, entry.value, entry.key.isCorner ? 6.5 : 5.0);
    }
    if (shape != null) _paintShapeHandles(canvas, shape);
    if (rotate != null) _paintRotate(canvas, rotate);
  }

  /// A selected shape's own handles, each looking like what it does:
  /// round knobs for points, smaller ones for sides, a ringed dot for a
  /// centre, a diamond for a radius, a small square for a bend, solid
  /// dots for a star's inner radius and for tangents (on an arm from
  /// their anchor).
  void _paintShapeHandles(Canvas canvas, ShapeGeometry shape) {
    final handles = SelectionChrome.shapeHandles(shape, viewport);
    // Tangent arms first, beneath every knob.
    for (final paint in [_halo, _arm]) {
      for (final h in handles) {
        if (h.handle.anchor case final anchor?) {
          canvas.drawLine(viewport.toScreen(anchor), h.at, paint);
        }
      }
    }
    final fill = Paint()..color = handleFill;
    final solid = Paint()..color = accent;
    final k = handleScale;
    for (final h in handles) {
      final p = h.at;
      switch (h.handle.role) {
        case HandleRole.vertex:
          _knob(canvas, p, 6.5);
        case HandleRole.edge:
          _knob(canvas, p, 4.5);
        case HandleRole.centre:
          _knob(canvas, p, 6.5);
          canvas.drawCircle(p, 2.5 * k, solid);
        case HandleRole.radius:
          final d = 8 * k;
          final diamond = Path()
            ..moveTo(p.dx, p.dy - d)
            ..lineTo(p.dx + d, p.dy)
            ..lineTo(p.dx, p.dy + d)
            ..lineTo(p.dx - d, p.dy)
            ..close();
          canvas
            ..drawPath(diamond.shift(const Offset(0, 1)), _shadow)
            ..drawPath(diamond, fill)
            ..drawPath(diamond, _outline);
        case HandleRole.bend:
          final square = RRect.fromRectAndRadius(
            Rect.fromCenter(center: p, width: 10 * k, height: 10 * k),
            const Radius.circular(2),
          );
          canvas
            ..drawRRect(square.shift(const Offset(0, 1)), _shadow)
            ..drawRRect(square, fill)
            ..drawRRect(square, _outline);
        case HandleRole.inner:
          canvas
            ..drawCircle(p + const Offset(0, 1), 4.5 * k, _shadow)
            ..drawCircle(p, 4.5 * k, solid);
        case HandleRole.tangent:
          canvas
            ..drawCircle(p, 5 * k, fill)
            ..drawCircle(p, 3.5 * k, solid);
      }
    }
  }

  Paint get _arm => Paint()
    ..color = accent
    ..strokeWidth = 1;

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
      old.handleScale != handleScale ||
      !listEquals(old.clip, clip);
}
