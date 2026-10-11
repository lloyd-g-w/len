import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/replay_run.dart';

import 'contacts.dart';
import 'edge_metrics.dart';
import 'metric.dart';
import 'overlay_metrics.dart';
import 'performance_metrics.dart';
import 'shape_metrics.dart';
import 'start_metrics.dart';
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

/// Raw-sample truths for the contacts of [recording] that make ink and are
/// not bounces ([intendedContacts]).
List<Truth> rawTruths(InputRecording recording) => [
  for (final c in intendedContacts(recording)) Truth.ofContact(c),
];

/// Every quality metric of [s] (performance and overlay are separate).
List<Metric> qualityMetrics(Subject s) {
  final pairs = pairStrokes(s.replay, s.truths);
  return [
    ...fidelity(pairs, s.streamline),
    ...detail(pairs, s.streamline),
    ...smoothness(committedLines(s.replay)),
    ...ends(s.replay, pairs, s.truths, s.streamline),
    ...temporal(s.replay),
    ...start(s.replay, intendedContacts(s.replay.recording)),
  ];
}

/// [qualityMetrics] plus performance and the low-latency overlay model.
List<Metric> allMetrics(Subject s) => [
  ...qualityMetrics(s),
  ...performance(s.replay),
  ...overlay(s.replay),
];
