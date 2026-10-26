part of 'tool_icons.dart';

/// The glyphs' grid, margin and stroke, in grid units (a 24-unit square).
const double _grid = 24;
const double _margin = 2;
const double _stroke = 1.7;

/// How much of the ink a selected line drawing's tint takes (the lasso's
/// loop, a shape): enough to read as chosen, light enough that a filled
/// square never outweighs the instruments beside it.
const double _tint = 0.22;

/// A glyph line: [_stroke] grid units wide on a canvas of [unit] (1 when
/// the canvas is already scaled to the grid), round ends and corners.
Paint _line(Color color, [double unit = 1]) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = _stroke * unit
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// [points] as a path whose corners are rounded off with a radius of up to
/// [radius] (less where a side is short, so dense curves stay as they are).
/// [closed] joins the last point to the first (a repeated first point at
/// the end is dropped).
Path _roundedPolygon(List<Offset> points, {required bool closed, required double radius}) {
  var p = points;
  if (closed && p.length > 2 && (p.first - p.last).distance < 1e-6) p = p.sublist(0, p.length - 1);
  final n = p.length;
  final path = Path();
  if (n < 3) return path..addPolygon(p, closed);
  // The point [radius] (at most) from corner i toward its previous (-1)
  // or next (+1) neighbour.
  Offset corner(int i, int towards) {
    final prev = p[(i - 1 + n) % n], at = p[i], next = p[(i + 1) % n];
    final d = math.min(radius, math.min((at - prev).distance, (next - at).distance) / 2.5);
    final out = towards < 0 ? prev - at : next - at;
    return at + out / out.distance * d;
  }

  void round(int i) {
    final a = corner(i, -1), b = corner(i, 1);
    path
      ..lineTo(a.dx, a.dy)
      ..quadraticBezierTo(p[i].dx, p[i].dy, b.dx, b.dy);
  }

  if (closed) {
    final start = corner(0, 1);
    path.moveTo(start.dx, start.dy);
    for (var k = 1; k <= n; k++) {
      round(k % n);
    }
    return path..close();
  }
  path.moveTo(p.first.dx, p.first.dy);
  for (var i = 1; i < n - 1; i++) {
    round(i);
  }
  return path..lineTo(p.last.dx, p.last.dy);
}

class _ToolIconPainter extends CustomPainter {
  _ToolIconPainter(this.kind, this.color, {required this.filled});

  final ToolIconKind kind;
  final Color color;
  final bool filled;

  late final Paint _ink = _line(color);
  late final Paint _solid = Paint()..color = color;
  late final Paint _wash = Paint()..color = color.withValues(alpha: color.a * _tint);

  /// Cuts details out of a solid body (the selected instruments).
  late final Paint _cut = _line(color)
    ..blendMode = BlendMode.clear
    ..strokeWidth = 1.4;

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
        _beam(canvas, const Offset(12, 12), dot: 3.25, glow: 7.5);
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

  /// A part that touches the page: solid in both states, its outline
  /// rounding its corners.
  void _tip(Canvas canvas, Path tip) => canvas
    ..drawPath(tip, _solid)
    ..drawPath(tip, _ink);

  /// A barrel [w] wide on each side from [top] (rounded corners) down to
  /// [shoulder], then tapering to a [neck] wide opening at [end].
  Path _barrel({
    required double w,
    required double top,
    required double shoulder,
    required double neck,
    required double end,
  }) {
    const r = 2.25;
    return Path()
      ..moveTo(-w, top + r)
      ..quadraticBezierTo(-w, top, -w + r, top)
      ..lineTo(w - r, top)
      ..quadraticBezierTo(w, top, w, top + r)
      ..lineTo(w, shoulder)
      ..quadraticBezierTo(w, shoulder + 1, w - 0.75, shoulder + 1.75)
      ..lineTo(neck, end)
      ..lineTo(-neck, end)
      ..lineTo(-w + 0.75, shoulder + 1.75)
      ..quadraticBezierTo(-w, shoulder + 1, -w, shoulder)
      ..close();
  }

  void _pen(Canvas canvas) {
    const w = 3.0;
    _body(canvas, _barrel(w: w, top: -11.5, shoulder: 2, neck: 1.2, end: 7.5));
    // The nib: a rounded drop below the cone, always solid.
    _tip(
      canvas,
      Path()
        ..moveTo(-1.2, 7.5)
        ..lineTo(1.2, 7.5)
        ..quadraticBezierTo(0.9, 9.5, 0, 10.75)
        ..quadraticBezierTo(-0.9, 9.5, -1.2, 7.5)
        ..close(),
    );
    // The cap's end: a line across the barrel, cut out when selected.
    _seam(canvas, -4.5, w);
  }

  void _highlighter(Canvas canvas) {
    const w = 3.5;
    _body(canvas, _barrel(w: w, top: -11.5, shoulder: 0.5, neck: 2.25, end: 4.75));
    // The chisel, cut on the slant, rounded at its corners.
    _tip(
      canvas,
      _roundedPolygon(
        const [Offset(-2.25, 4.75), Offset(2.25, 4.75), Offset(2.25, 7.75), Offset(-2.25, 10)],
        closed: true,
        radius: 0.9,
      ),
    );
    _seam(canvas, -4.5, w);
  }

