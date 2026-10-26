import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/pen_stabiliser.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/lab_stats.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/recording_codec.dart';
import 'package:len/ink/lab/replay_run.dart';

import 'sim/cases.dart';

SimCase caseNamed(String name) => simCases.firstWhere((c) => c.name == name);

void main() {
  test('a recording survives encoding unchanged', () {
    final r = caseNamed('cursive').record(defaultPen).recording;
    final bytes = RecordingCodec.encode(r);
    final again = RecordingCodec.decode(bytes);
    expect(jsonEncode(RecordingCodec.toJson(again)), utf8.decode(bytes));
    expect(again.entries.length, r.entries.length);
    expect(again.meta.pen.streamline, r.meta.pen.streamline);
    expect(() => RecordingCodec.decode(utf8.encode('{"format":"x"}')), throwsFormatException);
  });

  test('replay is deterministic and commits one stroke per real contact', () {
    final r = caseNamed('bounces').record(defaultPen).recording;
    final a = ReplayResult.run(r), b = ReplayResult.run(r);
    expect(a.strokes, hasLength(2), reason: 'the bounces are filtered out');
    expect(r.contactCount, 4);
    for (var i = 0; i < a.strokes.length; i++) {
      expect(
        [for (final p in a.strokes[i].points) (p.x, p.y, p.pressure)],
        [for (final p in b.strokes[i].points) (p.x, p.y, p.pressure)],
      );
    }
    expect(a.frames.where((f) => f.drawing), isNotEmpty);
  });

  test('historical stylus samples reach the live stroke (dense input)', () {
    final r = caseNamed('pressure_swell').record(defaultPen).recording;
    final raw = rawContacts(r).single.samples;
    expect(raw.length, greaterThan(400), reason: '2 s at 240 Hz');
    final moves = r.pointers.where((p) => p.type == PointerType.move).length;
    expect(moves, lessThan(raw.length ~/ 1.5), reason: 'batched: ~2 samples per event');
    final stroke = ReplayResult.run(r).strokes.single;
    // Every sample arrives; the controller only drops points
    // closer than 0.75 px to the previous one. With the pen's stabiliser
    // on, the samples are where it puts the ink (`PenStabiliser`), and the
    // stroke stops where the ink is.
    final params = StabiliserParams.of(defaultPen.streamline);
    final st = params == null ? null : (PenStabiliser(params)..begin(raw.first.position));
    var spaced = 1;
    var last = raw.first.position;
    for (final s in raw.skip(1)) {
      final at = st?.add(s.position) ?? s.position;
      if ((at - last).distance >= 0.75) {
        spaced++;
        last = at;
      }
    }
    expect(stroke.points.length, closeTo(spaced, spaced * 0.05));
  });

  test('stats report the digitiser rate and samples per frame', () {
    final r = caseNamed('pressure_swell').record(defaultPen).recording;
    final stats = LabStats();
    r.entries.forEach(stats.add);
    expect(stats.sampleHz, closeTo(240, 5));
    expect(stats.samplesPerFrame, closeTo(2, 0.3));
  });
}
