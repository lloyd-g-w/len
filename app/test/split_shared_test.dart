import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/audio/recording_controller.dart';
import 'package:len/features/audio/ui/audio_bar_button.dart';
import 'package:len/features/editor/chrome/editor_top_bar.dart';
import 'package:len/features/editor/chrome/title_button.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_session.dart';
import 'package:len/ink/surface_model.dart';

import 'document_editor_test.dart' show closeEditor;
import 'split_view_test.dart';
import 'support/fake_audio.dart';

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
        .update((n) => n.copyWith(paper: PaperStyle.dotted, paperColor: PaperColor.dark));
    await tester.pump();
    final papers = tester.widgetList<EditorCanvas>(find.byType(EditorCanvas));
    expect(papers.map((c) => (c.paper, c.paperColor)), [
      (PaperStyle.dotted, PaperColor.dark),
      (PaperStyle.dotted, PaperColor.dark),
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
}
