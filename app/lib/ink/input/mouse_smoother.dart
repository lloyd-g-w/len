import 'dart:math' as math;
import 'dart:ui';

/// Takes the whole-pixel steps out of a mouse's path before it becomes
/// ink (screen pixels and milliseconds, fed as the mouse moves).
///
/// A stylus reports positions to a fraction of a pixel; a mouse (on the
/// web and desktops) to whole pixels, so its path is a staircase with
/// ±0.5 px of error at every sample. At 100 % a pen 2.5 px wide hides it;
/// zoomed out the pen is a fraction of a pixel wide on screen and the
/// steps show as squiggles (and zoomed back in, they are as many times
/// larger in world units as the zoom was small). The outline's own
/// smoothing works in world units relative to the pen's width (its
/// geometry stays exact that way), so it cannot remove them there.
///
/// So the path is resampled every [spacing] px and smoothed with a
/// Gaussian of [sigma] px, centred: a point is passed on once the samples
/// [reach] past it are known, so the ink trails the mouse by about
/// [reach] px (as with the stabiliser) and never changes once drawn. The
/// window shrinks symmetrically towards both ends, so the stroke starts
/// and ends exactly where the mouse went down and up. The same at any
/// zoom: it works on the screen, where the steps are.
class MouseSmoother {
  /// [onPoint] receives each smoothed point (screen px) and its time.
  MouseSmoother(this.onPoint);

  final void Function(Offset at, int timeMs) onPoint;

  /// Resampling step (px).
  static const double spacing = 1;

  /// Smoothing (px): enough to level the steps of a slanted line.
  static const double sigma = 2;

  /// How far (px) the ink trails the mouse.
  static double get reach => _k * spacing;

  static final int _k = (3 * sigma / spacing).ceil();
  static final List<double> _weights = [
    for (var i = 0; i <= _k; i++) math.exp(-0.5 * math.pow(i * spacing / sigma, 2)),
  ];

  final List<Offset> _path = [];
  final List<int> _times = [];

  /// Points passed on so far (the first is the mouse-down's, not passed).
  int _emitted = 1;

  /// Distance along the last raw segment to the next resampled point.
  double _carry = spacing;
  Offset _last = Offset.zero;
  int _lastTime = 0;

  /// Starts a stroke at [at] (passed on by the caller as the first point).
  void begin(Offset at, int timeMs) {
    _path
      ..clear()
      ..add(at);
    _times
      ..clear()
      ..add(timeMs);
    _emitted = 1;
    _carry = spacing;
    _last = at;
    _lastTime = timeMs;
  }

  /// The mouse moved to [at].
  void add(Offset at, int timeMs) {
    final d = (at - _last).distance;
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
    _emitUpTo(_path.length - 1 - _k);
  }

  /// The mouse went up at its last position: passes on the rest of the
  /// path, ending there.
  void finish() {
    if (_path.isEmpty) return;
    if (_path.last != _last) {
      _path.add(_last);
      _times.add(_lastTime);
    }
    _emitUpTo(_path.length - 1);
  }

  void _emitUpTo(int last) {
    final n = _path.length;
    for (; _emitted <= last; _emitted++) {
      final i = _emitted;
      final r = math.min(_k, math.min(i, n - 1 - i));
      var x = 0.0, y = 0.0, w = 0.0;
      for (var j = -r; j <= r; j++) {
        final weight = _weights[j.abs()];
        x += _path[i + j].dx * weight;
        y += _path[i + j].dy * weight;
        w += weight;
      }
      onPoint(Offset(x / w, y / w), _times[i]);
    }
  }
}
