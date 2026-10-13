// The Ink Lab suite with flat pen ends (butt caps), on a subset cheap
// enough for every test run: each simulated case at one stabiliser
// ([_stabiliser], all three covered), the simulated recordings and a few
// lines of each real S Pen recording as recorded (`excerpt`). Every metric,
// the same limits as inklab_test.dart: flat ends bring their own rules to
// the live tip, the committed ends and the overlay (docs/INK_LAB.md, "Pen
// end styles"). Every entry with both end styles: tools/table_test.dart
// with INKLAB_ENDS=both.
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

/// The stabiliser each simulated case is written at (default 0.4): where
/// flat ends failed before the overlay and the live tip learnt their rules
/// (docs/INK_LAB.md, "A flat pen's live tip"), and spread over 0, 0.4 and 1.
const _stabiliser = {
  'cursive': 1.0,
  'fast_loops': 1.0,
  'zigzag': 0.0,
  'taps': 0.0,
  'hooks': 0.0,
  'bounces': 1.0,
  'long_stroke': 1.0,
};

/// Real recordings and the contacts replayed (from, to): short and
/// medium lines, none of the multi-second ones the pixel metrics take
/// long over.
const _excerpts = [('real_spen_01', 2, 12), ('real_spen_02', 12, 17)];

void main() {
  judgeEntries([
    for (final c in simCases)
      for (final st in [_stabiliser[c.name] ?? 0.4])
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
