import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A soft ribbon along polylines, drawn as one triangle mesh with
/// per-vertex colours: across the ribbon, lanes at fixed fractions of the
/// half-width carry their own colour and opacity (transparent at the edges,
/// so the ribbon is soft without a blur), and along it every point has an
/// opacity (the trail's fade) that also narrows it.
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

  /// Adds a ribbon along ([xs], [ys]) with [halfWidth] at full opacity;
  /// [alphas] (0 … 1) fades and narrows each point.
  void add(List<double> xs, List<double> ys, List<double> alphas, double halfWidth) {
    final n = xs.length;
    if (n < 2) return;
    final most = _maxVertices ~/ _lanes;
    if (n > most) {
      // Too long for one mesh: two overlapping halves.
      final k = n ~/ 2;
      add(xs.sublist(0, k + 1), ys.sublist(0, k + 1), alphas.sublist(0, k + 1), halfWidth);
      add(xs.sublist(k), ys.sublist(k), alphas.sublist(k), halfWidth);
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
      final w = halfWidth * (0.35 + 0.65 * alpha);
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
