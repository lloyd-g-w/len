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
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/recording_codec.dart';

import '../sim/cases.dart';
import '../suite.dart';
import 'wet_ink_vectors.dart';

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
      final (events, expected) = wetInkVectors(recording);
      File('$_out/$name.ev').writeAsStringSync(events);
      File('$_out/$name.expected').writeAsStringSync(expected);
    }
  }, skip: _out.isEmpty ? 'opt-in: --dart-define=INKLAB_WET_VECTORS=<dir>' : false);
}
