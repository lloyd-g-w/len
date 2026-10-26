// The stabiliser against a shaky hand: a slow, gently bowed line written
// with hand tremor (about ±1 px across the line at 5–9 Hz, plus the
// digitiser's jitter), replayed through the real input pipeline at
// stabiliser 0, 0.5 and 1. For the committed centre line, Flutter's live
// ink (the part each frame draws) and the low-latency overlay's model, it
// measures how far the ink strays from the steady path (the line without
// the tremor, as the stabiliser's string draws it). The stabiliser must visibly remove the tremor, live as well
// as committed, and the overlay must draw the stabilised line.
//
// Print the table with --dart-define=INKLAB_TABLE=true.
@Tags(['inklab'])
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/pen_stabiliser.dart';
import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/lab/wet_ink_model.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'metrics/polyline_index.dart';
import 'metrics/truth.dart';
import 'sim/cases.dart';
import 'sim/digitiser.dart';
import 'sim/pen_motion.dart';

const double _seconds = 4;

const bool _print = bool.fromEnvironment('INKLAB_TABLE');

/// The steady path: 300 px with a 20 px bow, in 4 s (a slow, careful line,
/// where a shaky hand shows most).
Offset _steady(double t) {
  final u = minJerk(t / _seconds);
  return Offset(60 + 300 * u, 200 - 20 * math.sin(math.pi * u));
}

/// The pen: the steady path plus tremor across it.
Offset _shaky(double t) {
  final a = _steady(math.max(0, t - 1e-3)), b = _steady(math.min(_seconds, t + 1e-3));
  final d = b - a;
  final n = d.distance < 1e-9 ? const Offset(0, 1) : Offset(-d.dy, d.dx) / d.distance;
  final wobble = 0.7 * math.sin(2 * math.pi * 8.7 * t) + 0.45 * math.sin(2 * math.pi * 5.3 * t + 1);
  return _steady(t) + n * wobble;
}

/// The shaky line: 4 s, 300 px with a 20 px bow, tremor across it.
final PenMotion shakyLine = PenMotion(duration: _seconds, at: _shaky, pressure: (_) => 0.5);

/// RMS and largest distance of [points] from the steady path.
({double rms, double max}) _stray(Iterable<Offset> points, PolylineIndex steady) {
  var sum = 0.0, worst = 0.0, n = 0;
  for (final p in points) {
    final d = steady.distance(p);
    sum += d * d;
    worst = math.max(worst, d);
    n++;
  }
  return (rms: n == 0 ? 0 : math.sqrt(sum / n), max: worst);
}

/// Stray of the committed centre line, of each live frame's newest 12 px
/// of drawn ink, and of the overlay's newest 12 px, at [streamline].
Map<String, ({double rms, double max})> measure(double streamline) {
  final motion = shakyLine;
  final pen = defaultPen.copyWith(streamline: streamline);
  final recording = SimCase('tremor', 'shaky line', [
    SimContact(motion, start: 0),
  ]).record(pen).recording;
  // The steady path as the stabiliser draws it (its string cuts the bow
  // by up to 6 px at 100 %, on purpose): the tremor is what strays from it.
  final path = [for (var i = 0; i <= 4000; i++) _steady(i / 1000)];
  final steady = PolylineIndex(
    stabilisedTruth(Truth(path: path, pressure: [for (final _ in path) 0.5]), streamline).path,
  );
  final r = ReplayResult.run(recording, pen: pen);
  final stroke = r.strokes.single;
  final spec = StrokeRenderer.specFor(pen.width, stroke.style);
  // Away from the ends (the pen starts and stops there).
  bool inner(Offset p) => p.dx > 75 && p.dx < 345;

  final c = StrokeOutline.centerline(stroke.points, spec)!;
  // The stroke's last string length is the catch-up at the lift, which
  // follows the pen's own path (`PenStabiliser.catchUp`): left out.
  final reach = StabiliserParams.of(streamline)?.radius ?? 0;
  final committed = [for (var i = 0; i < c.length; i++) r.toScreen(c.x[i], c.y[i])]
      .where((p) => inner(p) && p.dx < 355 - reach);

  // The newest [reach] px of a line (screen points, oldest first).
  List<Offset> newest(List<Offset> line, double reach) {
    var back = 0.0, i = line.length - 1;
    while (i > 0 && back < reach) {
      back += (line[i] - line[i - 1]).distance;
      i--;
    }
    return line.sublist(i);
  }

  final live = <Offset>[];
  for (final f in r.frames) {
    if (!f.drawing) continue;
    final line = StrokeOutline.centerline(f.points, spec, complete: false);
    if (line == null) continue;
    final drawn = [for (var i = 0; i < line.live; i++) f.toScreen(line.x[i], line.y[i])];
    live.addAll(newest(drawn, 12).where(inner));
  }

  // The overlay's model, fed every sample (logical px), queried after each.
  final wet = WetInkStyle.forPen(
    pen.tool,
    pen.width,
    stroke.style,
    color: 0xFF000000,
    scale: r.viewScale,
    stabiliser: streamline,
  )!;
  final model = WetInkModel(radii: wet.radii, shape: wet.shape, frameMs: 8.3);
  final overlay = <Offset>[];
  final samples = rawContacts(recording).single.samples;
  for (var i = 0; i < samples.length; i++) {
    final s = samples[i];
    model.add(s.position, s.pressure, s.timeUs ~/ 1000, lift: i == samples.length - 1);
    if (i == samples.length - 1 || model.samples.length < 2) continue;
    final ink = [for (final g in model.segments(0, model.samples.length)) g.b];
    overlay.addAll(newest(ink, 12).where(inner));
  }
  return {
    'committed': _stray(committed, steady),
    'live (newest 12 px)': _stray(live, steady),
    'overlay (newest 12 px)': _stray(overlay, steady),
    'raw samples': _stray([for (final s in samples) s.position].where(inner), steady),
  };
}

void main() {
  final results = {
    for (final s in [0.0, 0.5, 1.0]) s: measure(s),
  };

  test('the stabiliser removes tremor from committed, live and overlay ink', () {
    if (_print) {
      for (final MapEntry(key: s, value: m) in results.entries) {
        for (final MapEntry(key: what, value: v) in m.entries) {
          // ignore: avoid_print
          print(
            'stabiliser $s  ${what.padRight(24)} rms ${v.rms.toStringAsFixed(3)}'
            '  max ${v.max.toStringAsFixed(3)} px',
          );
        }
      }
    }
    final raw = results[0.0]!['raw samples']!.rms;
    for (final what in ['committed', 'live (newest 12 px)', 'overlay (newest 12 px)']) {
      final at0 = results[0.0]![what]!.rms;
      final at05 = results[0.5]![what]!.rms;
      final at1 = results[1.0]![what]!.rms;
      // At 0 the tremor stays (it is the pen's real motion) …
      expect(at0, greaterThan(0.6 * raw), reason: what);
      // … the string takes most of it away (at 50 % 12 px long, at 100 %
      // 80 px: what is left there is not tremor but the long string
      // following a shaky pen's longer path a little differently).
      expect(at05, lessThan(0.3 * at0), reason: what);
      expect(at1, lessThan(0.5 * at0), reason: what);
    }
    // The overlay draws the line Flutter draws.
    for (final s in [0.5, 1.0]) {
      expect(
        results[s]!['overlay (newest 12 px)']!.max,
        lessThan(results[s]!['live (newest 12 px)']!.max + 0.1),
        reason: 'overlay at $s',
      );
    }
  });
}
