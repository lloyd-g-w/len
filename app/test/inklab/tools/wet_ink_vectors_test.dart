// Writes test vectors of the wet-ink model (`WetInkModel`) for the Kotlin
// port in `android/.../WetInkModel.kt` (opt-in; run by
// tool/wet_ink_check/check.sh, which compares the two):
//
//   flutter test test/inklab/tools/wet_ink_vectors_test.dart \
//     --dart-define=INKLAB_WET_VECTORS=<output dir>
//
// Every simulated case at every stabiliser and every recording, each raw
// sample fed to the model, the overlay's tail queried after each one.
@Tags(['inklab'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/recording_codec.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/lab/wet_ink_model.dart';

import '../sim/cases.dart';
import '../suite.dart';

const String _out = String.fromEnvironment('INKLAB_WET_VECTORS');

void main() {
  test('wet-ink vectors', () {
    final recordings = <String, InputRecording>{
      for (final c in simCases)
        for (final st in stabilisers)
          '${c.name}@$st': c.record(defaultPen.copyWith(streamline: st)).recording,
      for (final f in recordingFiles())
        f.uri.pathSegments.last.replaceAll('.leninput', ''): RecordingCodec.decode(
          f.readAsBytesSync(),
        ),
    };
    Directory(_out).createSync(recursive: true);
    for (final MapEntry(key: name, value: recording) in recordings.entries) {
      final (events, expected) = _vectors(recording);
      File('$_out/$name.ev').writeAsStringSync(events);
      File('$_out/$name.expected').writeAsStringSync(expected);
    }
  }, skip: _out.isEmpty ? 'opt-in: --dart-define=INKLAB_WET_VECTORS=<dir>' : false);
}

/// Events (`S` radii, `H` shape, `B` startMs per contact, `A` sample, `Q`
/// query) and the model's answer to each query (tail start, then the
/// (x, y, r) triples drawn).
(String, String) _vectors(InputRecording recording) {
  final r = ReplayResult.run(recording);
  final dpr = recording.meta.devicePixelRatio;
  // An unusual zoom and unit, so scaling mistakes show.
  final wet = WetInkStyle.forPen(
    r.pen.tool,
    r.pen.width,
    r.style,
    color: 0xFF000000,
    scale: 1.3,
    unit: 0.9,
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
    // Ink starting a little after the first sample (a pen-down hook).
    final startMs = c.samples[c.samples.length > 3 ? 2 : 0].timeUs ~/ 1000;
    ev.writeln('B $startMs');
    final m = WetInkModel(radii: radii, shape: shape, frameMs: 8.3, startMs: startMs);
    for (var i = 0; i < c.samples.length; i++) {
      final s = c.samples[i];
      final lift = i == c.samples.length - 1;
      final p = s.position * dpr;
      final t = s.timeUs ~/ 1000;
      ev.writeln('A ${p.dx} ${p.dy} ${s.pressure} $t ${lift ? 1 : 0}');
      m.add(p, s.pressure, t, lift: lift);
      if (m.samples.isEmpty) continue;
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
