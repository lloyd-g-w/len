import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/pen/pen_ends.dart';

import 'contacts.dart';
import 'edge_metrics.dart';
import 'machine_load.dart';
import 'metric.dart';
import 'overlay_metrics.dart';
import 'performance_metrics.dart';
import 'shape_metrics.dart';
import 'start_metrics.dart';
import 'temporal_metrics.dart';
import 'truth.dart';

/// A recording replayed with one pen setting, and what it should look like.
class Subject {
  Subject(this.name, this.replay, this.truths, {this.busy = false});

  /// Replays [recording] (with [pen], default: as recorded; with [ends],
  /// default: the pen's round ends). Without
  /// [truths], the raw samples of each committed contact stand in.
  ///
  /// With [timed], the replay runs three times and each frame keeps its
  /// fastest live build and pen-up handling (the first run also warms up),
  /// so a busy machine does not skew the timing metrics; [busy] tells
  /// whether it was busy all the same ([MachineLoad]).
  factory Subject.of(
    String name,
    InputRecording recording, {
    List<Truth>? truths,
    PenSettings? pen,
    PenEnds? ends,
    bool timed = false,
  }) {
    final (replay, waited) = MachineLoad.waitShare(
      () => ReplayResult.run(recording, pen: pen, ends: ends, timingRepeats: timed ? 3 : 1),
    );
    return Subject(
      name,
      replay,
      truths ?? rawTruths(recording),
      busy: timed && (waited > MachineLoad.busyWaitShare || MachineLoad.loadAverageHigh),
    );
  }

  final String name;
  final ReplayResult replay;
  final List<Truth> truths;

  /// Whether the machine was busy while the timed replays ran: other work
  /// waited this thread for a CPU, or the load average was high.
  final bool busy;

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
