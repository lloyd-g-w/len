// The Ink Lab suite with flat pen ends (butt caps), on a subset cheap
// enough for every test run: every simulated case at stabiliser 0 and 1,
// `long_stroke` (timing) at the default 0.4, the simulated recordings as
// recorded, and a few lines of each real S Pen recording as recorded
// (`excerpt`). Every metric, the same limits as inklab_test.dart; flat ends
// bring their own rules to the live tip, the committed ends and the
// overlay (docs/INK_LAB.md, "Pen end styles"). All entries and both end
// styles: tools/table_test.dart with INKLAB_ENDS=both.
@Tags(['inklab'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/recording_codec.dart';
import 'package:len/ink/pen/pen_ends.dart';

import 'judge.dart';
import 'metrics/evaluate.dart';
import 'sim/cases.dart';
import 'suite.dart';

const _flat = PenEnds(style: StrokeEnds.flat);

/// Real recordings and the contacts replayed (from, to): short and
/// medium lines, none of the multi-second ones the pixel metrics take
/// long over.
const _excerpts = [('real_spen_01', 2, 12), ('real_spen_02', 12, 20)];

void main() {
  judgeEntries([
    for (final c in simCases)
      for (final st in c.name == 'long_stroke' ? const [0.4] : const [0.0, 1.0])
        SuiteEntry('${c.name}@$st/flat', c.name, st, () {
          final rec = c.record(defaultPen.copyWith(streamline: st));
          return Subject.of(
            c.name,
            rec.recording,
            truths: rec.truth,
            ends: _flat,
            timed: c.name == 'long_stroke',
          );
        }),
    for (final file in recordingFiles())
      if (!file.uri.pathSegments.last.startsWith('real_'))
        recordingEntries(file, ends: _flat).first,
    for (final (name, from, to) in _excerpts) _excerptEntry(name, from, to),
  ]);
}

SuiteEntry _excerptEntry(String file, int from, int to) {
  final name = 'rec:$file';
  final recording = excerpt(
    RecordingCodec.decode(File('$recordingsDir/$file.leninput').readAsBytesSync()),
    from: from,
    to: to,
  );
  final st = recording.meta.pen.streamline;
  return SuiteEntry(
    '$name[$from-$to]@$st/flat',
    name,
    st,
    () => Subject.of(name, recording, ends: _flat, timed: true),
  );
}
