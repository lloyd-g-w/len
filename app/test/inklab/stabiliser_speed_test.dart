// The stabiliser's string (`PenStabiliser`, docs/ARCHITECTURE.md,
// *Stabiliser*): replayed through the real input pipeline and on its own,
// the ink must never trail the pen by more than the string's length, trail
// by exactly that when the pen moves steadily, slow or fast (the owner:
// the stabilisation must hold when writing fast), ignore jitter within the
// string, give the same line at 120, 240 and 1000 Hz, and hand over at
// pen-up without a jump, ending where the pen lifted. The slow, shaky side
// is `stabiliser_test.dart`.
//
// Before (PR #7, a speed-adaptive time filter): the trail fell from ≈ 8 px
// at 40 px/s to under 1 px above 1500 px/s at 100 %, so fast writing was
// barely stabilised.
//
// Print the table with --dart-define=INKLAB_TABLE=true.
@Tags(['inklab'])
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/pen_stabiliser.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import '../support/real_ink.dart';
import 'metrics/polyline_index.dart';
import 'metrics/stabiliser_metrics.dart';
import 'sim/cases.dart';
import 'sim/digitiser.dart';
import 'sim/pen_motion.dart';

const bool _print = bool.fromEnvironment('INKLAB_TABLE');

const Offset _o = Offset(60, 160);

/// Fast cursive: 22 px x-height, 7 letters a second (median 470 px/s,
/// p90 1100: as fast as the real recordings' handwriting).
final PenMotion fastCursive = cursive(
  _o,
  [letterE, letterL, letterU, letterE, letterL, letterL, letterU, letterE],
  xHeight: 22,
  letterWidth: 18,
  lettersPerSecond: 7,
);

/// Sharp 40 px reversals in 70 ms each (cusps, the pen stops at each tip).
final PenMotion fastZigzag = zigzag(_o, count: 8, height: 40, pitch: 14, seconds: 0.07);

/// Six 7 px loops at 6 a second.
final PenMotion fastLoops = loops(_o);

typedef _Run = ({ReplayResult replay, StabiliserLag lag, List<Offset> truth, List<Offset> cusps});

_Run _run(PenMotion motion, double stabiliser, {double hz = 240}) {
  final pen = defaultPen.copyWith(streamline: stabiliser);
  final c = SimCase('fast', '', [
    SimContact(motion, start: 0),
  ], model: DigitiserModel(sampleHz: hz));
  final rec = c.record(pen);
  final replay = ReplayResult.run(rec.recording, pen: pen);
  return (
    replay: replay,
    lag: StabiliserLag.of(replay, rec.recording),
    truth: rec.truth.single.path,
    cusps: rec.truth.single.cusps,
  );
}

/// The committed centre line of [r]'s stroke (screen px).
List<Offset> _line(ReplayResult r) {
  final s = r.strokes.single;
  final c = StrokeOutline.centerline(s.points, StrokeRenderer.specFor(r.pen.width, s.style))!;
  final toScreen = r.screenOf(s);
  return [for (var i = 0; i < c.length; i++) toScreen(c.x[i], c.y[i])];
}

/// The largest distance between [a] and [b], both ways, away from their
/// ends (the digitiser's last sample and the lift fall differently at each
/// rate: ≈ 0.9 px there without the stabiliser).
double _hausdorff(List<Offset> a, List<Offset> b) {
  double oneWay(List<Offset> from, List<Offset> to) {
    final index = PolylineIndex(to, cell: 3);
    var worst = 0.0;
    for (final p in _inner(from, 3)) {
      worst = math.max(worst, index.distance(p));
    }
    return worst;
  }

  return math.max(oneWay(a, b), oneWay(b, a));
}

