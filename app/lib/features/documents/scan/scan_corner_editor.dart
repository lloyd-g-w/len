import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'scan_job.dart';

/// Shows a photo with the document's outline over it: the four corners
/// and the middles of the four sides can be dragged (a side moves both its
/// corners). Outside the outline is dimmed; while a corner moves, a loupe
/// in the top corner away from it shows the spot enlarged.
///
/// [quad] is in [photoSize] pixels; [onChanged] hears every move
/// (`done` false) and the end of a drag (`done` true). Moves that would
/// fold the outline over (not convex) are refused; corners stay on the
/// photo.
class ScanCornerEditor extends StatefulWidget {
  const ScanCornerEditor({
    super.key,
    required this.photo,
    required this.photoSize,
    required this.quad,
    required this.onChanged,
  });

  /// The photo as decoded for showing (any resolution).
  final ui.Image? photo;

  /// The photo's size in the pixels [quad] is in.
  final Size photoSize;
  final Quad quad;
  final void Function(Quad quad, {required bool done}) onChanged;

  /// Room around the photo, so handles on its edges can be grabbed.
  static const double margin = Gaps.xl;

  /// Side of the loupe.
  static const double loupeSize = 112;

  /// Magnification of the loupe over the photo as shown.
  static const double loupeZoom = 3;

  @override
  State<ScanCornerEditor> createState() => _ScanCornerEditorState();
}

class _ScanCornerEditorState extends State<ScanCornerEditor> {
  /// The handle being dragged: 0..3 corners, 4..7 sides (side i runs from
  /// corner i to corner i + 1).
  int? _handle;
  int? _pointer;
  Offset _grab = Offset.zero;
  Offset _last = Offset.zero;
  bool _moved = false;
  int? _hover;

  /// Where the photo is shown in this widget, and its pixels' scale.
  Rect _fit = Rect.zero;
  double get _k => _fit.width / widget.photoSize.width;

  Offset _toScreen(Offset p) => _fit.topLeft + p * _k;
  Offset _toPhoto(Offset s) => (s - _fit.topLeft) / _k;

  static double get _hitRadius => Targets.touchFirst ? 28 : 16;

  List<Offset> _handles(Quad quad) {
    final c = quad.corners.map(_toScreen).toList();
    return [...c, for (var i = 0; i < 4; i++) (c[i] + c[(i + 1) % 4]) / 2];
  }

  int? _handleAt(Offset at) {
    int? best;
    var bestDistance = _hitRadius;
    for (final (i, p) in _handles(widget.quad).indexed) {
      final d = (p - at).distance;
      // Corners win over sides at the same distance.
      if (d < bestDistance || (i < 4 && best != null && best >= 4 && d <= bestDistance + 4)) {
        best = i;
        bestDistance = d;
      }
    }
    return best;
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return; // One handle at a time.
    final handle = _handleAt(e.localPosition);
    if (handle == null) return;
    setState(() {
      _pointer = e.pointer;
      _handle = handle;
      _grab = _handles(widget.quad)[handle] - e.localPosition;
      _last = e.localPosition;
      _moved = false;
    });
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final handle = _handle!;
    final quad = widget.quad;
    final Quad moved;
    if (handle < 4) {
      moved = quad.withCorner(handle, _clamp(_toPhoto(e.localPosition + _grab)));
    } else {
      final i = handle - 4, j = (handle - 3) % 4;
      final delta = _sideDelta(quad, i, j, (e.localPosition - _last) / _k);
      moved = quad.withCorner(i, quad.corners[i] + delta).withCorner(j, quad.corners[j] + delta);
    }
    _last = e.localPosition;
    if (!moved.isConvex || moved == quad) return;
    _moved = true;
    widget.onChanged(moved, done: false);
  }

  /// [delta] for side [i]–[j], shortened so both its corners stay on the
  /// photo.
  Offset _sideDelta(Quad quad, int i, int j, Offset delta) {
    final a = quad.corners[i], b = quad.corners[j];
    final w = widget.photoSize.width, h = widget.photoSize.height;
    final dx = delta.dx.clamp(-math.min(a.dx, b.dx), w - math.max(a.dx, b.dx));
    final dy = delta.dy.clamp(-math.min(a.dy, b.dy), h - math.max(a.dy, b.dy));
    return Offset(dx, dy);
  }

  Offset _clamp(Offset p) =>
      Offset(p.dx.clamp(0, widget.photoSize.width), p.dy.clamp(0, widget.photoSize.height));

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    setState(() {
      _pointer = null;
      _handle = null;
    });
    if (_moved) widget.onChanged(widget.quad, done: true);
  }

  void _hovered(PointerHoverEvent e) {
    final handle = _handleAt(e.localPosition);
    if (handle != _hover) setState(() => _hover = handle);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = (Offset.zero & constraints.biggest).deflate(ScanCornerEditor.margin);
        final fitted = applyBoxFit(BoxFit.contain, widget.photoSize, room.size).destination;
        _fit = Alignment.center.inscribe(fitted, room);
        return Semantics(
          label: 'Page corners, drag to adjust',
          child: MouseRegion(
            cursor: _hover != null || _handle != null ? SystemMouseCursors.move : MouseCursor.defer,
            onHover: _hovered,
            onExit: (_) => setState(() => _hover = null),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: CustomPaint(
                size: constraints.biggest,
                painter: _CornerPainter(
                  photo: widget.photo,
                  fit: _fit,
                  quad: _handles(widget.quad),
                  active: _handle,
                  loupe: _handle != null && _handle! < 4,
                  brightness: Theme.of(context).brightness,
                  edge: Surfaces.border(scheme)?.color ?? scheme.outlineVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({
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

  /// The photo, dimmed outside the outline, the outline [line] wide and
  /// (with [handles]) the handles.
  void _scene(Canvas canvas, {bool handles = true, double line = Hairline.rule}) {
    final image = photo;
    if (image != null) {
      final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      canvas.drawImageRect(image, src, fit, Paint()..filterQuality = FilterQuality.medium);
    }
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
    _scene(canvas, handles: false, line: Hairline.width / ScanCornerEditor.loupeZoom);
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
  bool shouldRepaint(_CornerPainter old) =>
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
