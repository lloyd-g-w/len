// The stabiliser when writing fast (`PenStabiliser`, docs/ARCHITECTURE.md,
// *Stabiliser*): replayed through the real input pipeline, the ink must
// keep up with a fast pen (a small trail in px, whatever the sample
// rate), keep fast cursive's loops and cusps, give the same line at 120,
// 240 and 1000 Hz, and hand over at pen-up without a jump. The slow,
// shaky side is `stabiliser_test.dart`.
//
// Before (a centred smoothing of the line with live ink showing only its
// final part), at the pen's default 30 %: the ink trailed the pen by
// 16 px (median; 19 px above 1000 px/s, 22 px p95) on the real S Pen
// recordings and the lift added 17–23 px at once (up to 52); at 100 %
// 28 px and 30 px, and fast cursive's loops shrank by 2.5 px.
//
// Print the table with --dart-define=INKLAB_TABLE=true.
@Tags(['inklab'])
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/pen_stabiliser.dart';
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
      test('at $s the ink keeps up and keeps the shape', () {
        final c = _run(fastCursive, s), z = _run(fastZigzag, s), l = _run(fastLoops, s);
        final ce = shapeError(c.replay, [c.truth]);
        final ze = shapeError(z.replay, [z.truth], cusps: [z.cusps]);
        final le = shapeError(l.replay, [l.truth]);
        _log(
          'stabiliser $s: cursive trail p50 ${c.lag.pxAt(.5).toStringAsFixed(2)} '
          'p95 ${c.lag.pxAt(.95).toStringAsFixed(2)} px, lift adds '
          '${c.lag.liftTail.single.toStringAsFixed(2)} px, shape ${ce.hausdorff.toStringAsFixed(2)}'
          ' | zigzag trail p95 ${z.lag.pxAt(.95).toStringAsFixed(2)}, cusp '
          '${ze.cusp.toStringAsFixed(2)} | loops trail p95 ${l.lag.pxAt(.95).toStringAsFixed(2)}, '
          'shape ${le.hausdorff.toStringAsFixed(2)}',
        );
        // A small trail at speed (it was 11–27 px) …
        expect(c.lag.pxAt(.95), lessThan(3.5), reason: 'cursive trail');
        expect(z.lag.pxAt(.95), lessThan(2.5), reason: 'zigzag trail');
        expect(l.lag.pxAt(.95), lessThan(4.5), reason: 'loops trail');
        // … and little left to add at the lift (it was 13–23 px).
        expect(c.lag.liftTail.single, lessThan(6), reason: 'cursive lift');
        // Loops and cusps kept (the old stabiliser shrank these loops by
        // 2.5 px at 100 %).
        expect(ce.hausdorff, lessThan(1.0), reason: 'cursive shape');
        expect(ze.cusp, lessThan(0.6), reason: 'zigzag cusps');
        expect(le.hausdorff, lessThan(1.8), reason: 'loops shape');
      });
    }
  });

  test('the real S Pen recordings: the ink keeps up with fast writing', () {
    for (final name in realRecordings) {
      final rec = loadRecording(name);
      for (final s in settings) {
        final pen = rec.meta.pen.copyWith(streamline: s);
        final lag = StabiliserLag.of(ReplayResult.run(rec, pen: pen), rec);
        final fast = lag.pxAt(.95, minSpeed: 1000);
        final lift = StabiliserLag.quantile(lag.liftTail, .5);
        _log(
          '$name at $s: trail p50 ${lag.pxAt(.5).toStringAsFixed(2)}, above 1000 px/s p95 '
          '${fast.toStringAsFixed(2)} px; lift adds p50 ${lift.toStringAsFixed(2)} px',
        );
        // Was 19–36 px.
        expect(fast, lessThan(1.5), reason: '$name at $s');
        expect(lag.pxAt(.5), lessThan(1.5), reason: '$name at $s');
        // Was 17–32 px (median).
        expect(lift, lessThan(5.5), reason: '$name at $s');
      }
    }
  });

  test('the line does not depend on the sample rate (120, 240, 1000 Hz)', () {
    for (final s in [0.6, 1.0]) {
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
          // samples: ≈ 0.3 px without the stabiliser.
          expect(d, lessThan(0.5), reason: '$name at $s, $hz Hz');
        }
      }
    }
  });

  test('no jump at pen-up: the committed line continues the last live frame', () {
    for (final s in settings) {
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
    }
  });

  group('PenStabiliser', () {
    final params = StabiliserParams.of(1)!;

    test('off at 0; time constant at rest grows with the setting', () {
      expect(StabiliserParams.of(0), isNull);
      expect(StabiliserParams.of(0.3)!.restTau, closeTo(0.12, 1e-9));
      expect(params.restTau, closeTo(StabiliserParams.maxRestTau, 1e-9));
    });

    test('a steady pen: the trail falls as the pen speeds up', () {
      double trail(double speed) {
        final s = PenStabiliser(params)..begin(Offset.zero, 0);
        for (var t = 1; t <= 600; t++) {
          s.add(Offset(speed * t / 1000, 0), t);
        }
        return s.gap;
      }

      final slow = trail(40), medium = trail(300), fast = trail(1500);
      _log('trail at 40 / 300 / 1500 px/s: $slow / $medium / $fast');
      expect(slow, greaterThan(3)); // The string shows.
      expect(medium, lessThan(slow));
      expect(fast, lessThan(1)); // Fast writing is not held back.
    });

    test('the ink catches up with the pen along its path', () {
      final s = PenStabiliser(params)..begin(Offset.zero, 0);
      // A slow quarter circle (radius 30 px in 1 s).
      for (var t = 1; t <= 1000; t++) {
        final a = t / 1000 * math.pi / 2;
        s.add(Offset(30 - 30 * math.cos(a), 30 * math.sin(a)), t);
      }
      final before = s.ink;
      final pen = s.pen;
      final gap = s.gap;
      expect(gap, greaterThan(3));
      final rest = s.catchUp();
      expect(rest.last, pen);
      // It starts at the ink, not at the pen.
      expect((rest.first - before).distance, lessThan(0.5 * gap));
      expect(s.ink, pen);
      // Along the arc, not across it: the ink's own offset from the arc
      // (it cuts inside a curve) fades out, never grows.
      double off(Offset p) => ((p - const Offset(30, 0)).distance - 30).abs();
      for (final p in rest) {
        expect(off(p), lessThanOrEqualTo(off(before) + 0.05));
      }
    });
  });
}
