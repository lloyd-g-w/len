import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_session.dart';
import 'package:len/features/editor/zoom/zoom_box.dart';
import 'package:len/features/editor/zoom/zoom_frame.dart';
import 'package:len/features/editor/zoom/zoom_window.dart';
import 'package:len/ui/app_theme.dart';

import 'document_editor_test.dart' show pumpEditor, inkOf, closeEditor;

EditorSession _session(WidgetTester tester) =>
    tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;

/// Opens the zoom window with its shortcut.
Future<ZoomWindow> _open(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
  await tester.pumpAndSettle();
  return _session(tester).zoomWindow;
}

/// A short stylus stroke in the box's paper, from [at] (a fraction of its
/// size) [length] pixels to the right.
Future<void> _write(WidgetTester tester, Offset at, {double length = 40}) async {
  final box = tester.getRect(find.byType(ZoomBox));
  // The rail (✕, ↵) sits at the box's right; the paper is left of it.
  final paper = box.topLeft & _session(tester).zoomWindow.box;
  final start = Offset(paper.left + paper.width * at.dx, paper.bottom - paper.height * at.dy);
  final pen = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 8; i++) {
    await pen.moveTo(start + Offset(length * i / 8, i.isEven ? 6 : -6));
  }
  await pen.up();
  await tester.pump();
}

