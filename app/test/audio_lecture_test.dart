import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/playback_controller.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/library_controller.dart';
import 'package:len/features/library/library_notice.dart';
import 'package:len/ink/ink_surface.dart';
import 'package:len/ui/app_theme.dart';

import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';

/// Round 17 (recording a lecture): the recording stays in sight and
/// keeps going wherever the student goes.

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
  NotebookKind kind = NotebookKind.paged,
  void Function(AppServices s, Notebook nb)? seed,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final audio = FakeAudio();
  final clock = FakeClock()..now = _t0;
  final services = AppServices.create(AppDatabase.inMemory(), clock: clock, audio: audio.backends);
  addTearDown(services.dispose);
  final nb = services.notebooks.create(
    title: 'Calculus',
    kind: kind,
    paper: PaperStyle.wideRuled,
    coverColor: 0xFF3B5BDB,
  );
  seed?.call(services, nb);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Editor(services, nb, audio, clock);
}

Future<void> _settleAsync(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('R17-2: focus mode keeps the recording in sight, docked at the bottom', (
    tester,
  ) async {
    final e = await _pump(tester);
    await tester.tap(find.byTooltip('Record audio'));
    await _settleAsync(tester);
    final pill = find.byKey(const ValueKey('recording-pill')).hitTestable();
    expect(tester.getRect(pill).top, lessThan(60)); // In the top bar.

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(pill, findsOneWidget); // Not the faded top bar's.
    expect(tester.getRect(pill).bottom, greaterThan(700)); // Docked at the bottom.
    await tester.tap(find.byTooltip('Pause recording').hitTestable());
    await _settleAsync(tester);
    expect(find.text('Paused').hitTestable(), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(tester.getRect(pill).top, lessThan(60));
    e.clock.now += 3000;
    await tester.tap(find.byTooltip('Stop recording'));
    await _settleAsync(tester);
    await _close(tester);
  });

  testWidgets('R17-4: the "Saved" message offers to name the recording', (tester) async {
    final e = await _pump(tester);
    await tester.tap(find.byTooltip('Record audio'));
    await _settleAsync(tester);
    e.clock.now += 3000;
    await tester.tap(find.byTooltip('Stop recording'));
    await _settleAsync(tester);
    expect(find.textContaining('Saved “Recording'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lecture 12 — Integrals');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    final saved = e.services.recordings.listOf(e.notebook.id).single;
    expect(saved.title, 'Lecture 12 — Integrals');
    await _close(tester);
  });

  testWidgets('R17-5: the list shows the recording being made, and no Record meanwhile', (
    tester,
  ) async {
    final e = await _pump(tester, size: const Size(390, 844));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record audio'));
    await _settleAsync(tester);
    e.clock.now += 65000;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Recordings'), findsNothing); // None finished yet.
    await tester.tapAt(const Offset(10, 400)); // Close the menu.
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Stop recording'));
    await _settleAsync(tester);
    await tester.pump(const Duration(seconds: 5)); // Snack bar.
    await tester.pumpAndSettle();

    // The second lecture: the list has one, and the one being made.
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record audio'));
    await _settleAsync(tester);
    e.clock.now += 5000;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recordings'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recording-now')), findsOneWidget);
    expect(find.text('Recording now'), findsOneWidget);
    expect(find.text('0:05'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'Record'), findsNothing);
    expect(find.text('1 recording, 1\u00A0min'), findsOneWidget);
    await tester.tapAt(const Offset(10, 100)); // Close the sheet.
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Stop recording'));
    await _settleAsync(tester);
    await _close(tester);
  });

  testWidgets('R17-6: with the player open the pen never pans, and says why it leaves no ink', (
    tester,
  ) async {
    await _pump(
      tester,
      kind: NotebookKind.canvas,
      seed: (s, nb) => s.recordings.save(
        notebookId: nb.id,
        parts: [RecordingPart('cd' * 32, 30000)],
        mime: 'audio/mp4',
        title: 'Lecture',
        segments: const [RecordingSegment(_t0, 30000)],
      ),
    );
    await tester.tap(find.byTooltip('Recordings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lecture'));
    await _settleAsync(tester);
    await tester.pumpAndSettle();
    final viewport = tester.widget<InkSurface>(find.byType(InkSurface)).viewport;
    final before = viewport.toScreen(Offset.zero);

    final pen = await tester.startGesture(const Offset(500, 300), kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await pen.moveTo(Offset(500.0 + i * 10, 300.0 + i * 4));
    }
    await pen.up();
    await tester.pumpAndSettle();
    expect(viewport.toScreen(Offset.zero), before); // Not panned.
    expect(find.text('Tap ink to play is on'), findsOneWidget);

    // A finger still pans.
    final finger = await tester.startGesture(const Offset(500, 300));
    for (var i = 1; i <= 8; i++) {
      await finger.moveTo(Offset(500.0 + i * 10, 300.0));
    }
    await finger.up();
    await tester.pump();
    expect(viewport.toScreen(Offset.zero), isNot(before));

    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tap ink to play (off)'), findsOneWidget);
    await _close(tester);
  });

  test('R17-3: a recording made elsewhere downloads a few parts at once, with progress', () async {
    final audio = FakeAudio();
    final services = AppServices.create(AppDatabase.inMemory(), audio: audio.backends);
    addTearDown(services.dispose);
    final pending = <String, Completer<bool>>{};
    final playback = PlaybackController(
      backends: audio.backends,
      blobs: services.blobs,
      fetch: (sha) => (pending[sha] = Completer<bool>()).future,
    );
    addTearDown(playback.dispose);
    final parts = [for (var i = 0; i < 6; i++) RecordingPart('$i' * 64, 300000)];
    final lecture = Recording(
      id: 'r',
      notebookId: 'n',
      title: 'Lecture 12',
      startedAt: _t0,
      parts: parts,
      durationMs: 1800000,
      updatedAt: _t0,
      mime: 'audio/aac',
      segments: const [RecordingSegment(_t0, 1800000)],
    );
    final opened = playback.open(lecture);
    await pumpEventQueue();
    expect(pending.length, PlaybackController.parallelFetches);
    expect(playback.downloading, 0);
    expect(audio.log, isEmpty); // Not handed to the player yet.

    pending['0' * 64]!.complete(true);
    await pumpEventQueue();
    expect(playback.downloading, closeTo(1 / 6, 1e-9));
    expect(pending.length, 4); // The next one started.
    for (var i = 1; i < 6; i++) {
      pending['$i' * 64]?.complete(i != 4); // Part 4 can't be had.
      await pumpEventQueue();
    }
    for (final c in pending.values) {
      if (!c.isCompleted) c.complete(true);
    }
    expect(await opened, isTrue);
    expect(playback.downloading, isNull);
    expect(audio.log, ['open Lecture 12', 'play']);
  });

  testWidgets('R17-1: another notebook, or the library, says a lecture is still recording', (
    tester,
  ) async {
    final e = await _pump(tester);
    await tester.tap(find.byTooltip('Record audio'));
    await _settleAsync(tester);
    final physics = e.services.notebooks.create(
      title: 'Physics',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    Widget app(Widget home) => AppScope(
      services: e.services,
      child: MaterialApp(theme: AppTheme.light(), home: home),
    );
    // Another tab: the lecture goes on, and this editor says so.
    await tester.pumpWidget(app(EditorScreen(key: ValueKey(physics.id), notebook: physics)));
    await tester.pumpAndSettle();
    e.clock.now += 65000;
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('recording-elsewhere')), findsOneWidget);
    expect(find.text('Recording in “Calculus”'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(e.services.recordings.listOf(e.notebook.id), isEmpty);

    // The library too.
    await tester.pumpWidget(app(const Scaffold(body: LibraryNotices(child: SizedBox.expand()))));
    await tester.pumpAndSettle();
    expect(find.text('Recording in “Calculus” · 1:05'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await _settleAsync(tester);
    expect(find.textContaining('Saved “Recording'), findsOneWidget);
    expect(find.byKey(const ValueKey('recording-elsewhere')), findsNothing);
    expect(e.services.recordings.listOf(e.notebook.id).single.durationMs, 65000);
    expect(e.services.sharedNotebooks.unattended.value, isNull);
    await _close(tester);
  });

  testWidgets('R17: trashing (or deleting the folder of) a notebook recording unattended stops '
      'and saves the recording into it; restoring brings back both', (tester) async {
    for (final viaFolder in [false, true]) {
      final e = await _pump(
        tester,
        seed: viaFolder
            ? (s, nb) => s.notebooks.moveTo(nb.id, s.folders.create(name: 'Year 1', color: 0).id)
            : null,
      );
      await tester.tap(find.byTooltip('Record audio'));
      await _settleAsync(tester);
      e.clock.now += 65000;
      await tester.pumpWidget(
        AppScope(
          services: e.services,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: LibraryNotices(child: SizedBox.expand())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recording-elsewhere')), findsOneWidget);

      final library = LibraryController(e.services);
      final List<String> trashed;
      if (viaFolder) {
        final folder = e.services.notebooks.get(e.notebook.id)!.folderId!;
        trashed = library.deleteFolder(folder).notebookIds;
      } else {
        trashed = library.trashNotebooks([e.notebook.id]);
      }
      await _settleAsync(tester);
      expect(find.byKey(const ValueKey('recording-elsewhere')), findsNothing);
      expect(e.services.sharedNotebooks.unattended.value, isNull);
      expect(e.services.sharedNotebooks.ids, isEmpty);
      expect(e.services.recordings.listOf(e.notebook.id).single.durationMs, 65000);

      library.restoreNotebooks(trashed);
      expect(e.services.notebooks.get(e.notebook.id)!.isTrashed, isFalse);
      expect(e.services.recordings.listOf(e.notebook.id), hasLength(1));
      library.dispose();
      await _close(tester);
    }
  });

  testWidgets('R17: Show on the library notice never opens a notebook trashed meanwhile', (
    tester,
  ) async {
    final e = await _pump(tester);
    await tester.tap(find.byTooltip('Record audio'));
    await _settleAsync(tester);
    e.clock.now += 65000;
    await tester.pumpWidget(
      AppScope(
        services: e.services,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: LibraryNotices(child: SizedBox.expand())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Trashed by a path that doesn't let it go (not the library's).
    e.services.notebooks.trash(e.notebook.id);
    await tester.tap(find.text('Show'));
    await _settleAsync(tester);
    expect(find.byType(EditorScreen), findsNothing);
    expect(
      find.text('“Calculus” is in the trash: its recording stopped and was saved there'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('recording-elsewhere')), findsNothing);
    expect(e.services.recordings.listOf(e.notebook.id), hasLength(1));
    await _close(tester);
  });
}
