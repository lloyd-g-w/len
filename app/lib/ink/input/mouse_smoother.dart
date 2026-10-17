import 'dart:math' as math;
import 'dart:ui';

/// Smooths a mouse's path before it becomes ink, in screen pixels (fed as
/// the mouse moves, in screen px and milliseconds): the mouse's own
/// stabiliser.
///
/// A stylus reports positions to a fraction of a pixel; a mouse (on the
/// web and desktops) to whole pixels, so its path is a staircase with
/// ±0.5 px of error at every sample, and the pen's outline smoothing
/// (sub-pixel, bounded by the pen's width so its geometry stays exact)
/// cannot level it: a thick pen showed every step as a bump, its width
/// swelling and pinching along straight lines, and a thin one zoomed out
/// as squiggles. A mouse has no pressure either: its ink is the pen's
/// width throughout.
///
/// So every mouse stroke is resampled every [spacing] px along its path
/// (by position, whatever the event rate, its jitter or batching) and
/// smoothed with a centred Gaussian of σ [sigmaFor] the stabiliser, from
/// [minSigma] px at 0 (the steps levelled) to [maxSigma] at 1. A point is
/// passed on once the samples it depends on are known, so it never
/// changes once drawn: the final ink trails the mouse by [lagOf] px (8 px
/// at 0, 11 at 30 %), and with the stabiliser off [tip] gives the rest up
/// to the mouse, provisionally, so the ink reaches it. The stroke's
/// stabiliser is applied here, not again by the outline (`InkDrawing`
/// commits mouse strokes with stabiliser 0, as the pen's straight lines
/// are): the same smoothing costs half the lag in screen space, where a
/// mouse's error is.
///
/// Sharp turns (cusps: the line turns by more than [minTurn] over
/// [cornerBaseline] px each way) are kept: smoothing never crosses them.
/// At them and at the stroke's ends the path is continued by its point
/// reflection, so the stroke starts and ends exactly where the mouse went
/// down and up, cusps stay sharp, and the line runs straight into them
/// rather than keeping its steps there.
class MouseSmoother {
  /// [onPoint] receives each smoothed point (screen px) and its time.
  MouseSmoother(this.onPoint);

  final void Function(Offset at, int timeMs) onPoint;

  /// Resampling step (px).
  static const double spacing = 1;

  /// σ (px) with the stabiliser off: enough to level a mouse's steps.
  static const double minSigma = 2;

  /// σ (px) at full stabiliser.
  static const double maxSigma = 5;

  /// The smoothing (σ, screen px) at stabiliser [stabiliser] (0..1).
  static double sigmaFor(double stabiliser) =>
      minSigma + (maxSigma - minSigma) * stabiliser.clamp(0.0, 1.0);

  /// Samples each way a sharp turn is measured over (px).
  static const int cornerBaseline = 3;

  /// The least turn (radians) over [cornerBaseline] that is a cusp.
  static const double minTurn = 90 * math.pi / 180;

  /// Samples each side of a point its smoothing reaches (the Gaussian cut
  /// at 2.5 σ).
  static int reachOf(double sigma) => (2.5 * sigma / spacing).ceil();

  /// How far (px) the final ink trails the mouse with the smoothing
  /// [sigma]: the smoothing's reach, and what deciding a cusp needs.
  static double lagOf(double sigma) => (reachOf(sigma) + cornerBaseline) * spacing;

  int _k = 0;
  List<double> _weights = const [1];

  final List<Offset> _path = [];
  final List<int> _times = [];

  /// Cusps found so far (sample indices), and the first sample not yet
  /// scanned for one.
  final List<int> _cusps = [];
  int _scanned = cornerBaseline;

  /// Points passed on so far (the first is the mouse-down's, not passed).
  int _emitted = 1;

  /// Distance along the last raw segment to the next resampled point.
  double _carry = spacing;
  Offset _last = Offset.zero;
  int _lastTime = 0;

  /// Starts a stroke at [at] (passed on by the caller as the first point)
  /// with stabiliser [stabiliser].
  void begin(Offset at, int timeMs, {required double stabiliser}) {
    final sigma = sigmaFor(stabiliser);
    _k = reachOf(sigma);
    _weights = [for (var i = 0; i <= _k; i++) math.exp(-0.5 * math.pow(i * spacing / sigma, 2))];
    _restart(at, timeMs);
  }

  void _restart(Offset at, int timeMs) {
    _path
      ..clear()
      ..add(at);
    _times
      ..clear()
      ..add(timeMs);
    _cusps.clear();
    _scanned = cornerBaseline;
    _emitted = 1;
    _carry = spacing;
    _last = at;
    _lastTime = timeMs;
  }

