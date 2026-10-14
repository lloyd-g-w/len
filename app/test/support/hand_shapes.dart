import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/stroke.dart';

import 'handwriting.dart';

/// Hand-drawn shapes as a hand really draws them for "hold to snap":
/// rounded corners, bowed and wobbly sides, ends that miss or overshoot
/// the start, a little hook where the pen lands, slight rotation, sampled
/// at 240 Hz with jitter and the app's minimum spacing. Deterministic for
/// a [seed].
class HandShapes {
  HandShapes(int seed) : _rng = math.Random(seed);

  final math.Random _rng;

  double _between(double a, double b) => a + (b - a) * _rng.nextDouble();

  double _gauss() {
    final u = 1 - _rng.nextDouble(), v = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  /// A wobbly circle or ellipse (radii [rx], [ry], tilted by [angle]),
  /// begun anywhere and closed with a small gap or overshoot.
  List<Offset> ellipse(Offset centre, double rx, double ry, {double angle = 0}) {
    final start = _between(0, 2 * math.pi);
    final sweep = 2 * math.pi * _between(0.95, 1.1);
    final dir = _rng.nextBool() ? 1 : -1;
    final f1 = _between(0, 6), f2 = _between(0, 6);
    final wobble = _between(0.02, 0.045);
    final n = (sweep * math.max(rx, ry) / 2).round();
    return _sampled([
      for (var i = 0; i <= n; i++)
        () {
          final s = i / n;
          final t = start + dir * sweep * s;
          // Low-frequency radial wobble, as a hand's.
          final k = 1 + wobble * math.sin(2 * t + f1) + wobble * 0.6 * math.sin(3 * t + f2);
          final x = rx * k * math.cos(t), y = ry * k * math.sin(t);
          return centre + _rotate(Offset(x, y), angle);
        }(),
    ]);
  }

  /// A closed polygon through [corners] as a hand draws it: from a corner
  /// or mid-side, rounded corners, bowed sides, rotated by [angle] about
  /// their centre, ending a little short of or past the start.
  List<Offset> polygon(List<Offset> corners, {double angle = 0}) {
    final centre = corners.reduce((a, b) => a + b) / corners.length.toDouble();
    final c = [for (final p in corners) centre + _rotate(p - centre, angle)];
    final midSide = _rng.nextBool();
    final from = midSide ? Offset.lerp(c[0], c[1], _between(0.2, 0.6))! : c[0];
    final close = _between(-0.12, 0.15); // < 0: short of the start
    final path = <Offset>[from, ...c.skip(1), c[0]];
    if (midSide) path.add(from);
    final end = path.last, before = path[path.length - 2];
    path[path.length - 1] = end + (end - before) * close;
    final side = (c[1] - c[0]).distance;
    return _sampled(_wobble(_round(_dense(path), side * _between(0.04, 0.1)), side));
  }

  /// A nearly straight line from [a] to [b], slightly bowed.
  List<Offset> line(Offset a, Offset b) {
    final bow = _between(-0.03, 0.03);
    final normal = Offset(-(b - a).dy, (b - a).dx);
    final n = ((b - a).distance / 2).round();
    return _sampled(
      _wobble([
        for (var i = 0; i <= n; i++)
          Offset.lerp(a, b, i / n)! + normal * (bow * 4 * (i / n) * (1 - i / n)),
      ], (b - a).distance),
    );
  }

  /// An arrow in one stroke: the shaft from [tail] to [tip], then one
  /// wing, back to the tip and the other wing.
  List<Offset> arrow(Offset tail, Offset tip) {
    final v = tip - tail;
    final head = v.distance * _between(0.15, 0.25);
    final back = -v / v.distance * head;
    final spread = _between(0.4, 0.65);
    final w1 = tip + _rotate(back, spread), w2 = tip + _rotate(back, -spread);
    final path = [tail, tip, w1, tip + Offset(_gauss(), _gauss()), w2];
    return _sampled(_wobble(_round(_dense(path), head * 0.08), v.distance * 0.5));
  }

  /// Ordinary handwriting: a few cursive words, letters and digits, none
  /// of which should ever snap, at [origin].
  static List<List<Offset>> writing(Offset origin, {int seed = 3}) {
    final hand = Handwriting(seed: seed, jitter: 0.25);
    List<Offset> xy(List<StrokePoint> pts) => [for (final p in pts) p.offset];
    return [
      xy(hand.cursive(origin, [l, e, u, e, l, u])),
      xy(hand.cursive(origin + const Offset(0, 50), [u, u, e, u, l, l, e])),
      xy(hand.oval(origin + const Offset(20, 110), 9, 10)), // o
      xy(hand.oval(origin + const Offset(60, 110), 16, 18)), // O
      xy(hand.letterS(origin + const Offset(100, 125), 24)),
      xy(hand.cursive(origin + const Offset(140, 125), [e, e, e])),
      // A check mark and a "2".
      xy(hand.cursive(origin + const Offset(200, 125), [u])),
      [
        for (var t = 0.0; t <= 1; t += 0.02)
          origin + Offset(240 + 18 * math.sin(t * math.pi * 1.4), 100 + 30 * t),
        for (var t = 0.0; t <= 1; t += 0.05) origin + Offset(240 + 24 * t, 130.0),
      ],
    ];
  }

  // ---------------------------------------------------------------------------

  /// [path] with points at most 2 apart.
  static List<Offset> _dense(List<Offset> path) => [
    path.first,
    for (var i = 1; i < path.length; i++)
      for (var k = 1, n = math.max(1, ((path[i] - path[i - 1]).distance / 2).ceil()); k <= n; k++)
        Offset.lerp(path[i - 1], path[i], k / n)!,
  ];

  /// Rounds the corners of the dense [path] (a moving average over
  /// [radius]).
  static List<Offset> _round(List<Offset> path, double radius) {
    final reach = math.max(1, (radius / 2).round());
    return [
      for (var i = 0; i < path.length; i++)
        () {
          var sum = Offset.zero;
          var n = 0;
          for (var k = math.max(0, i - reach); k <= math.min(path.length - 1, i + reach); k++) {
            sum += path[k];
            n++;
          }
          return sum / n.toDouble();
        }(),
    ];
  }

  /// Low-frequency sideways wobble on [path] ([size] its scale).
  List<Offset> _wobble(List<Offset> path, double size) {
    final amp = size * _between(0.006, 0.014);
    final f = _between(0, 6);
    final out = <Offset>[];
    for (var i = 0; i < path.length; i++) {
      final a = path[math.max(0, i - 1)], b = path[math.min(path.length - 1, i + 1)];
      final d = b - a;
      final normal = d.distance == 0 ? Offset.zero : Offset(-d.dy, d.dx) / d.distance;
      out.add(path[i] + normal * (amp * math.sin(i * 0.05 + f)));
    }
    return out;
  }

  /// Samples [path] like a stylus: a landing hook, jitter, the minimum
  /// spacing.
  List<Offset> _sampled(List<Offset> path) {
    final out = <Offset>[];
    final d0 = path.length > 3 ? path[3] - path[0] : const Offset(1, 0);
    final hookDir = _rotate(d0 / math.max(d0.distance, 1e-9), _between(1.6, 2.6));
    out.add(path.first + hookDir * _between(1, 3));
    for (final p in path) {
      final q = p + Offset(_gauss(), _gauss()) * 0.3;
      if ((q - out.last).distance >= 0.75) out.add(q);
    }
    return out;
  }

  static Offset _rotate(Offset v, double a) =>
      Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));
}
