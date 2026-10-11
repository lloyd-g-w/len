import 'dart:io';

import 'package:len/ink/lab/recording_codec.dart';

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
/// recorded and at stabiliser 0.
List<SuiteEntry> suiteEntries() => [
  for (final c in simCases)
    for (final st in stabilisers)
      SuiteEntry('${c.name}@$st', c.name, st, () {
        final rec = c.record(defaultPen.copyWith(streamline: st));
        return Subject.of(c.name, rec.recording, truths: rec.truth, timed: c.name == 'long_stroke');
      }),
  for (final file in recordingFiles()) ...recordingEntries(file),
];

/// Long real-device recordings (`real_*`) replay thousands of frames through
/// pixel metrics and take many minutes, so the routine suite skips them;
/// run them with `--dart-define=INKLAB_REAL=true` (CI for pen work does).
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

List<SuiteEntry> recordingEntries(File file) {
  final name = 'rec:${file.uri.pathSegments.last.replaceAll('.leninput', '')}';
  final recording = RecordingCodec.decode(file.readAsBytesSync());
  final pen = recording.meta.pen;
  return [
    SuiteEntry(
      '$name@${pen.streamline}',
      name,
      pen.streamline,
      () => Subject.of(name, recording, timed: true),
    ),
    if (pen.streamline != 0)
      SuiteEntry(
        '$name@0.0',
        name,
        0,
        () => Subject.of(name, recording, pen: pen.copyWith(streamline: 0), timed: true),
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
