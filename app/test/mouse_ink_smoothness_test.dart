// Mouse handwriting through the real input pipeline (whole-pixel events at
// 1000 and 125 Hz, slow and fast, several widths and zooms), measured
// against the path the hand made (`support/ink_roughness.dart`): no bumps
// or stair-steps at stabiliser 0, smoother at 30 %, a steady width, ink
// reaching the mouse at 0 and trailing it no more than the stabiliser
// costs. A stylus is left alone. `mouse_ink_golden_test.dart` shows it.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/mouse_smoother.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/shapes/polyline.dart';

import 'support/ink_roughness.dart';
import 'support/mouse_writing.dart';

/// Every combination measured (at [stabiliser]), worst of each measure.
({Roughness formula, Roughness lines, double lag}) _worst(double stabiliser) {
  final formula = Roughness(), lines = Roughness();
  var lag = 0.0;
  void worst(Roughness into, Roughness r) {
    into
      ..bump2 = math.max(into.bump2, r.bump2)
      ..wave6 = math.max(into.wave6, r.wave6)
      ..kink = math.max(into.kink, r.kink)
      ..widthRange = math.max(into.widthRange, r.widthRange)
      ..drift = math.max(into.drift, r.drift)
      ..cusp = math.max(into.cusp, r.cusp);
  }

  for (final speed in [150.0, 600.0]) {
    for (final model in const [MouseModel(hz: 1000), MouseModel(hz: 125)]) {
      for (final (zoom, width) in const [(1.0, 1.5), (1.0, 4.0), (0.25, 2.5), (2.0, 2.5)]) {
        final pen = penOf(width, stabiliser);
        for (final (paths, into, straight) in [
          (ownerFormula(), formula, false),
          (straightLines(), lines, true),
        ]) {
          final rec = mouseRecording(paths, model: model, speed: speed, pen: pen, zoom: zoom);
          final replay = ReplayResult.run(rec.recording);
          worst(into, roughnessOf(replay, paths, zoom: zoom, straight: straight));
          lag = math.max(lag, lagOf(replay, rec.events, zoom: zoom).median);
        }
      }
    }
  }
  return (formula: formula, lines: lines, lag: lag);
}

void main() {
  test('stabiliser 0: no bumps or stair-steps, a steady width, ink at the mouse', () {
    final w = _worst(0);
    final reason = 'formula ${w.formula}\nlines ${w.lines}\nlag ${w.lag}';
    // Before: bumps up to 0.35 px, kinks up to 60°, the width swelling and
    // pinching by up to 32 % along straight lines.
    expect(w.formula.bump2, lessThan(0.05), reason: reason);
    expect(w.formula.kink, lessThan(8), reason: reason);
    expect(w.lines.kink, lessThan(2.5), reason: reason);
    expect(w.lines.wave6, lessThan(0.12), reason: reason);
    expect(w.lines.widthRange, lessThan(4), reason: reason);
    // Not distorted: near the path the hand made, cusps kept.
    expect(w.formula.drift, lessThan(2.2), reason: reason);
    expect(w.formula.cusp, lessThan(4), reason: reason);
    // The provisional tip reaches the mouse.
    expect(w.lag, lessThan(1), reason: reason);
  });

  test('stabiliser 30 %: smoother still, trailing the mouse ~11 px', () {
    final w = _worst(0.3);
    final reason = 'formula ${w.formula}\nlines ${w.lines}\nlag ${w.lag}';
    // Before: kinks up to 12°, the width off by up to 8 %, 13–33 px of lag.
    expect(w.formula.bump2, lessThan(0.03), reason: reason);
    expect(w.formula.kink, lessThan(4), reason: reason);
    expect(w.lines.kink, lessThan(0.8), reason: reason);
    expect(w.lines.wave6, lessThan(0.05), reason: reason);
    expect(w.lines.widthRange, lessThan(2), reason: reason);
    expect(w.formula.drift, lessThan(2.5), reason: reason);
    expect(w.formula.cusp, lessThan(4.5), reason: reason);
    expect(w.lag, lessThan(MouseSmoother.lagOf(MouseSmoother.sigmaFor(0.3)) + 1), reason: reason);
  });

  test('a stylus is not smoothed by the mouse\'s smoother: its points, its stabiliser', () {
    final paths = straightLines(angles: const [3, 30]);
    for (final stabiliser in [0.0, 0.3]) {
      final rec = mouseRecording(
        paths,
        model: const MouseModel(hz: 240),
        speed: 300,
        pen: penOf(2.5, stabiliser),
        kind: PointerDeviceKind.stylus,
      );
      final replay = ReplayResult.run(rec.recording);
      expect(replay.frames.every((f) => f.tip.isEmpty), isTrue);
      expect(replay.strokes, hasLength(paths.length));
      for (final (k, s) in replay.strokes.indexed) {
        // The pen's stabiliser is applied to its points (`PenStabiliser`).
        expect(s.style.streamline, 0);
        final events = [for (final e in rec.events[k]) e.position];
        for (final p in s.points) {
          if (stabiliser == 0) {
            expect(events, contains(Offset(p.x, p.y)), reason: 'an event\'s position');
          } else {
            // Held back along the line of whole-pixel steps, never further
            // off it than a step's corner.
            final d = [
              for (var i = 1; i < events.length; i++)
                Polyline.distanceToSegment(Offset(p.x, p.y), events[i - 1], events[i]),
            ].reduce(math.min);
            expect(d, lessThan(0.5), reason: 'on the line');
          }
        }
      }
    }
  });

  test('a mouse stroke is committed with its stabiliser applied on the screen', () {
    final rec = mouseRecording(
      straightLines(angles: const [10]),
      model: const MouseModel(hz: 1000),
      speed: 300,
      pen: penOf(2.5, 0.3),
    );
    final replay = ReplayResult.run(rec.recording);
    expect(replay.strokes.single.style.streamline, 0);
    // The tip shows only with the stabiliser off.
    expect(replay.frames.every((f) => f.tip.isEmpty), isTrue);
  });
}