void main() {
  testWidgets('M opens the window below the ink on the page, and closes it', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final zoom = await _open(tester);
    expect(zoom.isOpen, isTrue);
    expect(find.byType(ZoomBox), findsOneWidget);
    final page = s.pages.pagesOf(nb.id).first;
    final wave = inkOf(s, page).single.bounds;
    final frame = zoom.frameRect!;
    expect(zoom.frame!.surfaceId, page.id);
    expect(frame.top, greaterThan(wave.bottom));
    // Lines start where the ink does.
    expect(frame.left, closeTo(wave.left, 1));
    // The frame shows above the box.
    final box = tester.getRect(find.byType(ZoomBox));
    expect(zoom.host.onScreen(page.id, frame)!.bottom, lessThanOrEqualTo(box.top));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(zoom.isOpen, isFalse);
    expect(find.byType(ZoomBox), findsNothing);
    await closeEditor(tester);
  });

  testWidgets('the ⋯ menu toggles the window; ✕ closes it', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zoom window'));
    await tester.pumpAndSettle();
    final zoom = _session(tester).zoomWindow;
    expect(zoom.isOpen, isTrue);
    await tester.tap(find.byTooltip('Close zoom window'));
    await tester.pumpAndSettle();
    expect(zoom.isOpen, isFalse);
    await closeEditor(tester);
  });

  testWidgets('writing in the box writes small into the frame, undoably', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final zoom = await _open(tester);
    final page = s.pages.pagesOf(nb.id).first;
    final frame = zoom.frameRect!;
    final scale = zoom.frame!.scale;
    await _write(tester, const Offset(0.1, 0.5), length: 80);
    expect(zoom.blocksPage.value, isTrue, reason: 'the hand on the page is a palm');
    await tester.pumpAndSettle();
    expect(zoom.blocksPage.value, isFalse);
    final ink = inkOf(s, page).where((st) => st.id != 'w1').toList();
    expect(ink, hasLength(1));
    final stroke = ink.single.bounds;
    expect(frame.contains(stroke.center), isTrue);
    // 80 px written in the box are 80 / scale units on the page (the pen
    // keeps its width on the page: the box shows it magnified).
    final xs = ink.single.points.map((p) => p.x);
    expect(xs.reduce(math.max) - xs.reduce(math.min), closeTo(80 / scale, 2));
    expect(zoom.frameRect, frame, reason: 'ink outside the advance zone leaves the frame be');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(inkOf(s, page).where((st) => st.id != 'w1'), isEmpty);
    await closeEditor(tester);
  });

  testWidgets('ink at the right edge advances the frame at once', (tester) async {
    await pumpEditor(tester);
    final zoom = await _open(tester);
    final before = zoom.frame!.origin;
    final scale = zoom.frame!.scale;
    await _write(tester, const Offset(0.88, 0.5), length: 40);
    await tester.pump(); // No pause.
    await tester.pumpAndSettle();
    final after = zoom.frame!.origin;
    expect(after.dy, before.dy);
    expect(after.dx, greaterThan(before.dx));
    // The last ink now sits a quarter into the frame.
    final rect = zoom.frameRect!;
    final inkRight = before.dx + (0.88 * zoom.box.width + 40) / scale;
    expect(inkRight - rect.left, closeTo(rect.width * ZoomRules.keep, rect.width * 0.05));
    await closeEditor(tester);
  });

  testWidgets('ink in the zone advances after a pause, unless the pen comes back', (tester) async {
    await pumpEditor(tester);
    final zoom = await _open(tester);
    final before = zoom.frame!.origin;
    await _write(tester, const Offset(0.72, 0.5), length: 20);
    await tester.pump(ZoomWindow.pause ~/ 2);
    expect(zoom.frame!.origin, before);
    // The pen comes back in time (outside the zone): no advance.
    await _write(tester, const Offset(0.4, 0.5), length: 10);
    await tester.pump(ZoomWindow.pause * 2);
    await tester.pumpAndSettle();
    expect(zoom.frame!.origin, before);
    // Lifted in the zone and left: the frame moves on.
    await _write(tester, const Offset(0.72, 0.5), length: 20);
    await tester.pump(ZoomWindow.pause);
    await tester.pumpAndSettle();
    expect(zoom.frame!.origin.dx, greaterThan(before.dx));
    await closeEditor(tester);
  });

  testWidgets('↵ goes to the start of the next ruled line', (tester) async {
    await pumpEditor(tester);
    final zoom = await _open(tester);
    final before = zoom.frame!.origin;
    final pitch = zoom.host.pitchOf(zoom.frame!.surfaceId)!;
    await _write(tester, const Offset(0.88, 0.5), length: 40);
    await tester.pumpAndSettle();
    expect(zoom.frame!.origin.dx, greaterThan(before.dx));
    await tester.tap(find.byTooltip('Next line'));
    await tester.pumpAndSettle();
    expect(zoom.frame!.origin.dx, closeTo(before.dx, 0.01));
    expect(zoom.frame!.origin.dy, closeTo(before.dy + pitch, 0.01));
    await closeEditor(tester);
  });

  testWidgets('the frame moves by dragging and sizes with its handle', (tester) async {
    await pumpEditor(tester);
    final zoom = await _open(tester);
    final id = zoom.frame!.surfaceId;
    var screen = zoom.host.onScreen(id, zoom.frameRect!)!;
    final mainScale = zoom.host.main.scale;
    final before = zoom.frame!.origin;
    await tester.dragFrom(screen.center, const Offset(-30, -40));
    await tester.pumpAndSettle();
    final moved = zoom.frame!.origin;
    // The drag starts past the touch slop; most of it moves the frame.
    expect(moved.dy, lessThan(before.dy - 20 / mainScale));
    expect(moved.dx, lessThan(before.dx - 10 / mainScale));

    screen = zoom.host.onScreen(id, zoom.frameRect!)!;
    final width = zoom.frameRect!.width;
    await tester.dragFrom(screen.bottomRight, Offset(screen.width * 0.5, screen.height * 0.5));
    await tester.pumpAndSettle();
    expect(zoom.frameRect!.width, greaterThan(width * 1.2));
    expect(zoom.frame!.origin, moved, reason: 'sizing keeps the top-left corner');
    await closeEditor(tester);
  });

  testWidgets('past the bottom of a page the frame goes on to the next, adding one at the end', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester);
    final zoom = await _open(tester);
    final session = _session(tester);
    final pages = s.pages.pagesOf(nb.id);
    // Down to the bottom of the first page: ↵ turns to the second.
    final down = zoom.host.boundsOf(pages[0].id)!.bottom - zoom.frameRect!.bottom;
    zoom.dragBy(Offset(0, down * zoom.host.main.scale));
    zoom.dragEnd();
    await tester.pumpAndSettle();
    expect(zoom.frame!.surfaceId, pages[0].id);
    await tester.tap(find.byTooltip('Next line'));
    await tester.pumpAndSettle();
    expect(zoom.frame!.surfaceId, pages[1].id);
    expect(session.doc!.activePageData.id, pages[1].id);
    expect(zoom.frameRect!.top, lessThan(zoom.host.boundsOf(pages[1].id)!.height * 0.1));
    // Writing goes there.
    await _write(tester, const Offset(0.1, 0.5));
    await tester.pumpAndSettle();
    expect(inkOf(s, pages[1]).where((st) => st.id != 'w2'), hasLength(1));

    // The bottom of the last page: ↵ adds a page like it.
    zoom.dragBy(const Offset(0, 1e5));
    zoom.dragEnd();
    await tester.pumpAndSettle();
    expect(zoom.frame!.surfaceId, pages[2].id);
    await tester.tap(find.byTooltip('Next line'));
    await tester.pumpAndSettle();
    final now = s.pages.pagesOf(nb.id);
    expect(now, hasLength(4));
    expect(zoom.frame!.surfaceId, now[3].id);
    await closeEditor(tester);
  });

  testWidgets('on a canvas the box writes where the frame is', (tester) async {
    tester.view
      ..physicalSize = const Size(900, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.dotted,
      coverColor: 0,
    );
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
    final zoom = await _open(tester);
    expect(zoom.frame!.surfaceId, nb.id);
    final frame = zoom.frameRect!;
    await _write(tester, const Offset(0.2, 0.5));
    await tester.pumpAndSettle();
    final ink = SurfaceCopier(services.strokes).loadAll(nb.id);
    expect(ink, hasLength(1));
    expect(frame.contains(ink.single.bounds.center), isTrue);
    // ↵ goes down a line, back to where lines start.
    await tester.tap(find.byTooltip('Next line'));
    await tester.pumpAndSettle();
    expect(zoom.frameRect!.top, greaterThan(frame.top));
    expect(zoom.frameRect!.left, frame.left);
    await closeEditor(tester);
  });

  testWidgets('a palm on the page while the pen writes in the box neither draws nor scrolls', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester);
    final zoom = await _open(tester);
    final session = _session(tester);
    final page = s.pages.pagesOf(nb.id).first;
    final view = session.doc!.viewport;
    final offset = view.offset;
    // The palm lands first (a finger draws until the pen shows up)…
    final palm = await tester.startGesture(const Offset(400, 700));
    await palm.moveBy(const Offset(20, 10));
    await tester.pump();
    // …then the pen writes in the box while the palm slides.
    final box = tester.getRect(find.byType(ZoomBox));
    final pen = await tester.startGesture(
      box.topLeft + Offset(60, box.height / 2),
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 1; i <= 6; i++) {
      await pen.moveBy(const Offset(8, 3));
      await palm.moveBy(const Offset(0, -30));
    }
    await pen.up();
    await palm.up();
    await tester.pumpAndSettle();
    final ink = inkOf(s, page).where((st) => st.id != 'w1').toList();
    expect(ink, hasLength(1), reason: 'only the pen wrote');
    expect(zoom.frameRect!.contains(ink.single.bounds.center), isTrue);
    expect(view.offset, offset);
    await closeEditor(tester);
  });
}
