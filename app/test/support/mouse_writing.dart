import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/input_recording.dart';

/// Synthetic mouse handwriting: smooth true paths (screen px) written at a
/// given speed, polled by a mouse at a given rate, reported in whole
/// pixels and delivered as desktops and browsers deliver them. For
/// measuring how smooth mouse ink is (`test/mouse_ink_smoothness_test.dart`).

/// A stroke's true path: dense points (screen px) and the speed it is
/// written at.
class TruePath {
  TruePath(this.points, {this.cusps = const []});

  /// Dense (≤ 0.1 px apart) points along the path.
  final List<Offset> points;

  /// Deliberate sharp turns (a cusp is a corner of the hand's motion).
  final List<Offset> cusps;

  late final List<double> _s = () {
    final s = [0.0];
    for (var i = 1; i < points.length; i++) {
      s.add(s.last + (points[i] - points[i - 1]).distance);
    }
    return s;
  }();

  double get length => _s.last;

  /// The point [d] px along the path.
  Offset at(double d) {
    if (d <= 0) return points.first;
    if (d >= length) return points.last;
    var lo = 0, hi = _s.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_s[mid] <= d) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (d - _s[lo]) / (_s[hi] - _s[lo]);
    return Offset.lerp(points[lo], points[hi], t)!;
  }

  /// This path moved by [by] and scaled by [scale] about the origin.
  TruePath transformed(Offset by, [double scale = 1]) => TruePath(
    [for (final p in points) p * scale + by],
    cusps: [for (final p in cusps) p * scale + by],
  );
}

/// A smooth path through [pieces], each a list of control points joined by
/// a Catmull-Rom spline; pieces meet at cusps (sharp turns).
TruePath glyph(List<List<Offset>> pieces) {
  final out = <Offset>[];
  final cusps = <Offset>[];
  for (final (k, piece) in pieces.indexed) {
    if (k > 0) cusps.add(piece.first);
    final spline = _spline(piece);
    out.addAll(k == 0 ? spline : spline.skip(1));
  }
  return TruePath(out, cusps: cusps);
}

