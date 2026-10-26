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
/// the ink follows it in small steps (a [_steps]th of the radius, ½ px at
/// most), so
/// the path does not depend on the sample rate (120, 240 Hz, 1 kHz), only
/// on the pen's path.
///
/// The first [StabiliserParams.engage] px from pen-down are the pen's own
/// (a pen-down hook keeps its kink for `HookFinder`); from there the
/// string grows to its length over twice that length of travel.
///
/// It is causal: every output is final as soon as its sample arrives, so
/// live ink reaches the stabilised point with nothing provisional and the
/// stroke stores the stabilised points (with stabiliser 0 in its style):
/// live and committed ink are the same, and a reload draws them again. At
/// pen-up the stroke stops where the ink is, up to the string's length
/// short of the pen (as Krita's lazy brush): the unfinished tail is
/// dropped, not drawn (the owner's choice: drawn along the pen's path it
/// was the raw, unsmoothed hand for the last string's length).
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

  // Where the stroke started; the ink is the pen's own until the pen has
  // moved [StabiliserParams.engage] from there.
  double _sx = 0, _sy = 0;
  bool _engaged = false;

  // How far the pen has moved since the string engaged: the string grows
  // from nothing by [_growth] of that to its full length, so the ink
  // leaves the raw start in the pen's direction (a string slack there
  // would hold the ink still and then pull it off at an angle, a kink),
  // first at half the pen's pace.
  double _travel = 0;
  static const double _growth = 0.5;

  /// The ink follows the pen in steps of at most radius / [_steps], and
  /// at most engage / [_perEngage] (½ screen px: lengths in the units of
  /// the positions, so the overlay's physical px take the same steps).
  static const int _steps = 32;
  static const double _perEngage = 8;

  /// At most this many steps between two samples (a jump of the pen).
  static const int _maxSteps = 1024;

  /// Starts a stroke at [at]: the ink starts under the nib.
  void begin(Offset at) {
    _px = _ix = at.dx;
    _py = _iy = at.dy;
    _sx = _px;
    _sy = _py;
    _engaged = false;
    _started = true;
  }

  /// The pen moved to [at]: returns the ink's new position.
  Offset add(Offset at) {
    if (!_started) {
      begin(at);
      return at;
    }
    final x = at.dx, y = at.dy;
    if (!_engaged) {
      // The stroke's first px are the pen's: it starts where the pen
      // landed, and a pen-down hook keeps the kink `HookFinder` trims it
      // by (pulled on the string, the ink would start at the hook's tip
      // and lean from there).
      final e = params.engage;
      final ux = _px - _sx, uy = _py - _sy, dx = x - _px, dy = y - _py;
      final ex = ux + dx, ey = uy + dy;
      if (ex * ex + ey * ey < e * e) {
        _px = _ix = x;
        _py = _iy = y;
        return at;
      }
      // The string engages where the step leaves the circle of [e] around
      // the start (whatever the sample rate): |u + t d| = e.
      final a = dx * dx + dy * dy, b = ux * dx + uy * dy, c = ux * ux + uy * uy - e * e;
      final t = (-b + math.sqrt(b * b - a * c)) / a;
      _px = _ix = _px + dx * t;
      _py = _iy = _py + dy * t;
      _engaged = true;
      _travel = 0;
    }
    final r = params.radius;
    final dx = x - _px, dy = y - _py;
    final d = _distance(dx, dy);
    final n = math.min(
      _maxSteps,
      math.max(1, (d * math.max(_steps / r, _perEngage / params.engage)).ceil()),
    );
    for (var i = 1; i < n; i++) {
      final f = i / n;
      _pull(_px + dx * f, _py + dy * f, math.min(r, (_travel + d * f) * _growth));
    }
    _travel += d;
    _pull(x, y, math.min(r, _travel * _growth));
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

  static double _distance(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
}

/// The stabiliser's numbers for a setting (`PenConfig.streamline`, 0..1),
/// in the units of the positions it stabilises (logical screen px; the
/// overlay's are [scaled]).
class StabiliserParams {
  const StabiliserParams({required this.radius, this.engage = defaultEngage});

  /// The stabiliser at [setting] (0..1; 0: off, null), for positions in
  /// screen px times [scale].
  static StabiliserParams? of(double setting, {double scale = 1}) {
    if (!(setting > 0)) return null;
    return StabiliserParams(radius: radiusAt(setting) * scale, engage: defaultEngage * scale);
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

  /// How far (screen px) the pen moves from pen-down before the string
  /// acts: past the longest pen-down hook (`HookFinder`, 3 px).
  static const double defaultEngage = 4;

  /// How far (px) the pen moves from pen-down before the string acts.
  final double engage;

  /// The string's length (px): how far the pen moves from the ink before
  /// it pulls the ink along.
  final double radius;

  /// The same with lengths multiplied by [f].
  StabiliserParams scaled(double f) => StabiliserParams(radius: radius * f, engage: engage * f);

  /// The values in the order the overlay's `begin` message carries them.
  List<double> toList() => [radius, engage];

  @override
  bool operator ==(Object other) =>
      other is StabiliserParams && other.radius == radius && other.engage == engage;

  @override
  int get hashCode => Object.hash(radius, engage);
}
