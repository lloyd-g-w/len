part of 'tool_icons.dart';

/// The glyphs' grid, margin and stroke, in grid units (a 24-unit square).
const double _grid = 24;
const double _margin = 2;
const double _stroke = 1.75;

/// A glyph line: [_stroke] grid units wide on a canvas of [unit] (1 when
/// the canvas is already scaled to the grid), square ends, mitred corners.
Paint _line(Color color, [double unit = 1]) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = _stroke * unit
  ..strokeCap = StrokeCap.square
  ..strokeJoin = StrokeJoin.miter;

class _ToolIconPainter extends CustomPainter {
  _ToolIconPainter(this.kind, this.color, {required this.filled});

  final ToolIconKind kind;
  final Color color;
  final bool filled;

  late final Paint _ink = _line(color);
  late final Paint _solid = Paint()..color = color;

  /// Open lines that end in the middle of nothing (dashes, a tail): flat ends.
  late final Paint _rope = _line(color)..strokeCap = StrokeCap.butt;

  /// Cuts details out of a solid body (the selected instruments).
  late final Paint _cut = _line(color)
    ..blendMode = BlendMode.clear
    ..strokeWidth = 1.25;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..saveLayer(Offset.zero & size, Paint())
      ..scale(size.width / _grid);
    switch (kind) {
      case ToolIconKind.pen:
        _held(canvas, _pen);
      case ToolIconKind.highlighter:
        _held(canvas, _highlighter);
      case ToolIconKind.eraser:
        _held(canvas, _eraser);
      case ToolIconKind.laser:
        _held(canvas, _laser);
      case ToolIconKind.lasso:
        _lasso(canvas);
      case ToolIconKind.lassoRectangle:
        _marquee(canvas);
      case ToolIconKind.text:
        _text(canvas);
      case ToolIconKind.insert:
        _insert(canvas);
      case ToolIconKind.eraseStroke:
        canvas.drawPath(_squiggle(), _ink);
      case ToolIconKind.erasePartial:
        _partial(canvas);
      case ToolIconKind.laserDot:
        canvas.drawCircle(const Offset(12, 12), 3.5, _solid);
      case ToolIconKind.laserTrail:
        _trail(canvas);
    }
    canvas.restore();
  }

  /// Draws an instrument along a vertical axis through the grid's centre,
  /// writing end down (+y), then turns it 45° so it points down-left.
  void _held(Canvas canvas, void Function(Canvas) draw) {
    canvas
      ..save()
      ..translate(_grid / 2, _grid / 2)
      ..rotate(math.pi / 4);
    draw(canvas);
    canvas.restore();
  }

  /// A body outlined, or solid when selected.
  void _body(Canvas canvas, Path body) {
    if (filled) canvas.drawPath(body, _solid);
    canvas.drawPath(body, _ink);
  }

  void _pen(Canvas canvas) {
    const w = 2.75;
    final body = Path()
      ..moveTo(-w, -12)
      ..lineTo(w, -12)
      ..lineTo(w, 3.25)
      ..lineTo(0.9, 8.5)
      ..lineTo(-0.9, 8.5)
      ..lineTo(-w, 3.25)
      ..close();
    _body(canvas, body);
    // The nib, solid; selected, a seam where the cap ends.
    final nib = Path()
      ..addPolygon(const [Offset(-0.9, 8.5), Offset(0, 11.25), Offset(0.9, 8.5)], true);
    canvas
      ..drawPath(nib, _solid)
      ..drawPath(nib, _ink);
    _seam(canvas, -5, w);
  }

  void _highlighter(Canvas canvas) {
    const w = 3.25;
    final body = Path()
      ..moveTo(-w, -12)
      ..lineTo(w, -12)
      ..lineTo(w, 2)
      ..lineTo(1.75, 5.5)
      ..lineTo(-1.75, 5.5)
      ..lineTo(-w, 2)
      ..close();
    _body(canvas, body);
    // The chisel, cut on the slant.
    final chisel = Path()
      ..moveTo(-1.75, 5.5)
      ..lineTo(1.75, 5.5)
      ..lineTo(1.75, 8.5)
      ..lineTo(-1.75, 11)
      ..close();
    canvas
      ..drawPath(chisel, _solid)
      ..drawPath(chisel, _ink);
    _seam(canvas, -5, w);
  }

  void _eraser(Canvas canvas) {
    const block = Rect.fromLTRB(-3.75, -8.75, 3.75, 8.75);
    _body(canvas, Path()..addRect(block));
    canvas.drawRect(Rect.fromLTRB(block.left, 3.25, block.right, block.bottom), _solid);
    _seam(canvas, 3.25, block.right);
  }

  void _laser(Canvas canvas) {
    const w = 2.0;
    _body(canvas, Path()..addRect(const Rect.fromLTRB(-w, -12, w, -1)));
    // Its button, cut out when selected.
    canvas.drawRect(
      const Rect.fromLTRB(-0.75, -6.5, 0.75, -4),
      filled ? (Paint()..blendMode = BlendMode.clear) : _solid,
    );
    _beam(canvas, const Offset(0, 4), dot: 2, glow: 5);
  }

  /// A dot of light at [at] glowing away from the hand (+y): an arc of
  /// [glow] radius around it.
  void _beam(Canvas canvas, Offset at, {required double dot, required double glow}) {
    const sweep = 2 * math.pi / 3;
    canvas
      ..drawCircle(at, dot, _solid)
      ..drawArc(
        Rect.fromCircle(center: at, radius: glow),
        math.pi / 2 - sweep / 2,
        sweep,
        false,
        _rope,
      );
  }

  /// A line across an instrument at [y] (half-width [w]): cut out of a
  /// solid body, absent from an outline.
  void _seam(Canvas canvas, double y, double w) {
    if (!filled) return;
    canvas.drawLine(Offset(-w + 1.5, y), Offset(w - 1.5, y), _cut);
  }

  void _lasso(Canvas canvas) {
    // A loop of rope tilted up the instruments' diagonal, dashed (the
    // selection's marching ants), closed by a knot at its lower left; the
    // tail hangs from the knot toward the corner the instruments write in.
    const centre = Offset(13.75, 8.5);
    const rx = 8.5;
    const ry = 6;
    const tilt = -math.pi / 8;
    Offset at(double t) {
      final x = rx * math.cos(t);
      final y = ry * math.sin(t);
      return centre +
          Offset(x * math.cos(tilt) - y * math.sin(tilt), x * math.sin(tilt) + y * math.cos(tilt));
    }

    const knotAt = 0.97 * math.pi;
    final loop = Path()..moveTo(at(knotAt).dx, at(knotAt).dy);
    for (var i = 1; i <= 96; i++) {
      final p = at(knotAt + i / 96 * 2 * math.pi);
      loop.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(_dashed(loop, 9, 0.6, phase: 0.4), _rope);
    final knot = at(knotAt);
    canvas
      ..drawPath(
        Path()
          ..moveTo(knot.dx, knot.dy)
          ..cubicTo(knot.dx + 2.25, knot.dy + 3.5, 1.5, 16.5, 3.5, 21.5),
        _rope,
      )
      ..drawCircle(knot, 2, _solid);
  }

  void _marquee(Canvas canvas) {
    final box = Path()..addRect(const Rect.fromLTRB(4, 5, 20, 19));
    canvas.drawPath(_dashed(box, 12, 0.55, phase: 0.5), _rope);
  }

  void _text(Canvas canvas) {
    canvas
      ..drawPath(
        Path()
          ..moveTo(5, 7.5)
          ..lineTo(5, 4.75)
          ..lineTo(19, 4.75)
          ..lineTo(19, 7.5),
        _ink,
      )
      ..drawLine(const Offset(12, 4.75), const Offset(12, 19.25), _ink)
      ..drawLine(const Offset(9.25, 19.25), const Offset(14.75, 19.25), _ink);
  }

  void _insert(Canvas canvas) {
    canvas
      ..drawCircle(const Offset(12, 12), 8.25, _ink)
      ..drawLine(const Offset(12, 8), const Offset(12, 16), _ink)
      ..drawLine(const Offset(8, 12), const Offset(16, 12), _ink);
  }

  /// A handwritten wave from lower left to upper right.
  Path _squiggle() => Path()
    ..moveTo(3, 17)
    ..cubicTo(5.5, 6.5, 9, 6.5, 10.75, 12.5)
    ..cubicTo(12.5, 18.5, 16, 18.5, 17.75, 12)
    ..quadraticBezierTo(18.5, 9, 21, 7.5);

  void _partial(Canvas canvas) {
    final wave = _squiggle().computeMetrics().single;
    final a = wave.length * 0.4;
    final b = wave.length * 0.6;
    canvas
      ..drawPath(wave.extractPath(0, a), _rope)
      ..drawPath(wave.extractPath(b, wave.length), _rope);
  }

  void _trail(Canvas canvas) {
    final wave = _squiggle().computeMetrics().single;
    canvas.drawPath(wave.extractPath(0, wave.length * 0.82), _ink);
    final end = wave.getTangentForOffset(wave.length)!.position;
    canvas.drawCircle(end, 2.5, _solid);
  }

  /// [path] as [count] dashes per contour, each [on] of its period long,
  /// starting [phase] periods along.
  Path _dashed(Path path, int count, double on, {double phase = 0}) {
    final out = Path();
    for (final contour in path.computeMetrics()) {
      final period = contour.length / count;
      for (var i = 0; i < count; i++) {
        final start = (i + phase) * period;
        final end = start + on * period;
        out.addPath(contour.extractPath(start, math.min(end, contour.length)), Offset.zero);
        if (end > contour.length) {
          out.addPath(contour.extractPath(0, end - contour.length), Offset.zero);
        }
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_ToolIconPainter old) =>
      old.kind != kind || old.color != color || old.filled != filled;
}