/// [line] less [trim] px of length at each end.
List<Offset> _inner(List<Offset> line, double trim) {
  final along = [0.0];
  for (var i = 1; i < line.length; i++) {
    along.add(along.last + (line[i] - line[i - 1]).distance);
  }
  return [
    for (var i = 0; i < line.length; i++)
      if (along[i] >= trim && along.last - along[i] >= trim) line[i],
  ];
}

void _log(String line) {
  // ignore: avoid_print
  if (_print) print(line);
}

void main() {
  const settings = [0.3, 0.6, 1.0];

  group('fast synthetic writing', () {
    for (final s in settings) {
      test('at $s the ink trails the pen by the string, fast as slowly', () {
        final r = StabiliserParams.radiusAt(s);
        final c = _run(fastCursive, s), z = _run(fastZigzag, s), l = _run(fastLoops, s);
        final ce = shapeError(c.replay, [c.truth]);
        _log(
          'stabiliser $s (R ${r.toStringAsFixed(1)} px): cursive trail p50 '
          '${c.lag.pxAt(.5).toStringAsFixed(2)} p95 ${c.lag.pxAt(.95).toStringAsFixed(2)} px, '
          'above 1000 px/s p50 ${c.lag.pxAt(.5, minSpeed: 1000).toStringAsFixed(2)}, lift adds '
          '${c.lag.liftTail.single.toStringAsFixed(2)} px from ${c.lag.liftGap.single.toStringAsFixed(2)} '
          'px away, off the pen path '
          '${ce.hausdorff.toStringAsFixed(2)} | zigzag trail p95 '
          '${z.lag.pxAt(.95).toStringAsFixed(2)} | loops trail p95 '
          '${l.lag.pxAt(.95).toStringAsFixed(2)}',
        );
        // Live ink ends at most a string (plus the outline's provisional
        // end and the frame's newest samples, ≈ 3 px) behind the pen …
        for (final (what, run) in [('cursive', c), ('zigzag', z), ('loops', l)]) {
          expect(run.lag.pxAt(.95), lessThan(r + 3.5), reason: '$what trail');
        }
        // … and fast writing is held back as much as slow: the trail
        // above 1000 px/s is the string's length.
        expect(c.lag.pxAt(.5, minSpeed: 1000), greaterThan(0.8 * r), reason: 'held when fast');
        // At the lift the ink catches up from at most a string away (the
        // catch-up follows the pen's path, so its length can be more: the
        // ink cut the corners the pen went round).
        expect(c.lag.liftGap.single, lessThan(r + 3.5), reason: 'cursive lift');
      });
    }
  });

  test('the real S Pen recordings: the trail is the string at any speed', () {
    for (final name in realRecordings) {
      final rec = loadRecording(name);
      for (final s in settings) {
        final r = StabiliserParams.radiusAt(s);
        final pen = rec.meta.pen.copyWith(streamline: s);
        final lag = StabiliserLag.of(ReplayResult.run(rec, pen: pen), rec);
        final slow = lag.pxAt(.5, maxSpeed: 300), fast = lag.pxAt(.5, minSpeed: 1000);
        _log(
          '$name at $s (R ${r.toStringAsFixed(1)}): trail p50 below 300 px/s '
          '${slow.toStringAsFixed(2)}, above 1000 px/s ${fast.toStringAsFixed(2)}, p95 '
          '${lag.pxAt(.95).toStringAsFixed(2)} px',
        );
        expect(lag.pxAt(.95), lessThan(r + 3.5), reason: '$name at $s');
        // Writing fast keeps the stabilisation (the filter it replaced
        // trailed 0.3–1.2 px there).
        expect(fast, greaterThan(0.75 * r), reason: '$name at $s');
      }
    }
  });

  test('the line does not depend on the sample rate (120, 240, 1000 Hz)', () {
    for (final s in [0.0, 0.6, 1.0]) {
      for (final (name, motion) in [
        ('cursive', fastCursive),
        ('zigzag', fastZigzag),
        ('loops', fastLoops),
      ]) {
        final at240 = _line(_run(motion, s).replay);
        for (final hz in [120.0, 1000.0]) {
          final d = _hausdorff(_line(_run(motion, s, hz: hz).replay), at240);
          _log('$name at $s: ${hz.round()} Hz vs 240 Hz ${d.toStringAsFixed(2)} px');
          // The digitiser's jitter differs between runs, and so do the
          // samples: up to 0.5 px without the stabiliser (the catch-up at
          // the lift follows the pen's own samples).
          expect(d, lessThan(0.75), reason: '$name at $s, $hz Hz');
        }
      }
    }
  });

  test('no jump at pen-up: the committed line continues the last live frame', () {
    double? atZero;
    for (final s in [0.0, ...settings]) {
      final r = _run(fastCursive, s).replay;
      final stroke = r.strokes.single;
      final spec = StrokeRenderer.specFor(r.pen.width, stroke.style);
      final last = r.frames.lastWhere((f) => f.drawing);
      // Live and committed ink are drawn from the same points.
      expect(stroke.points.take(last.points.length - 3), last.points.take(last.points.length - 3));
      final live = StrokeOutline.centerline(last.points, spec, complete: false)!;
      final committed = StrokeOutline.centerline(stroke.points, spec)!;
      // The line the last frame drew is the committed one but for its tip
      // (the outline's provisional end, a few px).
      var worst = 0.0, along = 0.0;
      for (var i = live.live - 1; i > 0; i--) {
        along += (Offset(live.x[i], live.y[i]) - Offset(live.x[i - 1], live.y[i - 1])).distance;
        if (along < 6) continue;
        final d = (Offset(live.x[i], live.y[i]) - Offset(committed.x[i], committed.y[i])).distance;
        worst = math.max(worst, d);
      }
      expect(worst, lessThan(1e-9), reason: 'at $s');
      // The stroke ends where the pen lifted.
      final end = r.screenOf(stroke)(stroke.points.last.x, stroke.points.last.y);
      final lift = rawContacts(_run(fastCursive, s).replay.recording).single.samples.last;
      _log('at $s the stroke ends ${(end - lift.position).distance} px from the lift');
      // (As close as without the stabiliser: the input's own end, ≈ 0.4 px.)
      final off = (end - lift.position).distance;
      atZero ??= off;
      expect(off, lessThan(atZero + 0.05), reason: 'end at $s');
    }
  });

  group('PenStabiliser', () {
    final params = StabiliserParams.of(1)!;
    const r = StabiliserParams.maxRadius;

    test('the slider: off at 0, 3 px at 30 %, 80 px at 100 %, on a power curve', () {
      expect(StabiliserParams.of(0), isNull);
      expect(StabiliserParams.radiusAt(0.3), closeTo(3, 1e-9));
      expect(StabiliserParams.radiusAt(0.6), closeTo(19.9, 0.1));
      expect(params.radius, closeTo(80, 1e-9));
      // Today's (PR #7) largest trail at 100 % was ≈ 10 px: 8×.
      expect(params.radius, 8 * 10);
      var last = 0.0;
      for (var i = 1; i <= 100; i++) {
        final x = StabiliserParams.radiusAt(i / 100);
        expect(x, greaterThan(last));
        last = x;
      }
      // Zoom scales the string with the rest (screen px × scale).
      expect(StabiliserParams.of(0.3, scale: 2)!.radius, closeTo(6, 1e-9));
    });

    /// A steady pen along x at [speed] px/s for [seconds], sampled at [hz]:
    /// the largest gap and the last.
    ({double most, double last}) steady(double speed, double hz, {double seconds = 1}) {
      final s = PenStabiliser(params)..begin(Offset.zero);
      var most = 0.0;
      for (var i = 1; i <= seconds * hz; i++) {
        s.add(Offset(speed * i / hz, 0));
        most = math.max(most, s.gap);
      }
      return (most: most, last: s.gap);
    }

    test('a steady pen: the gap is the string at any speed, never more', () {
      for (final speed in [30.0, 300.0, 3000.0]) {
        for (final hz in [120.0, 240.0, 1000.0]) {
          final g = steady(speed, hz, seconds: 6 * r / speed);
          _log('steady $speed px/s at $hz Hz: gap ${g.last} (most ${g.most})');
          expect(g.most, lessThanOrEqualTo(r + 1e-9), reason: '$speed px/s, $hz Hz');
          expect(g.last, closeTo(r, 1e-6), reason: '$speed px/s, $hz Hz');
        }
      }
    });

    test('the gap never exceeds the string while writing, slow or fast', () {
      for (final s in settings) {
        final p = StabiliserParams.of(s)!;
        for (final (motion, slowdown) in [
          (fastCursive, 1.0),
          (fastCursive, 8.0),
          (fastZigzag, 1.0),
        ]) {
          final st = PenStabiliser(p)..begin(motion.at(0));
          final n = (motion.duration * slowdown * 240).round();
          for (var i = 1; i <= n; i++) {
            st.add(motion.at(i / n * motion.duration));
            expect(st.gap, lessThanOrEqualTo(p.radius + 1e-9), reason: 'at $s');
          }
        }
      }
    });

    test('jitter within the string does not move the ink', () {
      final s = PenStabiliser(params)..begin(Offset.zero);
      for (var x = 1; x <= 400; x++) {
        s.add(Offset(x.toDouble(), 0));
      }
      final ink = s.ink;
      final random = math.Random(3);
      for (var i = 0; i < 2000; i++) {
        // Anywhere within the string of the ink (the pen rests and shakes).
        final a = random.nextDouble() * 2 * math.pi, d = random.nextDouble() * 0.99 * r;
        s.add(ink + Offset(math.cos(a), math.sin(a)) * d);
        expect(s.ink, ink);
      }
    });

    test('the path does not depend on how often the pen is sampled', () {
      // A curve sampled at 120 Hz and 2 kHz: the same ink.
      Offset at(double t) => Offset(300 * t, 60 * math.sin(6 * t));
      List<Offset> run(int n) {
        final s = PenStabiliser(params)..begin(at(0));
        return [for (var i = 1; i <= n; i++) s.add(at(i / n))];
      }

      final coarse = run(120), fine = run(2000);
      final index = PolylineIndex(fine, cell: 3);
      var worst = 0.0;
      for (final p in coarse) {
        worst = math.max(worst, index.distance(p));
      }
      _log('120 Hz vs 2 kHz: ${worst.toStringAsFixed(3)} px');
      expect(worst, lessThan(0.1));
    });

    test('the ink catches up with the pen along its path', () {
      final s = PenStabiliser(params)..begin(Offset.zero);
      // A slow quarter circle (radius 120 px).
      for (var t = 1; t <= 1000; t++) {
        final a = t / 1000 * math.pi / 2;
        s.add(Offset(120 - 120 * math.cos(a), 120 * math.sin(a)));
      }
      final before = s.ink;
      final pen = s.pen;
      expect(s.gap, closeTo(r, 1e-6));
      final rest = s.catchUp();
      expect(rest.last, pen);
      // It starts at the ink, not at the pen, …
      expect((rest.first - before).distance, lessThan(2));
      for (var i = 1; i < rest.length; i++) {
        expect((rest[i] - rest[i - 1]).distance, lessThan(2), reason: 'no jump');
      }
      expect(s.ink, pen);
      // … along the arc, not across it: the ink's own offset inside the
      // arc fades out (a straight line to the pen would be 7 px inside).
      double off(Offset p) => ((p - const Offset(120, 0)).distance - 120).abs();
      for (final p in rest) {
        expect(off(p), lessThanOrEqualTo(1.01 * off(before)));
      }
      expect(off(rest[rest.length ~/ 2]), lessThan(0.6 * off(before)));
    });
  });
}
