import 'dart:math' as math;
import 'dart:ui';

/// The pen's stabiliser: a speed-adaptive, time-based low-pass filter on
/// the pen's path, applied to every sample before it becomes a stroke
/// point (`InkDrawing`; the low-latency overlay applies the same,
/// `WetInkModel`). See docs/ARCHITECTURE.md, *Stabiliser*.
///
/// It is a variant of the 1€ filter (Casiez, Roussel & Vogel, CHI 2012):
/// the ink follows the pen with a time constant that shrinks with the
/// pen's speed, so a slow, shaky hand is smoothed strongly while fast
/// writing passes almost untouched,
///
///   τ(v) = [restTau] / (1 + (v / [speed])²),
///
/// with v the pen's speed (its velocity low-passed over [velocityTau],
/// then held at its peak for about [holdTau], so the brief stop at a cusp
/// of fast writing does not smooth it: the corner keeps its point). The
/// square makes the trail in pixels (v · τ) peak at a crawl and fall as
/// the pen speeds up, where the 1€ filter's (linear) trail would only
/// level off: ≈ 1 px at 1000 px/s even at full strength.
///
/// Each step solves the filter exactly for the pen moving in a straight
/// line at constant speed between two samples (a first-order hold), so
/// the path does not depend on the sample rate (120, 240 Hz, 1 kHz) or on
/// irregular timestamps, only on the pen's motion.
///
/// It is causal: every output is final as soon as its sample arrives, so
/// live ink reaches the filtered point with nothing provisional and the
/// stroke stores the filtered points (with stabiliser 0 in its style):
/// live and committed ink are the same, and a reload draws them again. At
/// pen-up the ink goes on to where the pen lifted ([pen]).
class PenStabiliser {
  PenStabiliser(this.params);

  final StabiliserParams params;

  /// The ink's position: the filtered pen.
  Offset get ink => _y;
  Offset _y = Offset.zero;

  /// The pen's newest position (unfiltered).
  Offset get pen => _x;
  Offset _x = Offset.zero;

  /// How far the ink trails the pen.
  double get gap => (_x - _y).distance;

  int _t = 0;
  double _vx = 0, _vy = 0, _speed = 0;
  bool _started = false;

  // Where the stroke started; the ink is the pen's own until the pen has
  // moved [StabiliserParams.engage] from there.
  Offset _start = Offset.zero;
  bool _engaged = false;

  // The pen's latest positions, for [catchUp].
  final List<double> _hx = [], _hy = [];
  static const int _kept = 64;

  void _remember(Offset at) {
    _hx.add(at.dx);
    _hy.add(at.dy);
    if (_hx.length > _kept) {
      _hx.removeAt(0);
      _hy.removeAt(0);
    }
  }

  /// Starts a stroke at [at] (the ink starts under the nib) at [timeMs].
  void begin(Offset at, int timeMs) {
    _hx.clear();
    _hy.clear();
    _remember(at);
    _x = _y = at;
    _t = timeMs;
    _vx = _vy = _speed = 0;
    _start = at;
    _engaged = false;
    _started = true;
  }

  /// The pen moved to [at] at [timeMs]: returns the ink's new position.
  Offset add(Offset at, int timeMs) {
    if (!_started) {
      begin(at, timeMs);
      return at;
    }
    _remember(at);
    final dt = (timeMs - _t) / 1000;
    if (dt <= 0) {
      // No time passed (samples of the same millisecond, or input without
      // timestamps): the filter cannot act, the ink moves with the pen.
      _y = Offset(_y.dx + (at.dx - _x.dx), _y.dy + (at.dy - _x.dy));
      _x = at;
      return _y;
    }
    final p = params;
    // The pen's velocity over the step, low-passed (exact for a constant
    // velocity during the step) and held at its peak.
    final ux = (at.dx - _x.dx) / dt, uy = (at.dy - _x.dy) / dt;
    final kv = 1 - math.exp(-dt / p.velocityTau);
    _vx += (ux - _vx) * kv;
    _vy += (uy - _vy) * kv;
    final v = math.sqrt(_vx * _vx + _vy * _vy);
    _speed = math.max(v, _speed * math.exp(-dt / p.holdTau));
    final r = _speed / p.speed;
    final tau = p.restTau / (1 + r * r);
    // y' = (x − y) / τ with x moving at (ux, uy): the trail e = x − y
    // relaxes towards u·τ.
    final k = math.exp(-dt / tau);
    final ex = ux * tau + (_x.dx - _y.dx - ux * tau) * k;
    final ey = uy * tau + (_x.dy - _y.dy - uy * tau) * k;
    _x = at;
    _t = timeMs;
    if (!_engaged) {
      // The stroke's first px are the pen's: it starts where the pen
      // landed, and a pen-down hook keeps the kink `HookFinder` trims it
      // by (smoothed, it would become a curve the ink starts with). The
      // speed is tracked meanwhile, so the filter starts warm.
      final dx = at.dx - _start.dx, dy = at.dy - _start.dy;
      _engaged = dx * dx + dy * dy >= p.engage * p.engage;
      _y = at;
      return _y;
    }
    _y = Offset(at.dx - ex, at.dy - ey);
    return _y;
  }

