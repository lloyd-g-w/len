import 'dart:io';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/recording_codec.dart';
import 'package:len/ink/pen/pen_ends.dart';

import 'metrics/evaluate.dart';
import 'metrics/metric.dart';
import 'sim/cases.dart';

/// One entry of the Ink Lab suite: a simulated case at one stabiliser
/// setting, or a recording from `test/inklab/recordings/`.
class SuiteEntry {
  SuiteEntry(this.name, this.caseName, this.streamline, this._subject);

  /// `case@stabiliser`, e.g. `cursive@0.4`, or `rec:file@stabiliser`.
  final String name;
  final String caseName;
  final double streamline;
  final Subject Function() _subject;

  late final Subject subject = _subject();
  late final List<Metric> metrics = allMetrics(subject);

  Metric? metric(String id) => metrics.where((m) => m.id == id).firstOrNull;

  /// Whether timing metrics are judged: only on entries that are timed
  /// (warmed up and repeated: `long_stroke` and recordings).
  bool get judgedTiming => caseName == 'long_stroke' || caseName.startsWith('rec:');

  /// The metrics the suite judges (timing metrics only when [judgedTiming]).
  List<Metric> get judged => [
    for (final m in metrics)
      if (!m.id.startsWith('perf.') || judgedTiming) m,
  ];
}

/// Directory of committed `.leninput` recordings.
const String recordingsDir = 'test/inklab/recordings';

/// Every simulated case at every stabiliser, then every recording as
/// recorded and at stabiliser 0. With [ends] (e.g. flat), every entry is
/// written with those pen ends instead of the pen's round ones, and its
/// name ends in `/` and the style (`cursive@0.4/flat`).
List<SuiteEntry> suiteEntries({PenEnds? ends}) {
  final suffix = ends == null ? '' : '/${ends.style.name}';
  return [
    for (final c in simCases)
      for (final st in stabilisers)
        SuiteEntry('${c.name}@$st$suffix', c.name, st, () {
          final rec = c.record(defaultPen.copyWith(streamline: st));
          return Subject.of(
            c.name,
            rec.recording,
            truths: rec.truth,
            ends: ends,
            timed: c.name == 'long_stroke',
          );
        }),
    for (final file in recordingFiles()) ...recordingEntries(file, ends: ends),
  ];
}

/// The stabilisers whose entries [inklab_test.dart] leaves to files of their
/// own (inklab_stabiliser_0_4_test.dart, inklab_stabiliser_1_test.dart), so
/// the suite runs in three files at once.
const List<double> stabilisersApart = [0.4, 1];

/// [entries] at [streamline], or with null those at none of
/// [stabilisersApart]: together the files judge every entry once.
Iterable<SuiteEntry> entriesAt(List<SuiteEntry> entries, double? streamline) => entries.where(
  (e) => streamline == null ? !stabilisersApart.contains(e.streamline) : e.streamline == streamline,
);

/// The pen ends `--dart-define=INKLAB_ENDS=<round|flat|tapered>` asks for
/// (null: the pen's own, round).
PenEnds? suiteEnds() {
  const name = String.fromEnvironment('INKLAB_ENDS');
  if (name.isEmpty) return null;
  return PenEnds(style: StrokeEnds.values.byName(name));
}

/// Long real-device recordings (`real_*`) replay thousands of frames through
/// pixel metrics and take many minutes, so the routine suite skips them;
/// run them with `--dart-define=INKLAB_REAL=true` (pen-engine work must).
const bool includeRealRecordings = bool.fromEnvironment('INKLAB_REAL');

List<File> recordingFiles() {
  final dir = Directory(recordingsDir);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.leninput'))
      .where((f) => includeRealRecordings || !f.uri.pathSegments.last.startsWith('real_'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

List<SuiteEntry> recordingEntries(File file, {PenEnds? ends}) {
  final name = 'rec:${file.uri.pathSegments.last.replaceAll('.leninput', '')}';
  final suffix = ends == null ? '' : '/${ends.style.name}';
  final recording = RecordingCodec.decode(file.readAsBytesSync());
  final pen = recording.meta.pen;
  return [
    SuiteEntry(
      '$name@${pen.streamline}$suffix',
      name,
      pen.streamline,
      () => Subject.of(name, recording, ends: ends, timed: true),
    ),
    if (pen.streamline != 0)
      SuiteEntry(
        '$name@0.0$suffix',
        name,
        0,
        () =>
            Subject.of(name, recording, pen: pen.copyWith(streamline: 0), ends: ends, timed: true),
      ),
  ];
}

/// Every metric id the suite knows.
const List<String> metricIds = [
  'fidelity.hausdorff',
  'fidelity.rms',
  'fidelity.width',
  'detail.retraction',
  'smooth.edgeBump16x',
  'smooth.widthBump16x',
  'smooth.facet',
  'ends.blob',
  'ends.nub',
  'ends.stray',
  'ends.dotSize',
  'temporal.behindTip',
  'temporal.settle',
  'temporal.vanished',
  'temporal.bounceFlash',
  'pop.pixels',
  'pop.max',
  'start.distance',
  'start.delay',
  'perf.flatness',
  'perf.frameCost',
  'perf.commit',
  'perf.subpaths',
  'overlay.gap',
  'overlay.ghost',
];

/// Contacts [from] to [to] (exclusive, counted from 0) of [recording], from
/// the first frame after the lift before them to the first frame after
/// their last lift: a few lines of a long take that a routine test can
/// replay.
InputRecording excerpt(InputRecording recording, {int from = 0, required int to}) {
  var lifts = 0;
  var started = from == 0;
  final entries = <InputEntry>[];
  for (final e in recording.entries) {
    if (!started && lifts >= from && e is FrameEntry) started = true;
    if (started) entries.add(e);
    if (e is PointerEntry && (e.type == PointerType.up || e.type == PointerType.cancel)) lifts++;
    if (lifts >= to && e is FrameEntry) break;
  }
  return InputRecording(meta: recording.meta, entries: entries);
}
