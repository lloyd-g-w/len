import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/documents/scan/scan_screen.dart';
import 'package:len/features/documents/scan/scan_session.dart';
import 'package:len/features/documents/scan/scan_sources.dart';
import 'package:len/features/editor/document/page_overview.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/settings/settings_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'accessibility_test.dart';
import 'screenshots/screenshot_harness.dart';

// Flutter's accessibility guidelines (see accessibility_test.dart) over the
// screens and slips beyond the library, settings and editor chrome: the
// page overview, recordings, scan, storage, the library's menus and
// sheets, and large text (1.5× and 2×) on each.

/// Seeded services whose Physics notebook has a recording.
AppServices withRecording() {
  final s = seededServices();
  const sha = 'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0';
  s.database.execute(
    'INSERT INTO blobs (sha256, size, mime, created_at, uploaded) VALUES (?, ?, ?, 0, 1)',
    [sha, 4 << 20, Recording.adtsMime],
  );
  s.recordings.save(
    notebookId: physics(s).id,
    parts: [const RecordingPart(sha, 600000)],
    mime: Recording.adtsMime,
    title: 'Lecture 4',
    segments: const [RecordingSegment(0, 600000)],
  );
  return s;
}

Widget overview(AppServices s) {
  final id = physics(s).id;
  return PageOverview(
    currentPage: 0,
    copier: SurfaceCopier(s.strokes, elements: s.elements),
    handlers: OverviewHandlers(
      load: () => s.pages.pagesOf(id),
      command: (context, command, page) async {},
      move: (page, to) => s.pages.move(page, to),
    ),
  );
}

Widget scan(AppServices s) => ScanScreen(
  session: ScanSession(),
  doneLabel: 'Create notebook',
  sources: ScanSources(pick: () async => [], camera: () async => null),
);

/// Opens the recordings list: from the bar, or "⋯" on phones.
Future<void> openRecordings(WidgetTester tester) async {
  final bar = find.byTooltip('Recordings');
  if (bar.evaluate().isNotEmpty) return tapAll(tester, [bar]);
  await tapAll(tester, [find.byTooltip('More options'), find.text('Recordings')]);
}

/// Settings in a window tall enough to show Storage unscrolled: the pinned
/// title would clip rows scrolled under it to slivers the guideline
/// measures.
Future<void> openStorage(WidgetTester tester) async {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  setWindow(tester, Size(width, 4000), pointer: !Targets.touchFirst);
  await settle(tester);
  expect(find.text('Largest notebooks'), findsOneWidget);
}

/// A screen, how to reach it and what it needs.
typedef Screen = ({
  Widget Function(AppServices) home,
  AppServices Function()? services,
  Future<void> Function(WidgetTester)? open,
});

final Map<String, Screen> screens = {
  'overview': (home: overview, services: null, open: null),
  'overview selecting': (
    home: overview,
    services: null,
    open: (t) => tapAll(t, [find.text('Select'), find.byKey(const ValueKey('page-tile-0'))]),
  ),
  'recordings': (
    home: (s) => EditorScreen(notebook: physics(s)),
    services: withRecording,
    open: openRecordings,
  ),
  'scan': (home: scan, services: null, open: null),
  'storage': (home: (_) => const SettingsScreen(), services: null, open: openStorage),
  'library view menu': (
    home: (_) => const LibraryScreen(),
    services: null,
    open: (t) => tapAll(t, [find.byTooltip('View')]),
  ),
  'library search': (
    home: (_) => const LibraryScreen(),
    services: null,
    // Phones: behind a button; wider windows show the field.
    open: (t) async {
      final button = find.byTooltip('Search');
      await tapAll(t, [if (button.evaluate().isNotEmpty) button, find.byType(TextField)]);
    },
  ),
  'notebook menu': (
    home: (_) => const LibraryScreen(),
    services: null,
    open: (t) => tapAll(t, [find.byTooltip('More').first]),
  ),
};

void main() {
  for (final (name, size) in [('phone', phone), ('tablet', tablet)]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final MapEntry(key: screen, value: s) in screens.entries) {
        testWidgets('$screen $name ${mode.name}', (tester) async {
          await expectAccessible(
            tester,
            size: size,
            scenario: (t) async {
              await pumpScreen(t, s.home, size: size, mode: mode, services: s.services);
              await s.open?.call(t);
            },
          );
        });
      }
    }
  }

  // Large text: Android's font sizes go to 2×; 1.5× is a common choice.
  final large = <String, Screen>{
    'library': (home: (_) => const LibraryScreen(), services: null, open: null),
    'settings': (home: (_) => const SettingsScreen(), services: null, open: null),
    'editor': (home: (s) => EditorScreen(notebook: physics(s)), services: null, open: null),
    'new notebook': (
      home: (_) => const LibraryScreen(),
      services: null,
      open: (t) => tapAll(t, [find.bySemanticsLabel('New notebook')]),
    ),
    'export sheet': (
      home: (s) => EditorScreen(notebook: physics(s)),
      services: null,
      open: (t) => tapAll(t, [find.byTooltip('More options'), find.text('Export…')]),
    ),
    'more menu': (
      home: (s) => EditorScreen(notebook: physics(s)),
      services: null,
      open: (t) => tapAll(t, [find.byTooltip('More options')]),
    ),
    ...screens,
  };
  // What the contrast check can't measure at large text, by screen.
  const largeContrast = <String, Map<String, String>>{
    // Passes with the app's font; with the test font's boxes at 2× the
    // check reads the outlined button's label as a light grey.
    'scan': {'label: "Choose photos…"': 'the test font at 2×; passes with Sofia Sans'},
  };
  for (final scale in [1.5, 2.0]) {
    for (final (name, size) in [
      ('phone', phone),
      ('phone sideways', sideways),
      ('tablet', tablet),
    ]) {
      for (final MapEntry(key: screen, value: s) in large.entries) {
        // The menu scrolls on a short window: its last row sits in the
        // scroll fade by design.
        if (screen == 'more menu' && size == sideways) continue;
        testWidgets('$screen $name at $scale× text', (tester) async {
          await expectAccessible(
            tester,
            size: size,
            contrastHere: largeContrast[screen] ?? const {},
            scenario: (t) async {
              await pumpScreen(t, s.home, size: size, textScale: scale, services: s.services);
              await s.open?.call(t);
            },
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