  /// The ink catching up with the pen (at the lift, and before hold to
  /// snap reads the stroke): points from the ink along the pen's latest
  /// path to the pen, the ink's offset from that path fading out along it
  /// (by length), so the end follows the curve the pen drew rather than
  /// cutting across it, and a pen-up hook keeps its kink. The ink is at
  /// the pen afterwards.
  List<Offset> catchUp() {
    final n = _hx.length;
    // The pen's position nearest the ink.
    var j = n - 1;
    var best = double.infinity;
    for (var i = n - 1; i >= 0; i--) {
      final dx = _hx[i] - _y.dx, dy = _hy[i] - _y.dy;
      final d = dx * dx + dy * dy;
      if (d < best) {
        best = d;
        j = i;
      }
    }
    final ox = _y.dx - _hx[j], oy = _y.dy - _hy[j];
    var total = 0.0;
    for (var k = j + 1; k < n; k++) {
      total += _distance(_hx[k] - _hx[k - 1], _hy[k] - _hy[k - 1]);
    }
    final out = <Offset>[];
    var along = 0.0;
    for (var k = j + 1; k < n; k++) {
      along += _distance(_hx[k] - _hx[k - 1], _hy[k] - _hy[k - 1]);
      final w = total > 0 ? 1 - along / total : 0.0;
      out.add(Offset(_hx[k] + ox * w, _hy[k] + oy * w));
    }
    if (out.isEmpty || out.last != _x) out.add(_x);
    _y = _x;
    return out;
  }

  static double _distance(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
}

/// The stabiliser's numbers for a setting (`PenConfig.streamline`, 0..1),
/// in the units of the positions it filters (logical screen px; the
/// overlay's are [scaled]).
class StabiliserParams {
  const StabiliserParams({
    required this.restTau,
    required this.speed,
    this.velocityTau = defaultVelocityTau,
    this.holdTau = defaultHoldTau,
    this.engage = defaultEngage,
  });

  /// The stabiliser at [setting] (0..1; 0: off, null), for positions in
  /// screen px times [scale].
  ///
  /// The setting is the time constant at rest, linearly: 40 ms at 10 %,
  /// 120 ms at 30 % (the pen's default: jitter goes, no visible trail),
  /// 400 ms at 100 % (slow lines come out smooth, the ink drawn after the
  /// pen as on a string). The speed scale is the same throughout, so fast
  /// writing is never held back much.
  static StabiliserParams? of(double setting, {double scale = 1}) {
    if (!(setting > 0)) return null;
    return StabiliserParams(
      restTau: maxRestTau * setting.clamp(0.0, 1.0),
      speed: speed0 * scale,
      engage: defaultEngage * scale,
    );
  }

  /// The time constant at rest at full strength (s).
  static const double maxRestTau = 0.4;

  /// The speed (screen px/s) at which the time constant has halved.
  static const double speed0 = 50;

  static const double defaultVelocityTau = 0.008;
  static const double defaultHoldTau = 0.16;

  /// How far (screen px) the pen moves from pen-down before the filter
  /// acts: past the longest pen-down hook (`HookFinder`, 3 px).
  static const double defaultEngage = 4;

  /// Time constant (s) of the ink following a resting pen.
  final double restTau;

  /// Speed (px/s) at which the time constant halves.
  final double speed;

  /// Time constant (s) of the speed estimate's low-pass, and how long (s)
  /// it holds a peak (it decays by e over that time).
  final double velocityTau, holdTau;

  /// How far (px) the pen moves from pen-down before the filter acts.
  final double engage;

  /// The same with lengths multiplied by [f].
  StabiliserParams scaled(double f) => StabiliserParams(
    restTau: restTau,
    speed: speed * f,
    velocityTau: velocityTau,
    holdTau: holdTau,
    engage: engage * f,
  );

  /// The values in the order the overlay's `begin` message carries them.
  List<double> toList() => [restTau, speed, velocityTau, holdTau, engage];

  @override
  bool operator ==(Object other) =>
      other is StabiliserParams &&
      other.restTau == restTau &&
      other.speed == speed &&
      other.velocityTau == velocityTau &&
      other.holdTau == holdTau &&
      other.engage == engage;

  @override
  int get hashCode => Object.hash(restTau, speed, velocityTau, holdTau, engage);
}
