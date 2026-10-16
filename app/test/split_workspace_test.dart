import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/stroke_reader.dart';
import 'package:len/domain/chunk_digest.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/audio/recording_controller.dart';
import 'package:len/features/audio/ui/audio_bar_button.dart';
import 'package:len/features/editor/chrome/editor_tips.dart';
import 'package:len/features/editor/chrome/editor_top_bar.dart';
import 'package:len/features/editor/chrome/title_button.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_session.dart';
import 'package:len/features/editor/finger_reading.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/sync/sync_engine.dart';
import 'package:len/ui/text_prompt.dart';

import 'document_editor_test.dart' show closeEditor;
import 'split_view_test.dart';
import 'support/fake_audio.dart';
import 'support/real_async.dart';

/// The sessions of the shown editors, left to right.
List<EditorSession> sessionsOf(WidgetTester tester) =>
    tester.widgetList<EditorCanvas>(find.byType(EditorCanvas)).map((c) => c.session).toList();

SurfaceModel firstPageOf(EditorSession session) {
  final doc = session.doc!;
  return doc.surfaces.surfaceOf(doc.pages.first.id).model;
}

int strokesOn(SurfaceModel model) => model.strokesNear(Rect.largest).length;

Stroke inkStroke(String surfaceId) => Stroke(
  id: 'ink-$surfaceId',
  surfaceId: surfaceId,
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 2,
  points: const [StrokePoint(10, 10, 0.5), StrokePoint(40, 30, 0.5)],
  createdAt: 1,
);

