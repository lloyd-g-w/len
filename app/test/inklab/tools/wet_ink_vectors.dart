// Test vectors of the wet-ink model (`WetInkModel`) for the Kotlin port in
// `android/.../WetInkModel.kt`: a replay's raw samples fed to the model, the
// overlay's tail queried after them, and the model's answers.

import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/lab/wet_ink_model.dart';

/// Events (`S` radii, `H` shape, `B` a new contact, `A` sample, `Q`
/// query; after every [queryEvery]th sample and the last) and the model's
/// answer to each query (tail start, then the (x, y, r) triples drawn).
/// [maxContacts] limits the contacts used.
(String, String) wetInkVectors(
  InputRecording recording, {
  int queryEvery = 1,
  int? maxContacts,
}) {
  final r = ReplayResult.run(recording);
  final dpr = recording.meta.devicePixelRatio;
  // An unusual zoom and unit, so scaling mistakes show.
  final wet = WetInkStyle.forPen(
    r.pen.tool,
    r.pen.width,
    r.style.copyWith(unit: 0.9),
    color: 0xFF000000,
    scale: 1.3,
  )!;
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
      ev.writeln('Q $now $shown $ended');
      final from = m.tailStart(
        nowMs: now,
        shownUpToMs: shown.toDouble(),
        endedAtMs: ended < 0 ? null : ended,
      );
      out.write('$from');
      if (from < m.samples.length) {
        final segments = m.segments(from, m.samples.length);
        final first = segments.first;
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