  /// The mouse moved to [at].
  void add(Offset at, int timeMs) {
    final d = (at - _last).distance;
    if (d < 1e-6) return;
    var along = _carry;
    while (along <= d) {
      final t = along / d;
      _path.add(Offset.lerp(_last, at, t)!);
      _times.add(_lastTime + ((timeMs - _lastTime) * t).round());
      along += spacing;
    }
    _carry = along - d;
    _last = at;
    _lastTime = timeMs;
    _findCusps();
    // A point's window reaches [_k] samples ahead, and a cusp there is
    // known [cornerBaseline] samples after it.
    _emitUpTo(_path.length - 1 - _k - cornerBaseline, ended: false);
  }

  /// The mouse went up at its last position: passes on the rest of the
  /// path, ending there.
  void finish() {
    if (_path.isEmpty) return;
    if (_path.last != _last) {
      _path.add(_last);
      _times.add(_lastTime);
    }
    _findCusps();
    _emitUpTo(_path.length - 1, ended: true);
  }

  /// The mouse rests (hold to snap is about to read the stroke): passes on
  /// the rest of the path, ending at the mouse, as [finish] does, and
  /// carries on smoothing from there if it moves on.
  void flush() {
    if (_path.isEmpty) return;
    finish();
    _restart(_last, _lastTime);
  }

  /// The rest of the path after the last point passed on, as [finish]
  /// would pass it on now (screen px; ending at the mouse), without
  /// passing it on: the live ink's provisional tip. Points near its start
  /// barely move as the mouse goes on (the window there is nearly full).
  List<Offset> tip() {
    if (_path.isEmpty) return const [];
    final extra = _path.last != _last;
    if (extra) _path.add(_last);
    final n = _path.length;
    final out = [for (var i = _emitted; i < n; i++) _pointAt(i, ended: true)];
    if (extra) _path.removeLast();
    return out;
  }

  /// Finds the cusps among the samples whose turn is known: where the
  /// line first turns by more than [minTurn], the tip is the sample within
  /// the baseline after it furthest along the way the line came (as the
  /// outline's corners are), decided as soon as the turn is known.
  void _findCusps() {
    const b = cornerBaseline;
    final n = _path.length;
    for (; _scanned + b < n; _scanned++) {
      final i = _scanned;
      final u = _path[i] - _path[i - b], v = _path[i + b] - _path[i];
      final turn = math.atan2(u.dx * v.dy - u.dy * v.dx, u.dx * v.dx + u.dy * v.dy).abs();
      if (turn <= minTurn) continue;
      var tip = i;
      var best = 0.0;
      for (var j = i + 1; j <= i + b; j++) {
        final w = _path[j] - _path[i];
        final along = w.dx * u.dx + w.dy * u.dy;
        if (along > best) {
          best = along;
          tip = j;
        }
      }
      _cusps.add(tip);
      // The turns around the tip belong to it.
      _scanned = tip + b;
    }
  }

  void _emitUpTo(int last, {required bool ended}) {
    for (; _emitted <= last; _emitted++) {
      onPoint(_pointAt(_emitted, ended: ended), _times[_emitted]);
    }
  }

  /// Sample [i] smoothed within its stretch between cusps; the path's end
  /// bounds the last stretch only once [ended].
  Offset _pointAt(int i, {required bool ended}) {
    final n = _path.length;
    var c = _cusps.length; // The first cusp at or after [i].
    while (c > 0 && _cusps[c - 1] >= i) {
      c--;
    }
    final lo = c > 0 ? _cusps[c - 1] : 0;
    final hi = c < _cusps.length ? _cusps[c] : (ended ? n - 1 : n + _k);
    return i == hi ? _path[i] : _smoothed(i, lo, math.min(hi, n - 1));
  }

  /// The Gaussian at [i] within the stretch [lo]..[hi], continued past its
  /// ends by point reflection (a line runs on straight; the ends stay).
  Offset _smoothed(int i, int lo, int hi) {
    var x = 0.0, y = 0.0, w = 0.0;
    for (var j = -_k; j <= _k; j++) {
      final weight = _weights[j.abs()];
      final m = i + j;
      final Offset p;
      if (m < lo) {
        p = _path[lo] * 2 - _path[math.min(hi, 2 * lo - m)];
      } else if (m > hi) {
        p = _path[hi] * 2 - _path[math.max(lo, 2 * hi - m)];
      } else {
        p = _path[m];
      }
      x += p.dx * weight;
      y += p.dy * weight;
      w += weight;
    }
    return Offset(x / w, y / w);
  }
}
