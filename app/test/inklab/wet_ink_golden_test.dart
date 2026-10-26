// The shared golden of the wet-ink model: what the Dart model
// (`lib/ink/lab/wet_ink_model.dart`) draws for a recording, committed where
// the Kotlin port's unit test (`android/app/src/test/.../WetInkModelTest.kt`)
// checks its own answers against it. After changing the Dart model, update
// the golden and port the change:
//
//   flutter test test/inklab/wet_ink_golden_test.dart \
//     --dart-define=UPDATE_WET_INK_GOLDEN=true
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/lab/recording_codec.dart';

import 'tools/wet_ink_vectors.dart';

const bool _update = bool.fromEnvironment('UPDATE_WET_INK_GOLDEN');
const String _golden = 'android/app/src/test/resources/wet_ink';

void main() {
  // Recordings and how many of their contacts (a real one: its first two).
  for (final (name, contacts) in [('sim_hooks', null), ('real_spen_01', 2)]) {
    for (final variant in endVariants.entries) {
      final key = '$name${variant.key}';
      test('the wet-ink model draws $key as the golden says', () {
        final recording = RecordingCodec.decode(
          File('test/inklab/recordings/$name.leninput').readAsBytesSync(),
        );
        // Querying every 9th sample keeps the golden small; the model sees all.
        final (events, expected) = wetInkVectors(
          recording,
          queryEvery: 9,
          maxContacts: contacts,
          ends: variant.value,
        );
        final ev = File('$_golden/$key.ev');
        final out = File('$_golden/$key.expected');
        if (_update) {
          ev
            ..createSync(recursive: true)
            ..writeAsStringSync(events);
          out.writeAsStringSync(expected);
        }
        expect(ev.readAsStringSync(), events);
        expect(out.readAsStringSync(), expected);
      });
    }
  }
  // The stabiliser's longest string (80 px at 100 %): the overlay pulls the
  // ink as Flutter does.
  test('the wet-ink model draws sim_cursive_string as the golden says', () {
    final recording = RecordingCodec.decode(
      File('test/inklab/recordings/sim_cursive.leninput').readAsBytesSync(),
    );
    final (events, expected) = wetInkVectors(recording, queryEvery: 9, stabiliser: 1);
    final ev = File('$_golden/sim_cursive_string.ev');
    final out = File('$_golden/sim_cursive_string.expected');
    if (_update) {
      ev.writeAsStringSync(events);
      out.writeAsStringSync(expected);
    }
    expect(ev.readAsStringSync(), events);
    expect(out.readAsStringSync(), expected);
  });
}