List<Offset> _spline(List<Offset> c) {
  if (c.length == 2) {
    final n = math.max(1, ((c[1] - c[0]).distance / 0.05).ceil());
    return [for (var i = 0; i <= n; i++) Offset.lerp(c[0], c[1], i / n)!];
  }
  final out = [c.first];
  for (var i = 0; i + 1 < c.length; i++) {
    final p0 = i == 0 ? c[0] * 2 - c[1] : c[i - 1];
    final p1 = c[i], p2 = c[i + 1];
    final p3 = i + 2 < c.length ? c[i + 2] : c[i + 1] * 2 - c[i];
    final n = math.max(4, ((p2 - p1).distance / 0.05).ceil());
    for (var k = 1; k <= n; k++) {
      final t = k / n, t2 = t * t, t3 = t2 * t;
      out.add(
        (p1 * 2 +
                (p2 - p0) * t +
                (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                (p1 * 3 - p0 - p2 * 3 + p3) * t3) *
            0.5,
      );
    }
  }
  return out;
}

/// "x∈ℝ → f(x)dx" as the owner wrote it with a mouse, letters [h] px tall
/// (x-height h / 2), from [origin] (left end of the baseline).
List<TruePath> ownerFormula({Offset origin = const Offset(30, 90), double h = 40}) {
  final u = h / 40; // design units: 40 tall
  List<Offset> pts(double x0, List<(double, double)> p) => [
    for (final (x, y) in p) Offset(origin.dx + (x0 + x) * u, origin.dy - y * u),
  ];
  TruePath g(double x0, List<List<(double, double)>> pieces) =>
      glyph([for (final p in pieces) pts(x0, p)]);
  List<TruePath> letterX(double x0) => [
    g(x0, [
      [(0, 20), (5, 15), (10, 9), (16, 0)],
    ]),
    g(x0, [
      [(16, 20), (11, 14), (5, 6), (0, 0)],
    ]),
  ];
  return [
    ...letterX(0),
    // ∈: a C, then its bar.
    g(26, [
      [(20, 20), (8, 19), (1, 10), (8, 1), (20, 0)],
    ]),
    g(26, [
      [(3, 10), (17, 10)],
    ]),
    // ℝ: two stems, then the bowl and the leg (a cusp between them).
    g(56, [
      [(0, 40), (0, 0)],
    ]),
    g(56, [
      [(5, 40), (5, 0)],
    ]),
    g(56, [
      [(0, 40), (14, 39), (21, 32), (17, 23), (5, 21)],
      [(5, 21), (13, 11), (24, 0)],
    ]),
    // →: a long shaft, then the head (a cusp at the point).
    g(96, [
      [(0, 12), (60, 13)],
    ]),
    g(96, [
      [(50, 20), (55, 16), (60, 13)],
      [(60, 13), (55, 8), (50, 4)],
    ]),
    // f: the hook and the descender, then the bar.
    g(176, [
      [(18, 36), (12, 40), (6, 35), (5, 20), (4, 2), (2, -10), (-4, -12)],
    ]),
    g(176, [
      [(-2, 20), (14, 20)],
    ]),
    // ( x )
    g(200, [
      [(8, 38), (1, 18), (2, 2), (8, -6)],
    ]),
    ...letterX(214),
    g(236, [
      [(0, 38), (7, 18), (6, 2), (0, -6)],
    ]),
    // d: the bowl, then the stem.
    g(254, [
      [(16, 15), (8, 19), (1, 11), (4, 1), (12, 0), (16, 6)],
    ]),
    g(254, [
      [(17, 40), (17, 0)],
    ]),
    ...letterX(278),
  ];
}

/// Straight lines [length] px long at [angles] (degrees), for width and
/// edge checks along constant-speed straight segments.
List<TruePath> straightLines({
  List<double> angles = const [1, 3, 10, 30, 45, 80],
  double length = 160,
  Offset origin = const Offset(40, 300),
}) => [
  for (final (i, a) in angles.indexed)
    glyph([
      [
        origin + Offset(i * 4.0, i * 40.0),
        origin +
            Offset(i * 4.0, i * 40.0) +
            Offset(math.cos(a * math.pi / 180), -math.sin(a * math.pi / 180)) * length,
      ],
    ]),
];

/// How the events of a mouse reach the app.
enum Delivery {
  /// Every poll is its own event (browsers with coalesced events, Windows).
  raw,

  /// Events queue up and arrive together once per frame, each with its
  /// own time (X11 without compression).
  batched,

  /// Only the newest position per frame arrives (GTK's motion compression,
  /// browsers without coalesced events).
  coalesced,
}

/// A mouse: [hz] polls a second, each interval off by up to ±[jitter] of
/// itself, positions rounded to whole logical pixels ([quantum]).
class MouseModel {
  const MouseModel({
    this.hz = 125,
    this.jitter = 0.3,
    this.delivery = Delivery.raw,
    this.frameHz = 60,
    this.quantum = 1,
    this.seed = 3,
  });

  final double hz, jitter, frameHz, quantum;
  final Delivery delivery;
  final int seed;

  @override
  String toString() => '${hz.round()} Hz ${delivery.name}';
}

/// One stroke of a mouse recording: when its events were sent, where.
class MouseEvent {
  MouseEvent(this.timeUs, this.position);
  final int timeUs;
  final Offset position;
}

/// A recording of [paths] written with a mouse ([model]) at [speed] px/s
/// (ramping up and down over the first and last 15 % of each stroke), on
/// a view at [zoom] with the pen [pen]. Also returns each stroke's events.
/// [kind] makes it another pointer (a stylus, at constant pressure).
({InputRecording recording, List<List<MouseEvent>> events}) mouseRecording(
  List<TruePath> paths, {
  required MouseModel model,
  required double speed,
  required PenSettings pen,
  double zoom = 1,
  Size view = const Size(1000, 700),
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) {
  final rng = math.Random(model.seed);
  final entries = <(int, int, InputEntry)>[]; // (time, order, entry)
  var order = 0;
  void at(int t, InputEntry e) => entries.add((t, order++, e));
  final frameUs = (1e6 / model.frameHz).round();
  var start = 100000;
  final strokes = <List<MouseEvent>>[];
  for (final (i, path) in paths.indexed) {
    final events = _poll(path, model, speed, rng, start);
    strokes.add(events);
    final pointer = i + 1;
    PointerEntry pe(int t, PointerType type, MouseEvent e) => PointerEntry(
      t,
      type: type,
      kind: kind,
      pointer: pointer,
      device: 0,
      timeStampUs: e.timeUs,
      position: e.position,
      localPosition: e.position,
      pressure: type == PointerType.up ? 0 : (kind == PointerDeviceKind.mouse ? 1 : 0.5),
      buttons: type == PointerType.up ? 0 : 1,
    );
    at(events.first.timeUs + 1000, pe(0, PointerType.down, events.first));
    final moves = events.sublist(1);
    var k = 0;
    while (k < moves.length) {
      final arrival = moves[k].timeUs + 1000;
      if (model.delivery == Delivery.raw) {
        at(arrival, pe(0, PointerType.move, moves[k++]));
        continue;
      }
      final frame = (arrival / frameUs).ceil() * frameUs;
      final batch = <MouseEvent>[];
      while (k < moves.length && moves[k].timeUs + 1000 <= frame) {
        batch.add(moves[k++]);
      }
      final sent = model.delivery == Delivery.batched ? batch : [batch.last];
      for (final e in sent) {
        at(frame, pe(0, PointerType.move, e));
      }
    }
    final up = events.last;
    at(
      up.timeUs + 1000 + (model.delivery == Delivery.raw ? 0 : frameUs),
      pe(0, PointerType.up, up),
    );
    start = up.timeUs + 300000;
  }
  entries.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  final out = <InputEntry>[];
  var nextFrame = frameUs;
  for (final (t, _, e) in entries) {
    while (t > nextFrame) {
      out.add(FrameEntry(nextFrame, vsyncUs: nextFrame));
      nextFrame += frameUs;
    }
    out.add(switch (e) {
      final PointerEntry p => PointerEntry(
        t,
        type: p.type,
        kind: p.kind,
        pointer: p.pointer,
        device: p.device,
        timeStampUs: p.timeStampUs,
        position: p.position,
        localPosition: p.localPosition,
        pressure: p.pressure,
        buttons: p.buttons,
      ),
      _ => e,
    });
  }
  for (var i = 0; i < 3; i++) {
    out.add(FrameEntry(nextFrame, vsyncUs: nextFrame));
    nextFrame += frameUs;
  }
  final meta = RecordingMeta(
    platform: 'sim-mouse',
    devicePixelRatio: 1,
    viewSize: view,
    viewScale: zoom,
    pen: pen,
    stylusOnly: false,
  );
  return (recording: InputRecording(meta: meta, entries: out), events: strokes);
}

/// The events a mouse polled at [model]'s rate sends while the hand moves
/// along [path] at [speed] px/s, starting at [startUs]: whole pixels, and
/// none while the pixel does not change.
List<MouseEvent> _poll(
  TruePath path,
  MouseModel model,
  double speed,
  math.Random rng,
  int startUs,
) {
  final length = path.length;
  // Constant speed with smooth 15 % ramps: the ramps cover 2 × 0.15 of the
  // time at half speed on average.
  final duration = length / speed / 0.85;
  double along(double t) {
    final u = (t / duration).clamp(0.0, 1.0);
    const r = 0.15;
    // Speed profile: smoothstep up over [0, r], 1, smoothstep down.
    double integral(double x) {
      // ∫ smoothstep(x / r) dx over [0, x] for x ≤ r.
      final v = x / r;
      return r * (v * v * v - v * v * v * v / 2);
    }

    final full = integral(r); // r / 2
    final total = 2 * full + (1 - 2 * r);
    double s;
    if (u < r) {
      s = integral(u);
    } else if (u <= 1 - r) {
      s = full + (u - r);
    } else {
      s = total - integral(1 - u);
    }
    return length * s / total;
  }

  Offset q(Offset p) => model.quantum == 0
      ? p
      : Offset(
          (p.dx / model.quantum).roundToDouble() * model.quantum,
          (p.dy / model.quantum).roundToDouble() * model.quantum,
        );
  final events = [MouseEvent(startUs, q(path.at(0)))];
  var t = 0.0;
  final dt = 1 / model.hz;
  while (t < duration) {
    t += dt * (1 + model.jitter * (2 * rng.nextDouble() - 1));
    final p = q(path.at(along(math.min(t, duration))));
    if (p == events.last.position) continue;
    events.add(MouseEvent(startUs + (t * 1e6).round(), p));
  }
  return events;
}

/// The pen the owner wrote with: thick, red.
const PenSettings ownerPen = PenSettings(color: 0xFFDC2626, width: 4, streamline: 0);

/// [width] and [streamline] on [ownerPen].
PenSettings penOf(double width, double streamline) =>
    ownerPen.copyWith(width: width, streamline: streamline);

/// The tool of [pen] (for typing convenience).
InkTool toolOf(PenSettings pen) => pen.tool;
