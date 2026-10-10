import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/pressure_filter.dart';

/// Synthetic handwriting that looks like real digitiser input: cursive
/// letters from an oscillation model, sampled at 240 Hz with positional
/// jitter, noisy quantised pressure, the app's pressure filter and its
/// minimum point spacing. Deterministic for a given [seed].
class Handwriting {
  Handwriting({int seed = 7, this.jitter = 0.15, this.pressureNoise = 0.02})
    : _rng = math.Random(seed);

  final math.Random _rng;

  /// Standard deviation of positional noise, in world units (≈ screen px).
  final double jitter;

  /// Standard deviation of pressure noise (0..1 scale).
  final double pressureNoise;

  /// Sample rate of the simulated digitiser.
  static const double hz = 240;

  double _gauss() {
    final u = 1 - _rng.nextDouble(), v = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  /// Cursive loops in the Hollerbach oscillation model: each cycle is one
  /// letter. [letters] gives each cycle's (height, loop) pair: tall + wide
  /// loops look like `l`, short ones like `e`, loop ≈ 0 like `u`/`n`.
  List<StrokePoint> cursive(
    Offset origin,
    List<({double height, double loop})> letters, {
    double letterWidth = 8.5,
    double lettersPerSecond = 4.5,
  }) {
    final omega = 2 * math.pi * lettersPerSecond;
    final duration = letters.length / lettersPerSecond;
    final drift = letterWidth * lettersPerSecond;
    return _sample(duration, (t) {
      final k = math.min(letters.length - 1, (t * lettersPerSecond).floor());
      final cycle = t * lettersPerSecond - k;
      // Blend the letter shape across cycle boundaries for continuity.
      final next = letters[math.min(letters.length - 1, k + 1)];
      final cur = letters[k];
      final blend = _smoothstep((cycle - 0.75) / 0.25);
      final h = cur.height + (next.height - cur.height) * blend;
      final loop = cur.loop + (next.loop - cur.loop) * blend;
      final phase = omega * t;
      final x = drift * t + loop * math.sin(phase) * drift / omega;
      final y = -h * 0.5 * (1 - math.cos(phase));
      return Offset(origin.dx + x, origin.dy + y);
    });
  }

  /// A closed oval ("o"), drawn counter-clockwise from the top right.
  List<StrokePoint> oval(Offset center, double rx, double ry, {double seconds = 0.35}) =>
      _sample(seconds, (t) {
        final a = -math.pi / 3 - 2.15 * math.pi * t / seconds;
        return center + Offset(rx * math.cos(a), ry * math.sin(a));
      });

  /// An "s": top right → top left → bottom right → bottom left.
  List<StrokePoint> letterS(Offset origin, double size, {double seconds = 0.4}) =>
      _sample(seconds, (t) {
        final u = t / seconds;
        final x = size * 0.3 * math.cos(3 * math.pi * u);
        final y = -size * (1 - u) - size * 0.1 * math.sin(2 * math.pi * u);
        return origin + Offset(size * 0.35 + x, y);
      });

  /// A straight line, slightly accelerating then braking.
  List<StrokePoint> line(Offset a, Offset b, {double seconds = 0.3}) =>
      _sample(seconds, (t) => Offset.lerp(a, b, _smoothstep(t / seconds))!);

  /// Samples [at] (time → ideal position) like a stylus: 240 Hz, jitter,
  /// pressure ramp + slow variation + noise, then the app's own filtering.
  List<StrokePoint> _sample(double seconds, Offset Function(double t) at) {
    final filter = PressureFilter();
    final wobble = _rng.nextDouble() * 10;
    final out = <StrokePoint>[];
    Offset? last;
    final n = (seconds * hz).round();
    for (var i = 0; i <= n; i++) {
      final t = i / hz;
      final ideal = at(t);
      final p = ideal + Offset(_gauss() * jitter, _gauss() * jitter);
      final ramp = math.min(1.0, math.min(t / 0.04, (seconds - t) / 0.06 + 0.3));
      var raw = 0.5 * ramp + 0.08 * math.sin(t * 7 + wobble) + _gauss() * pressureNoise;
      raw = (raw.clamp(0.05, 1.0) * 4096).round() / 4096;
      final pressure = filter.next(raw);
      if (last != null && (p - last).distance < 0.75 && i != n) continue;
      last = p;
      out.add(StrokePoint(p.dx, p.dy, pressure));
    }
    final settled = PressureFilter.settleEnd([for (final s in out) s.pressure]);
    return [for (var i = 0; i < out.length; i++) StrokePoint(out[i].x, out[i].y, settled[i])];
  }

  static double _smoothstep(double x) {
    final t = x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

/// Letter shapes for [Handwriting.cursive].
const e = (height: 8.0, loop: 2.6);
const l = (height: 20.0, loop: 2.2);
const u = (height: 8.0, loop: 0.5);
