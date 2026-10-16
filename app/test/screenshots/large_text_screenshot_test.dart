@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/settings/settings_screen.dart';

import '../accessibility_screens_test.dart' show overview, scan, withRecording, openRecordings;
import '../accessibility_test.dart' show physics, tapAll;
import 'screenshot_harness.dart';

/// The main screens and slips at 1.5× and 2× text (Android's largest font
/// size), on a phone, a phone held sideways and a tablet: nothing
/// overflows, and the PNGs show what is cut or crowded.
void main() {
  setUpAll(loadRealFonts);

  Widget editor(AppServices s) => EditorScreen(notebook: physics(s));
  final shots = <String, (Widget Function(AppServices), List<Finder> Function())>{
    'library': ((_) => const LibraryScreen(), () => []),
    'settings': ((_) => const SettingsScreen(), () => []),
    'editor': (editor, () => []),
    'more': (editor, () => [find.byTooltip('More options')]),
    'export': (editor, () => [find.byTooltip('More options'), find.text('Export…')]),
    'new_notebook': ((_) => const LibraryScreen(), () => [find.bySemanticsLabel('New notebook')]),
    'overview': (overview, () => []),
    'scan': (scan, () => []),
  };

  for (final (device, size) in [
    ('phone', const Size(390, 844)),
    ('sideways', const Size(844, 390)),
    ('tablet', const Size(1280, 800)),
  ]) {
    for (final scale in [1.5, 2.0]) {
      for (final MapEntry(key: name, value: (home, taps)) in shots.entries) {
        testWidgets('$name $device at $scale×', (tester) async {
          setWindow(tester, size);
          final s = seededServices();
          addTearDown(s.dispose);
          await pumpApp(tester, s, home(s), textScale: scale);
          await tapAll(tester, taps());
          expect(tester.takeException(), isNull);
          await shoot(tester, 'large_${name}_${device}_${scale}x');
        });
      }
      testWidgets('recordings $device at $scale×', (tester) async {
        setWindow(tester, size);
        final s = withRecording();
        addTearDown(s.dispose);
        await pumpApp(tester, s, editor(s), textScale: scale);
        await openRecordings(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'large_recordings_${device}_${scale}x');
      });
    }
  }
}
