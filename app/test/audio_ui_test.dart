import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/chrome/chrome_metrics.dart';
import 'package:len/features/editor/chrome/editor_top_bar.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ink/ink_surface.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;
import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';
import 'support/handwriting.dart';

/// Recording starts at this wall time in these tests.
const _t0 = 1000000;

class _Editor {
  _Editor(this.services, this.notebook, this.audio, this.clock);

  final AppServices services;
  final Notebook notebook;
  final FakeAudio audio;
  final FakeClock clock;
}

Future<_Editor> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  NotebookKind kind = NotebookKind.canvas,
  bool fonts = false,
  void Function(AppServices s, Notebook nb)? seed,
}) async {
  if (fonts) await loadFonts();
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final audio = FakeAudio();
  final clock = FakeClock()..now = _t0;
  final services = AppServices.create(AppDatabase.inMemory(), clock: clock, audio: audio.backends);
  addTearDown(services.dispose);
  final nb = services.notebooks.create(
    title: 'Biology lecture',
    kind: kind,
    paper: PaperStyle.wideRuled,
    coverColor: 0xFF3B5BDB,
  );
  seed?.call(services, nb);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Editor(services, nb, audio, clock);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// Lets the controllers' futures (fakes, blob store) complete.
Future<void> _settleAsync(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A handwritten "word" at [origin], written at wall time [at].
Stroke _word(String id, String surface, Offset origin, int at, {int letters = 6, int seed = 1}) {
  const shapes = [(height: 16.0, loop: 4.0), (height: 36.0, loop: 4.0), (height: 16.0, loop: 1.0)];
  final points = Handwriting(seed: seed).cursive(origin, [
    for (var i = 0; i < letters; i++) shapes[(i * 7 + seed) % 3],
  ], letterWidth: 15);
  return Stroke(
    id: id,
    surfaceId: surface,
    tool: InkTool.ballpoint,
    color: 0xFF1F2937,
    width: 2.6,
    points: points,
    createdAt: at,
  );
}

/// Three lines of notes on [surface], each word written 2 s after the last
/// from [_t0] + 1 s; returns the strokes.
List<Stroke> _notes(AppServices s, String surface, {Offset origin = const Offset(160, 220)}) {
  final strokes = <Stroke>[];
  var i = 0;
  for (var line = 0; line < 3; line++) {
    for (var w = 0; w < 4; w++) {
      final at = Offset(origin.dx + w * 130, origin.dy + line * 64);
      strokes.add(_word('s$i', surface, at, _t0 + 1000 + i * 2000, letters: 4 + i % 3, seed: i));
      i++;
    }
  }
  s.strokes.save(strokes);
  return strokes;
}

Recording _recording(AppServices s, String notebookId, {String title = 'Lecture'}) =>
    s.recordings.create(
      notebookId: notebookId,
      blob: 'cd' * 32,
      mime: 'audio/mp4',
      title: title,
      segments: const [RecordingSegment(_t0, 30000)],
    );

void main() {
  testWidgets('record, pause, resume and stop from the top bar; manage recordings', (tester) async {
    final e = await _pump(tester, fonts: true);
    expect(find.byTooltip('Recordings'), findsNothing);
    await tester.tap(find.byTooltip('Record audio'));
    await _settleAsync(tester);
    expect(e.audio.log, ['permission', 'start']);
    expect(find.byKey(const ValueKey('recording-pill')), findsOneWidget);

    e.audio.capture.emitLevel(0.8);
    e.clock.now += 65000;
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1:05'), findsOneWidget);
    await expectLater(
      find.byType(EditorTopBar),
      matchesGoldenFile('goldens/audio_recording_bar.png'),
    );

    await tester.tap(find.byTooltip('Pause recording'));
    await _settleAsync(tester);
    e.clock.now += 20000; // Paused: does not count.
    await tester.tap(find.byTooltip('Resume recording'));
    await _settleAsync(tester);
    e.clock.now += 5000;
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1:10'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop recording'));
    await _settleAsync(tester);
    final saved = e.services.recordings.listOf(e.notebook.id).single;
    expect(saved.segments, const [
      RecordingSegment(_t0, 65000),
      RecordingSegment(_t0 + 85000, 5000),
    ]);
    expect(find.textContaining('Saved'), findsOneWidget);
    expect(find.byKey(const ValueKey('recording-pill')), findsNothing);

    // The list: rename, then delete.
    await tester.tap(find.byTooltip('Recordings'));
    await tester.pumpAndSettle();
    expect(find.text(saved.title), findsOneWidget);
    expect(find.text('1 recording · 1:10 · 64 bytes'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^\d+ Jan 1970, \d\d:\d\d · 1:10 · 64 bytes$')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cells');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(e.services.recordings.get(saved.id)!.title, 'Cells');
    expect(find.text('Cells'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(e.services.recordings.listOf(e.notebook.id), isEmpty);
    expect(find.text('No recordings yet', findRichText: true), findsNothing);
    await _close(tester);
  });

  testWidgets('playback fades later ink; tapping ink plays from when it was written', (
    tester,
  ) async {
    late List<Stroke> notes;
    final e = await _pump(
      tester,
      fonts: true,
      seed: (s, nb) {
        notes = _notes(s, nb.id);
        _recording(s, nb.id);
      },
    );
    await tester.tap(find.byTooltip('Recordings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lecture'));
    await _settleAsync(tester);
    await tester.pumpAndSettle();
    expect(e.audio.log, ['open Lecture', 'play']);
    expect(find.byKey(const ValueKey('playback-bar')), findsOneWidget);

    // 9.5 s in: the first five words are written, the rest is faded.
    e.audio.player.emit(9500);
    await tester.pump();
    expect(find.text('0:09 / 0:30'), findsOneWidget);
    await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/audio_playback.png'));

    // Tap the ninth word (written at 17 s): play from 1.5 s before.
    final viewport = tester.widget<InkSurface>(find.byType(InkSurface)).viewport;
    await tester.tapAt(_screenOf(viewport, notes[8]));
    await _settleAsync(tester);
    expect(e.audio.log.last, 'seek ${17000 - 1500}');
    expect(_inkOf(e.services, e.notebook.id).length, notes.length);

    // Tapping empty paper does nothing.
    final before = e.audio.log.length;
    await tester.tapAt(const Offset(1000, 600));
    await _settleAsync(tester);
    expect(e.audio.log.length, before);

    // With "tap ink to play" off, the pen draws again.
    await tester.tap(find.byTooltip('Tapping ink plays from it (on)'));
    await tester.pump();
    final gesture = await tester.startGesture(
      const Offset(900, 600),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset(900.0 + i * 8, 600.0 + i * 3));
    }
    await gesture.up();
    await tester.pump();
    expect(_inkOf(e.services, e.notebook.id).length, notes.length + 1);

    await tester.tap(find.byTooltip('Close player'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playback-bar')), findsNothing);
    await _close(tester);
  });

  testWidgets('phone, paged: record from the menu (floating controls), replay on pages', (
    tester,
  ) async {
    final e = await _pump(
      tester,
      size: const Size(390, 844),
      kind: NotebookKind.paged,
      fonts: true,
      seed: (s, nb) {
        _notes(s, s.pages.pagesOf(nb.id).first.id, origin: const Offset(80, 160));
        _recording(s, nb.id, title: 'Seminar');
      },
    );
    expect(find.byTooltip('Record audio'), findsNothing); // No room in the bar.
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record audio'));
    await _settleAsync(tester);
    expect(find.byKey(const ValueKey('recording-pill')), findsOneWidget);
    e.clock.now += 3000;
    await tester.tap(find.byTooltip('Stop recording'));
    await _settleAsync(tester);
    expect(e.services.recordings.listOf(e.notebook.id), hasLength(2));
    await tester.pump(const Duration(seconds: 5)); // Snack bar.
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recordings…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seminar'));
    await _settleAsync(tester);
    await tester.pumpAndSettle();
    e.audio.player.emit(13500);
    ScaffoldMessenger.of(tester.element(find.byType(EditorScreen))).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/audio_playback_phone.png'),
    );

    // Tap the second word of the page (written at 3 s).
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    final stroke = _inkOf(e.services, doc.pages.first.id).firstWhere((s) => s.id == 's1');
    final frame = doc.layout.frameOf(0)!;
    final world = stroke.points[stroke.points.length ~/ 2].offset + frame.topLeft;
    await tester.tapAt(doc.viewport.toScreen(world));
    await _settleAsync(tester);
    expect(e.audio.log.last, 'seek ${3000 - 1500}');
    await _close(tester);
  });

  for (final size in const [Size(640, 900), Size(700, 900), Size(844, 390), Size(800, 1280)]) {
    testWidgets('the top bar fits a recording paged notebook at ${size.width.toInt()} dp', (
      tester,
    ) async {
      final e = await _pump(
        tester,
        size: size,
        kind: NotebookKind.paged,
        seed: (s, nb) => _recording(s, nb.id),
      );
      expect(find.byTooltip('Recordings'), findsOneWidget);
      if (size.width < ChromeMetrics.roomyBarWidth) {
        // All pages and the bookmark move into the "⋯" menu.
        expect(find.byTooltip('All pages'), findsNothing);
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        expect(find.text('All pages'), findsOneWidget);
        expect(find.text('Bookmark page'), findsOneWidget);
        await tester.tapAt(const Offset(20, 300));
        await tester.pumpAndSettle();
      } else {
        expect(find.byTooltip('All pages'), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Record audio'));
      await _settleAsync(tester);
      expect(find.byKey(const ValueKey('recording-pill')), findsOneWidget);
      expect(tester.takeException(), isNull); // No overflow.
      e.clock.now += 1000;
      await tester.tap(find.byTooltip('Stop recording'));
      await _settleAsync(tester);
      await _close(tester);
    });
  }

  testWidgets('leaving the editor saves a running recording', (tester) async {
    final e = await _pump(tester);
    await tester.tap(find.byTooltip('Record audio'));
    await _settleAsync(tester);
    e.clock.now += 4000;
    await _close(tester);
    await _settleAsync(tester);
    expect(e.services.recordings.listOf(e.notebook.id).single.durationMs, 4000);
    expect(e.audio.log, containsAllInOrder(['start', 'stop', 'dispose']));
  });

  testWidgets('Android: pausing the app stops and saves the recording', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final e = await _pump(tester);
    await tester.tap(find.byTooltip('Record audio'));
    await _settleAsync(tester);
    e.clock.now += 2500;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await _settleAsync(tester);
    expect(e.services.recordings.listOf(e.notebook.id).single.durationMs, 2500);
    // Paused apps draw no frames; back in front the bar is idle again.
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(find.byKey(const ValueKey('recording-pill')), findsNothing);
    expect(find.byTooltip('Record audio'), findsOneWidget);
    await _close(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('refused microphone access explains itself', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final audio = FakeAudio(allow: false);
    final services = AppServices.create(AppDatabase.inMemory(), audio: audio.backends);
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'N',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(home: EditorScreen(notebook: nb)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Record audio'));
    await _settleAsync(tester);
    expect(find.text('Microphone access was not allowed.'), findsOneWidget);
    expect(find.byKey(const ValueKey('recording-pill')), findsNothing);
    await _close(tester);
  });
}

Offset _screenOf(ViewportController viewport, Stroke stroke) =>
    viewport.toScreen(stroke.points[stroke.points.length ~/ 2].offset);

List<Stroke> _inkOf(AppServices s, String surface) => SurfaceCopier(s.strokes).loadAll(surface);
