import 'dart:math' as math;
import 'dart:ui';

/// The true motion of the pen tip during one contact: where it is and how
/// hard it presses at time t (seconds since pen-down). This is the ground
/// truth a simulated recording is measured against.
class PenMotion {
  PenMotion({
    required this.duration,
    required this.at,
    required this.pressure,
    this.cusps = const [],
  });

  /// Contact length in seconds (0 for a tap of one sample).
  final double duration;

  /// Tip position (logical screen px of the surface) at time t.
  final Offset Function(double t) at;

  /// Pressure at time t as the ink should show it (0..1; 0.5 is medium,
  /// the pen's width). The hand presses [devicePressure] for it.
  final double Function(double t) pressure;

  /// The device pressure (0..1) the hand presses at time t: what gives
  /// [pressure] through the input's `PressureCurve` (S Pen handwriting
  /// presses about 0.2 for medium).
  double devicePressure(double t) {
    final y = pressure(t);
    return y / (4 - 3 * y); // the inverse of 4p / (3p + 1)
  }

  /// Times of deliberate sharp reversals (the tip of a "v").
  final List<double> cusps;

  /// The path sampled every [dt] seconds (dense ground truth).
  List<Offset> path({double dt = 0.0005}) => [
    for (var i = 0; i <= (duration / dt).ceil(); i++) at(math.min(duration, i * dt)),
  ];

  /// The true device pressure ([devicePressure]) every [dt] seconds.
  List<double> pressures({double dt = 0.0005}) => [
    for (var i = 0; i <= (duration / dt).ceil(); i++) devicePressure(math.min(duration, i * dt)),
  ];

  /// The same motion moved by [by].
  PenMotion shifted(Offset by) =>
      PenMotion(duration: duration, at: (t) => at(t) + by, pressure: pressure, cusps: cusps);
}

/// Minimum-jerk position profile 0..1 (zero speed and acceleration at both ends).
double minJerk(double u) {
  final x = u.clamp(0.0, 1.0);
  return x * x * x * (10 - 15 * x + 6 * x * x);
}

