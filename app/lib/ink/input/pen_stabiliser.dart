import 'dart:math' as math;
import 'dart:ui';

/// The pen's stabiliser: a pulled string (a "lazy brush") between the pen
/// and the ink, applied to every sample before it becomes a stroke point
/// (`InkDrawing`; the low-latency overlay applies the same,
/// `WetInkModel`). See docs/ARCHITECTURE.md, *Stabiliser*.
///
/// The ink stays put while the pen is within [StabiliserParams.radius] of
/// it; when the pen goes further, the ink moves straight toward the pen
/// until it is exactly the radius away, as if pulled on a string. Jitter
/// smaller than the string never reaches the ink, and the ink's path is a
/// pursuit curve that cuts corners and rounds a shaky line by the string's
/// length. Nothing depends on time: writing fast keeps the same gap and the
/// same smoothing as writing slowly (the owner's request: the stabiliser
/// should not let go when writing fast).
///
/// Between two samples the pen is taken to move in a straight line, and
/// the ink follows it in steps of at most a [_steps]th of the radius, so
/// the path does not depend on the sample rate (120, 240 Hz, 1 kHz), only
/// on the pen's path.
///
/// It is causal: every output is final as soon as its sample arrives, so
/// live ink reaches the stabilised point with nothing provisional and the
/// stroke stores the stabilised points (with stabiliser 0 in its style):
/// live and committed ink are the same, and a reload draws them again. At
/// pen-up the ink catches up with the pen along its path ([catchUp]).
class PenStabiliser {
  PenStabiliser(this.params);

  final StabiliserParams params;

  /// The ink's position: where the string pulled it.
  Offset get ink => Offset(_ix, _iy);
  double _ix = 0, _iy = 0;

  /// The pen's newest position (unstabilised).
  Offset get pen => Offset(_px, _py);
  double _px = 0, _py = 0;

  /// How far the ink trails the pen: at most the string's length.
  double get gap => _distance(_px - _ix, _py - _iy);

  bool _started = false;

  /// The ink follows the pen in steps of at most radius / [_steps].
  static const int _steps = 32;

  /// At most this many steps between two samples (a jump of the pen).
  static const int _maxSteps = 1024;

  // The pen's positions over the last [_keptLength] of its path (further
  // back than the ink can be), with the path's length up to each, for
  // [catchUp]; from [_h0] on.
  final List<double> _hx = [], _hy = [], _hs = [];
  int _h0 = 0;

  /// How much of the pen's path (px) is kept for [catchUp].
  double get _keptLength => 4 * params.radius + 16;

  void _remember(double x, double y) {
    final n = _hx.length;
    _hs.add(n == 0 ? 0 : _hs[n - 1] + _distance(x - _hx[n - 1], y - _hy[n - 1]));
    _hx.add(x);
    _hy.add(y);
    final s = _hs.last;
    while (_h0 < _hs.length - 2 && s - _hs[_h0 + 1] > _keptLength) {
      _h0++;
    }
    // Drop what has fallen out now and then, not on every sample.
    if (_h0 > 1024) {
      _hx.removeRange(0, _h0);
      _hy.removeRange(0, _h0);
      _hs.removeRange(0, _h0);
      _h0 = 0;
    }
  }

  /// Starts a stroke at [at]: the ink starts under the nib.
  void begin(Offset at) {
    _hx.clear();
    _hy.clear();
    _hs.clear();
    _h0 = 0;
    _px = _ix = at.dx;
    _py = _iy = at.dy;
    _remember(_px, _py);
    _started = true;
  }

  /// The pen moved to [at]: returns the ink's new position.
  Offset add(Offset at) {
    if (!_started) {
      begin(at);
      return at;
    }
    final x = at.dx, y = at.dy;
    _remember(x, y);
    final r = params.radius;
    final dx = x - _px, dy = y - _py;
    final d = _distance(dx, dy);
    final n = math.min(_maxSteps, math.max(1, (d * _steps / r).ceil()));
    for (var i = 1; i < n; i++) {
      final f = i / n;
      _pull(_px + dx * f, _py + dy * f, r);
    }
    _pull(x, y, r);
    _px = x;
    _py = y;
    return ink;
  }

