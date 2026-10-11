import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay_run.dart';

import 'edge_metrics.dart';
import 'metric.dart';
import 'overlay_metrics.dart';
import 'performance_metrics.dart';
import 'shape_metrics.dart';
import 'temporal_metrics.dart';
import 'truth.dart';

/// A recording replayed with one pen setting, and what it should look like.
class Subject {
  Subject(this.name, this.replay, this.truths);

  /// Replays [recording] (with [pen], default: as recorded). Without
  /// [truths], the raw samples of each committed contact stand in.
  ///
  /// With [timed], the replay runs once to warm up first and each live
  /// outline is timed three times (fastest kept), for steadier timings.
  factory Subject.of(
    String name,
    InputRecording recording, {
    List<Truth>? truths,
    PenSettings? pen,
    bool timed = false,
  }) {
    if (timed) ReplayResult.run(recording, pen: pen);
    final replay = ReplayResult.run(recording, pen: pen, timingRepeats: timed ? 3 : 1);
    return Subject(name, replay, truths ?? rawTruths(recording));
  }

  final String name;
  final ReplayResult replay;
  final List<Truth> truths;

  double get streamline => replay.pen.streamline;
}

/// Raw-sample truths for the contacts of [recording] that are not bounces
/// (shorter than 80 ms, starting within 120 ms and 16 px of the last lift).
List<Truth> rawTruths(InputRecording recording) {
  final out = <Truth>[];
  RawContact? previous;
  for (final c in rawContacts(recording)) {
    if (c.cancelled || c.samples.isEmpty) continue;
    final bounce =
        previous != null &&
        c.downUs - previous.upUs < 120000 &&
        c.upUs - c.downUs < 80000 &&
        (c.samples.first.position - previous.samples.last.position).distance < 16;
    if (!bounce) out.add(Truth.ofContact(c));
    previous = c;
  }
  return out;
}

/// Every quality metric of [s] (performance and overlay are separate).
List<Metric> qualityMetrics(Subject s) {
  final pairs = pairStrokes(s.replay, s.truths);
  return [
    ...fidelity(pairs, s.streamline),
    ...detail(pairs, s.streamline),
    ...smoothness(committedLines(s.replay)),
    ...ends(s.replay, pairs, s.truths, s.streamline),
    ...temporal(s.replay),
  ];
}

/// [qualityMetrics] plus performance and the low-latency overlay model.
List<Metric> allMetrics(Subject s) => [
  ...qualityMetrics(s),
  ...performance(s.replay),
  ...overlay(s.replay),
];