double _smoothstep(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// A natural pressure curve: rises over the first 25 ms, eases off over the
/// last 30 ms, and follows [body] in between.
double Function(double) pressureCurve(double duration, double Function(double t) body) => (t) {
  final rise = _smoothstep(t / 0.025);
  final fall = 0.35 + 0.65 * _smoothstep((duration - t) / 0.03);
  return (body(t) * math.min(rise, fall)).clamp(0.0, 1.0);
};

/// Letter shape for [cursive]: x-height multiple and loop width.
typedef Letter = ({double height, double loop});

const Letter letterE = (height: 1.0, loop: 2.6);
const Letter letterL = (height: 2.4, loop: 2.2);
const Letter letterU = (height: 1.0, loop: 0.5);

/// Cursive handwriting in the Hollerbach oscillation model: each cycle is
/// one letter, [xHeight] px tall, [letterWidth] px wide.
PenMotion cursive(
  Offset origin,
  List<Letter> letters, {
  double xHeight = 10,
  double letterWidth = 10,
  double lettersPerSecond = 4.5,
  double pressure = 0.45,
}) {
  final duration = letters.length / lettersPerSecond;
  final omega = 2 * math.pi * lettersPerSecond;
  final drift = letterWidth * lettersPerSecond;
  Offset at(double t) {
    final k = math.min(letters.length - 1, (t * lettersPerSecond).floor());
    final cycle = t * lettersPerSecond - k;
    final cur = letters[k], next = letters[math.min(letters.length - 1, k + 1)];
    final blend = _smoothstep((cycle - 0.75) / 0.25);
    final h = (cur.height + (next.height - cur.height) * blend) * xHeight;
    final loop = cur.loop + (next.loop - cur.loop) * blend;
    final phase = omega * t;
    final x = drift * t + loop * math.sin(phase) * drift / omega;
    final y = -h * 0.5 * (1 - math.cos(phase));
    return origin + Offset(x, y);
  }

  return PenMotion(
    duration: duration,
    at: at,
    pressure: pressureCurve(duration, (t) => pressure + 0.08 * math.sin(t * 7)),
  );
}

/// Fast small loops (a prolate cycloid): [count] loops of radius [radius]
/// at [loopsPerSecond], drifting right.
PenMotion loops(
  Offset origin, {
  int count = 6,
  double radius = 7,
  double loopsPerSecond = 6,
  double advance = 9,
}) {
  final duration = count / loopsPerSecond;
  final omega = 2 * math.pi * loopsPerSecond;
  return PenMotion(
    duration: duration,
    at: (t) =>
        origin +
        Offset(
          advance * loopsPerSecond * t - radius * math.sin(omega * t),
          -radius * (1 - math.cos(omega * t)),
        ),
    pressure: pressureCurve(duration, (_) => 0.5),
  );
}

/// Straight segments through [corners], each with a minimum-jerk speed
/// profile (the pen stops at every reversal, like a real zigzag).
PenMotion polyline(List<Offset> corners, {double segmentSeconds = 0.12, double pressure = 0.5}) {
  final n = corners.length - 1;
  final duration = n * segmentSeconds;
  return PenMotion(
    duration: duration,
    at: (t) {
      final k = math.min(n - 1, (t / segmentSeconds).floor());
      final u = (t - k * segmentSeconds) / segmentSeconds;
      return Offset.lerp(corners[k], corners[k + 1], minJerk(u))!;
    },
    pressure: pressureCurve(duration, (_) => pressure),
    cusps: [for (var k = 1; k < n; k++) k * segmentSeconds],
  );
}

/// A zigzag of [count] strokes [height] px tall, [pitch] px apart.
PenMotion zigzag(
  Offset origin, {
  int count = 6,
  double height = 24,
  double pitch = 8,
  double seconds = 0.1,
}) => polyline([
  for (var i = 0; i <= count; i++) origin + Offset(i * pitch, i.isEven ? 0 : -height),
], segmentSeconds: seconds);

/// A straight line from [a] to [b].
PenMotion line(Offset a, Offset b, {double seconds = 0.25, double pressure = 0.5}) =>
    polyline([a, b], segmentSeconds: seconds, pressure: pressure);

/// A slow, gently curving line whose pressure swells from light to full
/// and back.
PenMotion swell(Offset origin, {double length = 220, double seconds = 2}) => PenMotion(
  duration: seconds,
  at: (t) {
    final u = minJerk(t / seconds);
    return origin + Offset(length * u, 6 * math.sin(u * math.pi * 2));
  },
  pressure: pressureCurve(seconds, (t) => 0.08 + 0.9 * math.sin(math.pi * t / seconds)),
);

/// A tap: a brief, almost still contact (dotting an "i").
PenMotion tap(Offset at, {double seconds = 0.045, double pressure = 0.5}) => PenMotion(
  duration: seconds,
  at: (t) => at + Offset(0.3 * t / seconds, 0.2 * t / seconds),
  pressure: (t) =>
      pressure * math.min(1, math.min(t / 0.015, (seconds - t) / 0.015 + 0.3)).clamp(0.0, 1.0),
);

/// An inward spiral: curvature rising smoothly (edge smoothness at zoom).
PenMotion spiral(
  Offset centre, {
  double from = 40,
  double to = 6,
  double turns = 2.5,
  double seconds = 1.6,
}) {
  return PenMotion(
    duration: seconds,
    at: (t) {
      final u = t / seconds;
      final a = 2 * math.pi * turns * u;
      final r = from + (to - from) * u;
      return centre + Offset(r * math.cos(a), r * math.sin(a));
    },
    pressure: pressureCurve(seconds, (t) => 0.5 + 0.1 * math.sin(t * 5)),
  );
}