void main() {
  testWidgets('two views of one notebook share its models: edits show at once, no reloads', (
    tester,
  ) async {
    final (s, physics, _) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    final [left, right] = sessionsOf(tester);
    expect(firstPageOf(left), same(firstPageOf(right)));
    expect(left.backgrounds, same(right.backgrounds), reason: 'one PDF cache per notebook');
    expect(left.pdf!.info, same(right.pdf!.info));

    final model = firstPageOf(right);
    var reloads = 0;
    final sub = model.invalidations.listen((chunks) {
      if (chunks == null) reloads++; // Everything stale: a reload.
    });
    addTearDown(sub.cancel);
    await drawIn(tester, 0);
    expect(strokesOn(model), 1, reason: 'without waiting for a mirror');
    await tester.pump(const Duration(seconds: 1));
    expect(reloads, 0);
    await closeEditor(tester);
  });

  testWidgets('undo in either view: one history, nothing erased in one comes back in the other', (
    tester,
  ) async {
    final (s, physics, _) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    final [left, right] = sessionsOf(tester);
    final model = firstPageOf(left);
    int stored() => inkOfNotebook(s, physics).length;

    await drawIn(tester, 0);
    final stroke = model.strokesNear(Rect.largest).single;
    // The right pane erases what the left drew.
    final at = stroke.points.first.offset;
    expect(firstPageOf(right).eraseAlong(at, at, 4, continueEdit: false), isTrue);
    await tester.pump();
    expect((strokesOn(model), stored()), (0, 0));
    expect(left.undo.canUndo && right.undo.canUndo, isTrue);

    // The left pane's undo undoes the latest edit, the erase.
    left.undo.undo();
    await tester.pump();
    expect((strokesOn(model), stored()), (1, 1));
    // Then the drawing, from the right pane.
    right.undo.undo();
    await tester.pump();
    expect((strokesOn(model), stored()), (0, 0));
    expect(left.undo.canUndo || right.undo.canUndo, isFalse);
    // Redo both steps: drawn, then erased again (never resurrected).
    left.undo.redo();
    left.undo.redo();
    await tester.pump();
    expect((strokesOn(model), stored()), (0, 0));
    expect(right.undo.canRedo, isFalse);
    await closeEditor(tester);
  });

  testWidgets('a page added in one view shows in the other', (tester) async {
    final (s, physics, _) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    final [left, right] = sessionsOf(tester);
    final before = right.doc!.pages.length;
    left.commands!.addPage();
    await tester.pumpAndSettle();
    expect(right.doc!.pages.length, before + 1);
    expect(right.doc!.pages.map((p) => p.id), left.doc!.pages.map((p) => p.id));
    await closeEditor(tester);
  });

  testWidgets('two views of one canvas share its surface and undo', (tester) async {
    final (s, physics, _) = await pumpWorkspace(tester, kind: NotebookKind.canvas);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    final [left, right] = sessionsOf(tester);
    expect(left.canvas, same(right.canvas));
    expect(right.undo.canUndo, isFalse);
    final model = left.canvas!;
    model.addStroke(inkStroke(physics.id));
    await tester.pump();
    expect(right.undo.canUndo, isTrue);
    right.undo.undo();
    expect(strokesOn(model), 0);
    await closeEditor(tester);
  });

  testWidgets('renaming or new paper in one view shows in the other', (tester) async {
    final (s, physics, _) = await pumpWorkspace(tester, kind: NotebookKind.canvas);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TitleButton).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Mechanics');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    final titles = tester.widgetList<EditorTopBar>(find.byType(EditorTopBar)).map((b) => b.title);
    expect(titles, ['Mechanics', 'Mechanics']);
    expect(s.openNotebooks.tabs.map((t) => t.title), contains('Mechanics'));

    s.sharedNotebooks
        .peek(physics.id)!
        .update(
          (n) => n.copyWith(paper: const Paper(PaperStyle.dotted), paperColor: PaperColor.dark),
        );
    await tester.pump();
    final papers = tester.widgetList<EditorCanvas>(find.byType(EditorCanvas));
    expect(papers.map((c) => (c.paper, c.paperColor)), [
      (const Paper(PaperStyle.dotted), PaperColor.dark),
      (const Paper(PaperStyle.dotted), PaperColor.dark),
    ]);
    await closeEditor(tester);
  });

  testWidgets('one notebook, one audio; one recording at a time across panes', (tester) async {
    final audio = FakeAudio();
    final (s, physics, chemistry) = await pumpWorkspace(tester, audio: audio.backends);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    final buttons = tester.widgetList<AudioBarButton>(find.byType(AudioBarButton)).toList();
    expect(buttons[0].audio, same(buttons[1].audio));
    final physicsAudio = buttons[0].audio;

    // A recording saved in one pane lists in both.
    var notified = 0;
    physicsAudio.addListener(() => notified++);
    await tester.runAsync(() async {
      expect(await physicsAudio.recorder.start(), isTrue);
    });
    // The other notebook can't record meanwhile.
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    final chemistryAudio = tester
        .widgetList<AudioBarButton>(find.byType(AudioBarButton))
        .last
        .audio;
    expect(chemistryAudio, isNot(same(physicsAudio)));
    await tester.runAsync(() async {
      expect(await chemistryAudio.recorder.start(), isFalse);
    });
    expect(chemistryAudio.recorder.lastError, contains('Already recording in “Physics”'));
    expect(chemistryAudio.recorder.state, RecorderState.idle);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await physicsAudio.recorder.stop();
    });
    await tester.pump();
    expect(physicsAudio.recordings, hasLength(1));
    expect(notified, greaterThan(0));
    // Now it can.
    await tester.runAsync(() async {
      expect(await chemistryAudio.recorder.start(), isTrue);
      await chemistryAudio.recorder.stop();
    });
    await closeEditor(tester);
  });

  testWidgets('turned to portrait, the second pane is parked: editor, undo, recording live on', (
    tester,
  ) async {
    final audio = FakeAudio();
    final (s, physics, chemistry) = await pumpWorkspace(tester, audio: audio.backends);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    final secondEditor = tester.state(find.byType(EditorScreen).last);
    await drawIn(tester, 1);
    final right = sessionsOf(tester)[1];
    final recording = tester.widgetList<AudioBarButton>(find.byType(AudioBarButton)).last.audio;
    await tester.runAsync(() async {
      expect(await recording.recorder.start(), isTrue);
    });

    tester.view.physicalSize = const Size(800, 1280);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.byType(EditorScreen, skipOffstage: false), findsNWidgets(2));
    expect(recording.recorder.state, RecorderState.recording);
    expect(right.undo.canUndo, isTrue);
    expect(
      s.incomingFiles.targets.active?.notebookId,
      physics.id,
      reason: 'files go to the shown pane',
    );
    expect(find.byTooltip('Close this pane'), findsNothing);
    // The pane on screen says the parked one records.
    expect(find.text('Recording in “Chemistry”'), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(find.text('Recording in “Chemistry”'), findsNothing, reason: 'both shown again');
    expect(find.byType(EditorScreen), findsNWidgets(2));
    expect(tester.state(find.byType(EditorScreen).last), same(secondEditor));
    expect(sessionsOf(tester)[1], same(right));
    expect(right.undo.canUndo, isTrue);
    expect(recording.recorder.state, RecorderState.recording);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await recording.recorder.stop();
    });
    expect(recording.recordings, hasLength(1));
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  group('the second pane\'s notebook deleted on another device', () {
    Future<void> deleteRemotely(WidgetTester tester, AppServices s, Notebook notebook) async {
      s.notebooks.delete(notebook.id);
      s.sync.debugAnnounce(RemoteChanges()..notebooks = true);
      await tester.pumpAndSettle();
    }

    testWidgets('closes the pane, says so in the first, keeps the first pane\'s dialog', (
      tester,
    ) async {
      final (s, physics, chemistry) = await pumpWorkspace(tester);
      s.openNotebooks.openSplit(chemistry.id);
      await tester.pumpAndSettle();
      // A dialog opened from the first pane (its title shows in the tabs).
      await tester.tap(find.byTooltip('Undo (Ctrl+Z)').first);
      unawaited(
        showTextPrompt(tester.element(find.byType(EditorScreen).first), title: 'Rename notebook'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await deleteRemotely(tester, s, chemistry);
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(s.openNotebooks.splitId, isNull);
      expect(find.byType(TextField), findsOneWidget, reason: 'opened from the other pane');
      expect(find.text('“Chemistry” was deleted on another device'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(s.openNotebooks.activeId, physics.id);
      expect(tester.takeException(), isNull);
      await closeEditor(tester);
    });

    testWidgets('closes the dialogs it opened, also while parked', (tester) async {
      final (s, physics, chemistry) = await pumpWorkspace(tester);
      s.openNotebooks.openSplit(chemistry.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TitleButton).last); // Rename Chemistry (second pane)…
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      tester.view.physicalSize = const Size(800, 1280); // Parks the pane.
      await tester.pumpAndSettle();

      await deleteRemotely(tester, s, chemistry);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditorScreen, skipOffstage: false), findsOneWidget);
      expect(find.text('“Chemistry” was deleted on another device'), findsOneWidget);
      expect(s.openNotebooks.activeId, physics.id);
      expect(tester.takeException(), isNull);
      await closeEditor(tester);
    });
  });

  testWidgets('a PDF dropped on a pane goes to that pane\'s notebook', (tester) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    await drawIn(tester, 0); // Physics in use.
    expect(s.incomingFiles.targets.active?.notebookId, physics.id);
    String? target;
    s.incomingFiles.handler = (_) => target = s.incomingFiles.targets.active?.notebookId;
    final drop = tester.widgetList<DropTarget>(find.byType(DropTarget)).last;
    drop.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile('/tmp/Lecture 5.pdf', name: 'Lecture 5.pdf')],
        localPosition: const Offset(100, 100),
        globalPosition: const Offset(900, 100),
      ),
    );
    await tester.pump();
    expect(target, chemistry.id);
    await closeEditor(tester);
  });

  testWidgets('a second pane opens in reading on a page with content, decided at once', (
    tester,
  ) async {
    FingerReading.debugEnabled = true;
    // Surfaces read in the background answer later (on a device: another
    // isolate, busy loading the first pane's pages).
    final later = <Completer<void>>[];
    final (s, _, chemistry) = await pumpWorkspace(
      tester,
      reader: (strokes) => _LaterReader(strokes, later),
    );
    s.strokes.save([inkStroke(s.pages.pagesOf(chemistry.id).first.id)]);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pump();
    final right = sessionsOf(tester)[1];
    expect(right.tools.reading, isTrue, reason: 'decided on open, from what the page holds');
    for (final c in [...later]) {
      c.complete();
    }
    await tester.pumpAndSettle();
    expect(right.tools.reading, isTrue);
    await closeEditor(tester);
  });

  testWidgets('a parked pane going back to reading offers no tip nobody sees', (tester) async {
    FingerReading.debugEnabled = true;
    final (s, _, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    await drawIn(tester, 1);
    final right = sessionsOf(tester)[1];
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget, reason: 'parked');
    await tester.pump(FingerReading.idle + const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(right.tools.reading, isTrue);
    expect(s.settings.seenTips, isNot(contains(EditorTip.reading.name)));
    // Shown again: the tip.
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.text('Reading: one finger scrolls; tap the pen to write'), findsOneWidget);
    await closeEditor(tester);
  });

  testWidgets('a parked pane that records: Show swaps it in, Stop stops it', (tester) async {
    final audio = FakeAudio();
    final (s, physics, chemistry) = await pumpWorkspace(tester, audio: audio.backends);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    final recording = tester.widgetList<AudioBarButton>(find.byType(AudioBarButton)).last.audio;
    await tester.runAsync(() async {
      expect(await recording.recorder.start(), isTrue);
    });
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pumpAndSettle();
    expect(find.text('Recording in “Chemistry”'), findsOneWidget);

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(s.openNotebooks.activeId, chemistry.id, reason: 'Chemistry is on screen now');
    expect(find.text('Recording in “Chemistry”'), findsNothing);
    // Physics is parked now, and records nothing: no notice.
    expect(find.byKey(const ValueKey('parked-recording')), findsNothing);

    // Back, then Stop from the notice.
    s.openNotebooks.swapSplit();
    await tester.pumpAndSettle();
    expect(find.text('Recording in “Chemistry”'), findsOneWidget);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.tap(find.text('Stop'));
    await pumpUntil(tester, () => recording.recorder.state == RecorderState.idle);
    await tester.pumpAndSettle();
    expect(recording.recorder.state, RecorderState.idle);
    expect(find.byKey(const ValueKey('parked-recording')), findsNothing);
    expect(s.openNotebooks.activeId, physics.id);
    await closeEditor(tester);
  });

  testWidgets('a parked pane is named in a chip; Show swaps it in', (tester) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('parked-pane')), findsNothing, reason: 'both shown');

    tester.view.physicalSize = const Size(800, 1280);
    await tester.pumpAndSettle();
    expect(find.text('“Chemistry” in split view'), findsOneWidget);
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(s.openNotebooks.activeId, chemistry.id);
    expect(find.text('“Physics” in split view'), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('parked-pane')), findsNothing);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });
}

/// A reader answering only once the test completes the completers it adds
/// to [later] (as a background isolate answers later).
class _LaterReader implements StrokeReader {
  _LaterReader(this.inner, this.later);

  final StrokeReader inner;
  final List<Completer<void>> later;

  Future<T> _later<T>(FutureOr<T> Function() answer) {
    final c = Completer<void>();
    later.add(c);
    return c.future.then((_) => answer());
  }

  @override
  Future<ChunkLoad> read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) =>
      _later(() => inner.read(surfaceId, range, skip: skip));

  @override
  Future<Map<ChunkKey, ChunkDigest>> chunkDigests(String surfaceId, ChunkRange range) =>
      _later(() => inner.chunkDigests(surfaceId, range));

  @override
  Future<Map<ChunkKey, int>> chunkDensity(String surfaceId) =>
      _later(() => inner.chunkDensity(surfaceId));

  @override
  Future<Rect?> contentBounds(String surfaceId) => _later(() => inner.contentBounds(surfaceId));
}