  void _eraser(Canvas canvas) {
    final block = RRect.fromLTRBR(-4, -9, 4, 9, const Radius.circular(2.5));
    _body(canvas, Path()..addRRect(block));
    // The band at the working end: solid, the body's rounded corners kept.
    canvas
      ..save()
      ..clipRect(const Rect.fromLTRB(-6, 3, 6, 10))
      ..drawRRect(block, _solid)
      ..restore()
      ..drawLine(const Offset(-4, 3), const Offset(4, 3), _ink);
    _seam(canvas, 3, block.right);
  }

  void _laser(Canvas canvas) {
    // A slim pointer, rounded at both ends.
    const body = Rect.fromLTRB(-2.25, -12, 2.25, 0.5);
    _body(canvas, Path()..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(2.25))));
    // Its button: a dot, cut out when selected.
    canvas.drawCircle(
      const Offset(0, -6),
      0.9,
      filled ? (Paint()..blendMode = BlendMode.clear) : _solid,
    );
    _beam(canvas, const Offset(0, 6), dot: 2, glow: 4.5);
  }

  /// A dot of light at [at], [dot] across, in a soft halo [glow] across.
  void _beam(Canvas canvas, Offset at, {required double dot, required double glow}) => canvas
    ..drawCircle(at, glow, _wash)
    ..drawCircle(at, dot, _solid);

  /// A line across an instrument at [y] (half-width [w]): cut out of a
  /// solid body; absent from an outline.
  void _seam(Canvas canvas, double y, double w) {
    if (!filled) return;
    canvas.drawLine(Offset(-w + 1.75, y), Offset(w - 1.75, y), _cut);
  }

  void _lasso(Canvas canvas) {
    // A loop of rope tilted up the instruments' diagonal, in round dashes
    // (the selection's marching ants), closed by a round knot at its lower
    // left; the tail curls from the knot toward the corner the instruments
    // write in. Selected, the loop holds a light wash.
    const centre = Offset(13.5, 9.25);
    const rx = 8.25;
    const ry = 6;
    const tilt = -math.pi / 7;
    Offset at(double t) {
      final x = rx * math.cos(t);
      final y = ry * math.sin(t);
      return centre +
          Offset(x * math.cos(tilt) - y * math.sin(tilt), x * math.sin(tilt) + y * math.cos(tilt));
    }

    const knotAt = 0.9 * math.pi;
    final loop = Path()..moveTo(at(knotAt).dx, at(knotAt).dy);
    for (var i = 1; i <= 96; i++) {
      final p = at(knotAt + i / 96 * 2 * math.pi);
      loop.lineTo(p.dx, p.dy);
    }
    loop.close();
    if (filled) canvas.drawPath(loop, _wash);
    // Gaps open beside the knot so the rope runs into it.
    canvas.drawPath(_dashed(loop, 6, 0.6, phase: 0.3), _ink);
    final knot = at(knotAt);
    canvas
      ..drawPath(
        Path()
          ..moveTo(knot.dx, knot.dy)
          ..cubicTo(knot.dx + 1.5, knot.dy + 4, 6.5, 17.5, 4.5, 19.5)
          ..quadraticBezierTo(3.25, 20.75, 4, 21.5),
        _ink,
      )
      ..drawCircle(knot, 2.1, _solid);
  }

  void _marquee(Canvas canvas) {
    final box = Path()..addRRect(RRect.fromLTRBR(4, 5, 20, 19, const Radius.circular(3)));
    if (filled) canvas.drawPath(box, _wash);
    canvas.drawPath(_dashed(box, 10, 0.45, phase: 0.6), _ink);
  }

  void _text(Canvas canvas) {
    // A soft capital T, round at every end; selected, a bolder T (a line
    // drawing has nothing to fill, so it gains weight instead).
    final pen = filled ? (_line(color)..strokeWidth = _stroke * 1.55) : _ink;
    canvas
      ..drawLine(const Offset(5.5, 5.5), const Offset(18.5, 5.5), pen)
      ..drawLine(const Offset(12, 5.5), const Offset(12, 19), pen);
  }

  void _insert(Canvas canvas) {
    if (filled) canvas.drawCircle(const Offset(12, 12), 8.25, _wash);
    canvas
      ..drawCircle(const Offset(12, 12), 8.25, _ink)
      ..drawLine(const Offset(12, 8.25), const Offset(12, 15.75), _ink)
      ..drawLine(const Offset(8.25, 12), const Offset(15.75, 12), _ink);
  }

  /// A handwritten wave from lower left to upper right.
  Path _squiggle() => Path()
    ..moveTo(3.5, 16.5)
    ..cubicTo(5.5, 7, 9, 7, 10.75, 12.5)
    ..cubicTo(12.5, 18, 16, 18, 17.75, 12)
    ..quadraticBezierTo(18.5, 9, 20.5, 7.75);

  void _partial(Canvas canvas) {
    final wave = _squiggle().computeMetrics().single;
    final a = wave.length * 0.38;
    final b = wave.length * 0.62;
    canvas
      ..drawPath(wave.extractPath(0, a), _ink)
      ..drawPath(wave.extractPath(b, wave.length), _ink);
  }

  void _trail(Canvas canvas) {
    final wave = _squiggle().computeMetrics().single;
    canvas.drawPath(wave.extractPath(0, wave.length * 0.8), _ink);
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