  /// The pen at ([x], [y]): the ink moves toward it until it is [r] away,
  /// if it is further.
  void _pull(double x, double y, double r) {
    final ex = x - _ix, ey = y - _iy;
    final e = _distance(ex, ey);
    if (e <= r) return;
    final k = (e - r) / e;
    _ix += ex * k;
    _iy += ey * k;
  }

  /// The ink catching up with the pen (at the lift, and before hold to
  /// snap reads the stroke): points from the ink along the pen's latest
  /// path to the pen, the ink's offset from that path fading out along it
  /// (by length), so the end follows the curve the pen drew rather than
  /// cutting across it, and reaches the lift. The ink is at the pen
  /// afterwards.
  List<Offset> catchUp() {
    final n = _hx.length;
    // The pen's position nearest the ink.
    var j = n - 1;
    var best = double.infinity;
    for (var i = n - 1; i >= _h0; i--) {
      final dx = _hx[i] - _ix, dy = _hy[i] - _iy;
      final d = dx * dx + dy * dy;
      if (d < best) {
        best = d;
        j = i;
      }
    }
    final ox = _ix - _hx[j], oy = _iy - _hy[j];
    final total = _hs[n - 1] - _hs[j];
    final out = <Offset>[];
    for (var k = j + 1; k < n; k++) {
      final w = total > 0 ? 1 - (_hs[k] - _hs[j]) / total : 0.0;
      out.add(Offset(_hx[k] + ox * w, _hy[k] + oy * w));
    }
    final p = pen;
    if (out.isEmpty || out.last != p) out.add(p);
    _ix = _px;
    _iy = _py;
    return out;
  }

  static double _distance(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
}

/// The stabiliser's numbers for a setting (`PenConfig.streamline`, 0..1),
/// in the units of the positions it stabilises (logical screen px; the
/// overlay's are [scaled]).
class StabiliserParams {
  const StabiliserParams({required this.radius});

  /// The stabiliser at [setting] (0..1; 0: off, null), for positions in
  /// screen px times [scale].
  static StabiliserParams? of(double setting, {double scale = 1}) {
    if (!(setting > 0)) return null;
    return StabiliserParams(radius: radiusAt(setting) * scale);
  }

  /// The string's length (screen px) at [setting] (0..1): a power curve
  /// through [defaultRadius] at 30 % (the pen's default: jitter goes, a
  /// gentle smoothing) and [maxRadius] at 100 %; 0.15 px at 10 %, 6.6 px
  /// at 40 %, 20 px at 60 %, 44 px at 80 %.
  static double radiusAt(double setting) =>
      maxRadius * math.pow(setting.clamp(0.0, 1.0), exponent).toDouble();

  /// The string's length at 100 % (screen px): 8× the largest trail of
  /// the speed-adaptive filter it replaced (≈ 10 px at 100 %).
  static const double maxRadius = 80;

  /// The string's length at the pen's default 30 % (screen px): that
  /// filter's largest trail at 30 %.
  static const double defaultRadius = 3;

  /// The curve's power (≈ 2.73): [radiusAt] passes through (0.3,
  /// [defaultRadius]) and (1, [maxRadius]).
  static final double exponent = math.log(defaultRadius / maxRadius) / math.log(0.3);

  /// The string's length (px): how far the pen moves from the ink before
  /// it pulls the ink along.
  final double radius;

  /// The same with lengths multiplied by [f].
  StabiliserParams scaled(double f) => StabiliserParams(radius: radius * f);

  /// The values in the order the overlay's `begin` message carries them.
  List<double> toList() => [radius];

  @override
  bool operator ==(Object other) => other is StabiliserParams && other.radius == radius;

  @override
  int get hashCode => radius.hashCode;
}
