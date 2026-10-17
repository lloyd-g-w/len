import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A soft ribbon along polylines, drawn as one triangle mesh with
/// per-vertex colours: across the ribbon, lanes at fixed fractions of the
/// half-width carry their own colour and opacity (transparent at the edges,
/// so the ribbon is soft without a blur), and along it every point has a
/// half-width (the pen engine's radii: pressure, tapers) and an opacity (the
/// trail's fade) that also narrows it. Ends are cut square, or rounded
/// ([add]'s caps: a half disc of rings narrowing to the tip).
///
/// Buffers are typed and kept between frames: reuse one ribbon per layer
/// and [draw] it every frame.
class LaserRibbon {
  LaserRibbon._(this._offsets, this._weights, this._hot);

  /// The wide, faint halo.
  LaserRibbon.glow() : this._(const [-1, -0.5, 0, 0.5, 1], const [0, 0.16, 0.5, 0.16, 0], null);

  /// The bright core: nearly white in the middle, the colour towards its
  /// soft edges.
  LaserRibbon.core()
    : this._(const [-1, -0.6, 0, 0.6, 1], const [0, 1, 1, 1, 0], const [
        false,
        false,
        true,
        false,
        false,
      ]);

  /// Lane positions across the ribbon (−1 … 1 of the half-width).
  final List<double> _offsets;

  /// Lane opacities.
  final List<double> _weights;

  /// Lanes in the hot (whitened) colour, if any.
  final List<bool>? _hot;

  /// Lane colours (RGB) for the current [color].
  late final Int32List _rgb = Int32List(_offsets.length);

  Float32List _positions = Float32List(0);
  Int32List _colors = Int32List(0);
  Uint16List _indices = Uint16List(0);
  int _vertices = 0;
  int _indexCount = 0;
  final List<Vertices> _meshes = [];

  /// Indices are 16-bit: a mesh is flushed before it reaches this many vertices.
  static const int _maxVertices = 60000;

  int get _lanes => _offsets.length;

  /// The bright centre of the core: [color] lightened, but not to white
  /// (a white centre reads as a hollow line on white paper).
  static Color hotOf(Color color) => Color.lerp(color, const Color(0xFFFFFFFF), 0.45)!;

  /// Sets the colour of what is added next.
  set color(Color color) {
    final hot = hotOf(color);
    for (var l = 0; l < _lanes; l++) {
      _rgb[l] = ((_hot?[l] ?? false) ? hot : color).toARGB32() & 0xFFFFFF;
    }
  }

  /// Adds a ribbon along ([xs], [ys]) with [halfWidths] × [scale] at full
  /// opacity; [alphas] (0 … 1) fades and narrows each point. [capStart] and
  /// [capEnd] round those ends (a half disc of the end's width beyond it).
  void add(
    List<double> xs,
    List<double> ys,
    List<double> alphas,
    List<double> halfWidths, {
    double scale = 1,
    bool capStart = false,
    bool capEnd = false,
  }) {
    final n = xs.length;
    if (n < 2) return;
    if (capStart || capEnd) {
      final c = _capped(xs, ys, alphas, halfWidths, scale, capStart, capEnd);
      return add(c.x, c.y, c.a, c.w, scale: scale);
    }
    final most = _maxVertices ~/ _lanes;
    if (n > most) {
      // Too long for one mesh: two overlapping halves.
      final k = n ~/ 2;
      List<double> head(List<double> l) => l.sublist(0, k + 1);
      List<double> tail(List<double> l) => l.sublist(k);
      add(head(xs), head(ys), head(alphas), head(halfWidths), scale: scale);
      add(tail(xs), tail(ys), tail(alphas), tail(halfWidths), scale: scale);
      return;
    }
    if (_vertices + n * _lanes > _maxVertices) _flush();
    _reserve(n);
    final lanes = _lanes;
    var nx = 0.0, ny = 0.0;
    for (var i = 0; i < n; i++) {
      final a = i == 0 ? 0 : i - 1, b = i == n - 1 ? n - 1 : i + 1;
      final tx = xs[b] - xs[a], ty = ys[b] - ys[a];
      final len = math.sqrt(tx * tx + ty * ty);
      if (len > 1e-6) {
        nx = -ty / len;
        ny = tx / len;
      }
      final alpha = _ease(alphas[i]);
      final w = halfWidths[i] * scale * (0.35 + 0.65 * alpha);
      final base = _vertices;
      for (var l = 0; l < lanes; l++) {
        final o = w * _offsets[l];
        final v = _vertices++;
        _positions[2 * v] = xs[i] + nx * o;
        _positions[2 * v + 1] = ys[i] + ny * o;
        final a8 = (_weights[l] * alpha * 255).round();
        _colors[v] = (a8 << 24) | _rgb[l];
      }
      if (i == 0) continue;
      final prev = base - lanes;
      for (var l = 0; l < lanes - 1; l++) {
        _indices[_indexCount++] = prev + l;
        _indices[_indexCount++] = prev + l + 1;
        _indices[_indexCount++] = base + l;
        _indices[_indexCount++] = prev + l + 1;
        _indices[_indexCount++] = base + l + 1;
        _indices[_indexCount++] = base + l;
      }
    }
  }

