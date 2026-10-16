import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/library_screen.dart';

import 'accessibility_test.dart';

// Flutter's accessibility guidelines (see accessibility_test.dart) on a
// phone held sideways: short-window chrome, Android's targets.
void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final label = 'phone sideways ${mode.name}';
    testWidgets('library $label', (tester) async {
      await expectAccessible(
        tester,
        size: sideways,
        scenario: (t) => pumpScreen(t, (_) => const LibraryScreen(), size: sideways, mode: mode),
      );
    });

    for (final MapEntry(key: state, value: taps) in phoneEditorStates.entries) {
      testWidgets('$state $label', (tester) async {
        await expectAccessible(
          tester,
          size: sideways,
          // The options sheet scrolls: its next group fades out at the
          // window's bottom edge, by design.
          contrastHere: const {
            'label: "Size"': 'the pen sheet\'s Size group, inside its scroll fade',
            'label: "0.65 mm"': 'the pen sheet\'s size readout, inside its scroll fade',
          },
          scenario: (t) async {
            await pumpScreen(
              t,
              (s) => EditorScreen(notebook: physics(s)),
              size: sideways,
              mode: mode,
            );
            await tapAll(t, taps());
          },
        );
      });
    }
  }
}
