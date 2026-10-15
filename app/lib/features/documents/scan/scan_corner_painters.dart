import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'scan_corner_editor.dart';

/// Draws [photo] into [fit]; with [only], just the part of it inside that
/// rectangle (same coordinates as [fit]).
void _drawPhoto(Canvas canvas, ui.Image? photo, Rect fit, {Rect? only}) {
  if (photo == null || fit.isEmpty) return;
  final dst = only == null ? fit : fit.intersect(only);
  if (dst.isEmpty) return;
  final kx = photo.width / fit.width, ky = photo.height / fit.height;
  final src = Rect.fromLTRB(
    (dst.left - fit.left) * kx,
    (dst.top - fit.top) * ky,
    (dst.right - fit.left) * kx,
    (dst.bottom - fit.top) * ky,
  );
  canvas.drawImageRect(photo, src, dst, Paint()..filterQuality = FilterQuality.medium);
}

/// The photo alone, behind a repaint boundary: repainted only when the
/// photo or its place changes.
class ScanPhotoPainter extends CustomPainter {
  ScanPhotoPainter({required this.photo, required this.fit});

  final ui.Image? photo;
  final Rect fit;

  @override
  void paint(Canvas canvas, Size size) => _drawPhoto(canvas, photo, fit);

  @override
  bool shouldRepaint(ScanPhotoPainter old) => old.photo != photo || old.fit != fit;
}

/// The outline over the photo (dimming outside it), the handles and the
/// loupe (which draws the photo again, enlarged and clipped).
class ScanCornerPainter extends CustomPainter {
  ScanCornerPainter({
    required this.photo,
    required this.fit,
    required this.quad,
    required this.active,
    required this.loupe,
    required this.brightness,
    required this.edge,
  });

  final ui.Image? photo;
  final Rect fit;

  /// The handles on screen: corners 0..3, then the sides' middles.
  final List<Offset> quad;
  final int? active;
  final bool loupe;
  final Brightness brightness;
  final Color edge;

  // Handles sit on the photo, not the chrome: fixed colours, as in image crop.
  static const Color _accent = AppTheme.seed;

  @override
  void paint(Canvas canvas, Size size) {
    _scene(canvas);
    if (loupe && active != null) _loupe(canvas, size, quad[active!]);
  }

  /// The dimming outside the outline, the outline [line] wide and (with
  /// [handles]) the handles; with [photoIn], the photo beneath them, as
  /// much of it as lies in that rectangle.
  void _scene(Canvas canvas, {Rect? photoIn, bool handles = true, double line = Hairline.rule}) {
    if (photoIn != null) _drawPhoto(canvas, photo, fit, only: photoIn);
    final outline = Path()..addPolygon(quad.sublist(0, 4), true);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(fit)
        ..addPath(outline, Offset.zero),
      Paint()..color = Palette.cropShade,
    );
    final stroke = Paint()
      ..color = _accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = line;
    canvas.drawPath(outline, stroke);
    if (!handles) return;
    final fill = Paint()..color = Palette.paper;
    for (final (i, p) in quad.indexed) {
      final r = i < 4 ? (i == active ? 9.0 : 7.0) : (i == active ? 7.0 : 5.5);
      canvas
        ..drawCircle(p, r, fill)
        ..drawCircle(p, r, stroke);
    }
  }

  /// The spot around [at] enlarged, in the top corner away from it.
  void _loupe(Canvas canvas, Size size, Offset at) {
    const side = ScanCornerEditor.loupeSize, inset = Gaps.md;
    final left = at.dx < size.width / 2 ? size.width - side - inset : inset;
    final box = Rect.fromLTWH(left, inset, side, side);
    final shape = RRect.fromRectAndRadius(box, const Radius.circular(Radii.md));
    for (final shadow in Shadows.low(brightness)) {
      canvas.drawRRect(shape.shift(shadow.offset), shadow.toPaint());
    }
    canvas
      ..save()
      ..clipRRect(shape)
      ..drawColor(Surfaces.canvasBackdrop(brightness), BlendMode.src)
      ..translate(box.center.dx, box.center.dy)
      ..scale(ScanCornerEditor.loupeZoom)
      ..translate(-at.dx, -at.dy);
    // A hairline outline however enlarged, so the paper's edge shows.
    _scene(
      canvas,
      photoIn: Rect.fromCenter(
        center: at,
        width: side / ScanCornerEditor.loupeZoom,
        height: side / ScanCornerEditor.loupeZoom,
      ),
      handles: false,
      line: Hairline.width / ScanCornerEditor.loupeZoom,
    );
    canvas.restore();
    // Crosshair on the corner.
    final cross = Paint()
      ..color = _accent
      ..strokeWidth = Hairline.width;
    const arm = Gaps.sm;
    canvas
      ..drawLine(box.center - const Offset(arm, 0), box.center + const Offset(arm, 0), cross)
      ..drawLine(box.center - const Offset(0, arm), box.center + const Offset(0, arm), cross)
      ..drawRRect(
        shape,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = Hairline.width,
      );
  }

  @override
  bool shouldRepaint(ScanCornerPainter old) =>
      old.photo != photo ||
      old.fit != fit ||
      !_same(old.quad, quad) ||
      old.active != active ||
      old.loupe != loupe ||
      old.brightness != brightness ||
      old.edge != edge;

  static bool _same(List<Offset> a, List<Offset> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return a.length == b.length;
  }
}