  /// Rings of a round cap beyond an end.
  static const int _capRings = 5;

  /// How much a point of opacity [alpha] is narrowed (as [add] does).
  static double widthFactor(double alpha) => 0.35 + 0.65 * _ease(alpha);

  /// The line with round caps: rings beyond the chosen ends along the end's
  /// direction, `r sin θ` out and `r cos θ` wide (a half disc of the end's
  /// half-width r, as drawn), at the end's opacity.
  static ({List<double> x, List<double> y, List<double> a, List<double> w}) _capped(
    List<double> xs,
    List<double> ys,
    List<double> alphas,
    List<double> halfWidths,
    double scale,
    bool capStart,
    bool capEnd,
  ) {
    final x = <double>[], y = <double>[], a = <double>[], w = <double>[];
    void cap(int end, int inner, bool outward) {
      final dx = xs[end] - xs[inner], dy = ys[end] - ys[inner];
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-9) return;
      final r = halfWidths[end] * scale * widthFactor(alphas[end]);
      for (var k = 1; k <= _capRings; k++) {
        final m = outward ? k : _capRings + 1 - k;
        final theta = m / _capRings * math.pi / 2;
        final d = r * math.sin(theta) / len;
        x.add(xs[end] + dx * d);
        y.add(ys[end] + dy * d);
        a.add(alphas[end]);
        w.add(halfWidths[end] * math.cos(theta));
      }
    }

    final n = xs.length;
    if (capStart) cap(0, 1, false);
    x.addAll(xs);
    y.addAll(ys);
    a.addAll(alphas);
    w.addAll(halfWidths);
    if (capEnd) cap(n - 1, n - 2, true);
    return (x: x, y: y, a: a, w: w);
  }

  /// Makes room for [n] more points.
  void _reserve(int n) {
    final vertices = _vertices + n * _lanes;
    if (vertices * 2 > _positions.length) {
      final grown = math.max(vertices, _positions.length);
      _positions = Float32List(grown * 2)..setRange(0, _vertices * 2, _positions);
      _colors = Int32List(grown)..setRange(0, _vertices, _colors);
    }
    final indices = _indexCount + n * (_lanes - 1) * 6;
    if (indices > _indices.length) {
      _indices = Uint16List(math.max(indices, _indices.length * 2))
        ..setRange(0, _indexCount, _indices);
    }
  }

  /// Smoothstep: the trail stays bright longer and fades out gently.
  static double _ease(double a) => a * a * (3 - 2 * a);

  void _flush() {
    if (_indexCount == 0) return;
    _meshes.add(
      Vertices.raw(
        VertexMode.triangles,
        Float32List.sublistView(_positions, 0, _vertices * 2),
        colors: Int32List.sublistView(_colors, 0, _vertices),
        indices: Uint16List.sublistView(_indices, 0, _indexCount),
      ),
    );
    _vertices = 0;
    _indexCount = 0;
  }

  /// Draws everything added since the last draw (vertex colours only: the
  /// paint is ignored), then starts over.
  void draw(Canvas canvas) {
    _flush();
    final paint = Paint();
    for (final mesh in _meshes) {
      canvas.drawVertices(mesh, BlendMode.dst, paint);
    }
    _meshes.clear();
  }
}
