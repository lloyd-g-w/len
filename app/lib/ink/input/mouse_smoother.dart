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
/// [minSigma] px at 0 (the steps levelled, ink 4 px behind the mouse) to
/// [maxSigma] at 1. A point is passed on once the samples it depends on
/// are known: the ink trails the mouse by [lagOf] px and never changes
/// once drawn. The stroke's stabiliser is applied here, not again by the
/// outline (`InkDrawing` commits mouse strokes with stabiliser 0, as the
/// pen's straight lines are): the same smoothing costs half the lag in
/// screen space, where a mouse's error is.
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
  static const double minSigma = 1.5;

  /// σ (px) at full stabiliser.
  static const double maxSigma = 6.5;

  /// The smoothing (σ, screen px) at stabiliser [stabiliser] (0..1).
  static double sigmaFor(double stabiliser) =>
      minSigma + (maxSigma - minSigma) * stabiliser.clamp(0.0, 1.0);

  /// Samples each way a sharp turn is measured over (px).
  static const int cornerBaseline = 3;

  /// The least turn (radians) over [cornerBaseline] that is a cusp.
  static const double minTurn = 90 * math.pi / 180;

  /// σ (px) from which cusps are kept. Below it smoothing rounds them by
  /// less than a pixel, less than deciding them costs in lag.
  static const double cornerSigma = 2;

  /// Samples each side of a point its smoothing reaches (the Gaussian cut
  /// at 2.5 σ).
  static int reachOf(double sigma) => (2.5 * sigma / spacing).ceil();

  /// How far (px) the ink trails the mouse with the smoothing [sigma]: the
  /// smoothing's reach, and what deciding a cusp needs.
  static double lagOf(double sigma) =>
      (reachOf(sigma) + (sigma >= cornerSigma ? cornerBaseline : 0)) * spacing;

  int _k = 0;
  List<double> _weights = const [1];

  /// Whether cusps are kept ([cornerSigma]).
  bool _corners = false;

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
    _corners = sigma >= cornerSigma;
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
    _before = null;
    _tangent = null;
  }

  /// The mouse moved to [at].
  void add(Offset at, int timeMs) {
    final d = (at - _last).distance;
    if (d < 1e-6) return;
    _resample(at, timeMs, d);
    _before = _last;
    _last = at;
    _lastTime = timeMs;
    _findCusps(ended: false);
    // A point's window reaches [_k] samples ahead, and a cusp there is
    // known [cornerBaseline] samples after it.
    _emitUpTo(_path.length - 1 - _k - (_corners ? cornerBaseline : 0), ended: false);
  }

  /// The mouse went up at its last position: passes on the rest of the
  /// path, ending there.
  void finish() {
    if (_path.isEmpty) return;
    if (_path.last != _last) {
      _path.add(_last);
      _times.add(_lastTime);
    }
    _findCusps(ended: true);
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

  /// The shortest step (px) between events, and before it, that is curved
  /// ([_resample]).
  static const double minCurve = 4;

  /// The mouse position before [_last] (null at the start), and the
  /// path's direction at [_last] (unit; null at the start).
  Offset? _before;
  Offset? _tangent;

  /// Resamples the path from [_last] to [at] ([d] px apart) every
  /// [spacing] px. Sparse events (a slow event rate, or one event per frame
  /// as GTK and some browsers deliver them) would make a polygon whose
  /// corners the smoothing only blunts, so the piece is a cubic curve
  /// leaving [_last] the way the path arrived there and reaching [at] the
  /// way the circle through the last three positions does: the path's
  /// direction is continuous, and nothing waits for the next event. At a
  /// sharp turn (more than 60° off the chord) a piece starts or ends along
  /// its chord instead, rather than loop.
  void _resample(Offset at, int timeMs, double d) {
    final chord = (at - _last) / d;
    final before = _before;
    // Steps of a few pixels are mostly the whole-pixel error: chords.
    final curved = d >= minCurve && before != null && (_last - before).distance >= minCurve;
    final start = (curved ? _along(_tangent, chord) : chord) * d;
    final end = (curved ? _along(_endTangent(before, _last, at), chord) : chord) * d;
    // Flattened finely, then sampled by length.
    final pieces = math.max(1, (d / 0.25).ceil());
    var from = _last;
    var along = _carry;
    for (var m = 1; m <= pieces; m++) {
      final t = m / pieces;
      final to = _hermite(_last, start, at, end, t);
      final length = (to - from).distance;
      while (along <= length) {
        final u = (m - 1 + along / length) / pieces;
        _path.add(Offset.lerp(from, to, along / length)!);
        _times.add(_lastTime + ((timeMs - _lastTime) * u).round());
        along += spacing;
      }
      along -= length;
      from = to;
    }
    _carry = along;
    _tangent = end / d;
  }

  /// [tangent], or [chord] when there is none or it turns sharply off it.
  static Offset _along(Offset? tangent, Offset chord) =>
      tangent != null && tangent.dx * chord.dx + tangent.dy * chord.dy > 0.5 ? tangent : chord;

  /// The unit direction at [c] of the parabola through [a], [b], [c]
  /// (parametrised by chord length), or null if they double back.
  static Offset? _endTangent(Offset a, Offset b, Offset c) {
    final d1 = (b - a).distance, d2 = (c - b).distance;
    if (d1 < 1e-6) return null;
    final v = a * (d2 / (d1 * (d1 + d2))) -
        b * ((d1 + d2) / (d1 * d2)) +
        c * ((d1 + 2 * d2) / ((d1 + d2) * d2));
    final length = v.distance;
    return length < 1e-9 ? null : v / length;
  }

  static Offset _hermite(Offset p0, Offset m0, Offset p1, Offset m1, double t) {
    final t2 = t * t, t3 = t2 * t;
    return p0 * (2 * t3 - 3 * t2 + 1) +
        m0 * (t3 - 2 * t2 + t) +
        p1 * (-2 * t3 + 3 * t2) +
        m1 * (t3 - t2);
  }

  /// Finds the cusps among the samples whose turn is known: where the
  /// line first turns by more than [minTurn], the tip is the sample within
  /// the baseline after it furthest along the way the line came (as the
  /// outline's corners are), decided as soon as the turn is known.
  void _findCusps({required bool ended}) {
    if (!_corners) return;
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
    final n = _path.length;
    var c = 0; // The first corner after the point.
    for (; _emitted <= last; _emitted++) {
      final i = _emitted;
      while (c < _cusps.length && _cusps[c] < i) {
        c++;
      }
      final lo = c > 0 ? _cusps[c - 1] : 0;
      final hi = c < _cusps.length ? _cusps[c] : (ended ? n - 1 : n + _k);
      onPoint(i == hi ? _path[i] : _smoothed(i, lo, math.min(hi, n - 1)), _times[i]);
    }
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
