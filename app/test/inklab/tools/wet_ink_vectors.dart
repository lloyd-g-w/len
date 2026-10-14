// Test vectors of the wet-ink model (`WetInkModel`) for the Kotlin port in
// `android/.../WetInkModel.kt`: a replay's raw samples fed to the model, the
// overlay's tail queried after them, and the model's answers.

import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/lab/wet_ink_model.dart';
import 'package:len/ink/render/flat_ends.dart';
import 'package:len/ink/render/stroke_renderer.dart';

/// Events (`S` radii, `H` shape, `B` a new contact, `A` sample, `Q`
/// query; after every [queryEvery]th sample and the last) and the model's
/// answer to each query (tail start, then the ends — 1: flat start, 2: flat
/// end —, the cuts at flat ends (how many, then each one's piece and line:
/// point and normal), the flat nib sweeps (how many, then each one's piece
/// and its two cross-sections: centre, left and right end) and the (x, y,
/// r) triples drawn). [maxContacts] limits the
/// contacts used; [ends] replaces the pen's end style (the end taper is the
/// one a committed stroke carries, `WetInkModel.commit`).
(String, String) wetInkVectors(
  InputRecording recording, {
  int queryEvery = 1,
  int? maxContacts,
  StrokeStyle Function(StrokeStyle)? ends,
}) {
  final r = ReplayResult.run(recording);
  final dpr = recording.meta.devicePixelRatio;
  // An unusual zoom and unit, so scaling mistakes show.
  final style = (ends ?? (s) => s)(r.style.copyWith(unit: 0.9));
  final wet = WetInkStyle.forPen(r.pen.tool, r.pen.width, style, color: 0xFF000000, scale: 1.3)!;
  final taperEnd = StrokeRenderer.specFor(r.pen.width, style).taperEnd * 1.3 * dpr;
  final radii = [for (final x in wet.radii) x * dpr];
  final shape = wet.shape.scaled(dpr);
  final ev = StringBuffer()
    ..writeln('S ${radii.join(' ')}')
    ..writeln('H ${shape.toList().join(' ')}');
  final out = StringBuffer();
  var contact = 0;
  for (final c in rawContacts(recording)) {
    if (c.samples.isEmpty) continue;
    if (maxContacts != null && contact >= maxContacts) break;
    ev.writeln('B');
    final m = WetInkModel(radii: radii, shape: shape, frameMs: 8.3);
    for (var i = 0; i < c.samples.length; i++) {
      final s = c.samples[i];
      final lift = i == c.samples.length - 1;
      final p = s.position * dpr;
      final t = s.timeUs ~/ 1000;
      ev.writeln('A ${p.dx} ${p.dy} ${s.pressure} $t ${lift ? 1 : 0}');
      m.add(p, s.pressure, t, lift: lift);
      if (m.samples.isEmpty || (i % queryEvery != 0 && !lift)) continue;
      final shown = i >= 6 ? c.samples[i - 6].timeUs ~/ 1000 : 0;
      final now = t + 1.0;
      // Every other contact ends just within the tail's last frames.
      final ended = lift && contact.isEven ? now - 9 : -1.0;
      ev.writeln('Q $now $shown $ended $taperEnd');
      if (ended >= 0) m.commit(taperEnd: taperEnd);
      final from = m.tailStart(
        nowMs: now,
        shownUpToMs: shown.toDouble(),
        endedAtMs: ended < 0 ? null : ended,
      );
      out.write('$from');
      if (from < m.samples.length) {
        final segments = m.segments(from, m.samples.length);
        final first = segments.first;
        final flags = (first.flatA ? 1 : 0) + (segments.last.flatB ? 2 : 0);
        out.write(' $flags');
        // The cuts at flat ends: how many, then each one's piece and line.
        final cuts = [
          for (var k = 0; k < segments.length; k++)
            for (final l in segments[k].cuts) '$k ${l.px} ${l.py} ${l.nx} ${l.ny}',
        ];
        out.write(' ${cuts.length}');
        for (final c in cuts) {
          out.write(' $c');
        }
        // The flat nib sweeps: how many, then each one's piece and sections.
        String section(CrossSection c) => '${c.cx} ${c.cy} ${c.lx} ${c.ly} ${c.rx} ${c.ry}';
        final sweeps = [
          for (var k = 0; k < segments.length; k++)
            for (final (a, b) in segments[k].sweeps) '$k ${section(a)} ${section(b)}',
        ];
        out.write(' ${sweeps.length}');
        for (final w in sweeps) {
          out.write(' $w');
        }
        out.write(' ${first.a.dx} ${first.a.dy} ${first.ra}');
        if (first.a != first.b || segments.length > 1) {
          for (final g in segments) {
            out.write(' ${g.b.dx} ${g.b.dy} ${g.rb}');
          }
        }
      }
      out.writeln();
    }
    contact++;
  }
  return (ev.toString(), out.toString());
}

/// The end styles the vectors are written for (name suffix → style).
final Map<String, StrokeStyle Function(StrokeStyle)?> endVariants = {
  '': null,
  '_flat': (s) => s.copyWith(ends: StrokeEnds.flat),
  '_tapered': (s) => s.copyWith(ends: StrokeEnds.tapered, taperStart: 3, taperEnd: 5),
};
