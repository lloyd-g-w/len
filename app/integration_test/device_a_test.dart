// End-to-end, part 1 of 3 (device A, first launch). Run by tool/e2e.sh,
// which then relaunches the app on this data (relaunch_test.dart) and
// syncs a second device (device_b_test.dart).
import 'dart:convert';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/notebook_card.dart';

import 'support/e2e.dart';
import 'support/flows.dart';

void main() {
  initE2E();

  testWidgets('device A: write a notebook, a canvas, export, search, trash, sync', (tester) async {
    final s = await launchApp(tester);
    expect(find.text('New notebook'), findsWidgets, reason: 'first launch: empty library');
    expect(s.notebooks.list(), isEmpty);
    await snapshot(tester, 'a01_empty_library');

    // --- A paged notebook -------------------------------------------------
    await createNotebook(tester, 'Field notes');
    final nb = s.notebooks.list().single;
    expect(find.byType(EditorScreen), findsOneWidget);
    List<String> pageIds() => s.pages.pagesOf(nb.id).map((p) => p.id).toList();
    String surfaces() => pageIds().map((id) => "'$id'").join(',');
    int strokes() => count(s, 'strokes', 'surface_id IN (${surfaces()})');

    final c = tester.getCenter(find.byType(EditorScreen));
    await mouseStroke(tester, wave(c + const Offset(-150, -120)));
    await stylusStroke(tester, wave(c + const Offset(-150, -60)));
    await stylusStroke(tester, wave(c + const Offset(-150, 0), amp: 30));
    expect(strokes(), 3);

    // Undo / redo (keyboard and buttons).
    await press(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(strokes(), 2);
    await tapTooltip(tester, 'Undo (Ctrl+Z)');
    expect(strokes(), 1);
    await press(tester, LogicalKeyboardKey.keyZ, ctrl: true, shift: true);
    await tapTooltip(tester, 'Redo (Ctrl+Shift+Z)');
    expect(strokes(), 3);
    await snapshot(tester, 'a02_strokes');

    // Lasso: circle the first stroke and drag it down.
    final before = strokeStarts(s, pageIds().first);
    await press(tester, LogicalKeyboardKey.keyL);
    final lassoAt = c + const Offset(-50, -120);
    await mouseStroke(tester, [
      lassoAt + const Offset(-130, -30),
      lassoAt + const Offset(130, -30),
      lassoAt + const Offset(130, 25),
      lassoAt + const Offset(-130, 25),
      lassoAt + const Offset(-130, -25),
    ]);
    expect(find.byTooltip('Delete (Del)'), findsOneWidget, reason: 'the selection menu');
    await mouseStroke(tester, [for (var i = 0; i <= 10; i++) lassoAt + Offset(0, i * 20.0)]);
    await press(tester, LogicalKeyboardKey.escape);
    soft(find.byTooltip('Delete (Del)').evaluate().isEmpty, 'Escape deselects the moved ink');
    if (find.byTooltip('Delete (Del)').evaluate().isNotEmpty) {
      await press(tester, LogicalKeyboardKey.escape);
    }
    expect(strokes(), 3);
    final after = strokeStarts(s, pageIds().first);
    final moved = after.keys.where((id) => !before.containsKey(id)).toList();
    final gone = before.keys.where((id) => !after.containsKey(id)).toList();
    expect(moved, hasLength(1), reason: 'moving = one stroke replaced');
    expect(after[moved.single]!.dy - before[gone.single]!.dy, greaterThan(100));

    // A text box with formatting.
    await press(tester, LogicalKeyboardKey.keyT);
    await mouseStroke(tester, [c + const Offset(-150, 120)]);
    final field = find.byKey(const ValueKey('text-box-field'));
    await pumpUntil(tester, field);
    await tester.enterText(field, 'Meeting about photosynthesis');
    await press(tester, LogicalKeyboardKey.keyA, ctrl: true);
    await press(tester, LogicalKeyboardKey.keyB, ctrl: true);
    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.escape);
    final box = s.database.db.select(
      "SELECT data FROM elements WHERE deleted = 0 AND type = 'text' AND surface_id IN (${surfaces()})",
    );
    expect(box, hasLength(1));
    final data = TextData.fromJson(
      jsonDecode(box.single['data'] as String) as Map<String, Object?>,
    );
    expect(data.text, 'Meeting about photosynthesis');
    expect(data.spans.single.style.bold, isTrue);

    // An image from a file (the real decoder, blob store and placement).
    final photo = await writeTestPng('${E2E.out}/photo.png');
    files.openQueue.add([photo]);
    await tapTooltip(tester, 'Insert');
    await tapText(tester, 'Image…');
    await waitFor(
      tester,
      () => count(s, 'elements', "type = 'image' AND surface_id IN (${surfaces()})") == 1,
      reason: 'the image element',
    );
    expect(find.byTooltip('Delete (Del)'), findsOneWidget, reason: 'the new image is selected');
    await press(tester, LogicalKeyboardKey.escape);
    soft(find.byTooltip('Delete (Del)').evaluate().isEmpty, 'Escape deselects the new image');
    if (find.byTooltip('Delete (Del)').evaluate().isNotEmpty) {
      await press(tester, LogicalKeyboardKey.escape);
    }
    expect(s.database.db.select('SELECT sha256 FROM blobs'), hasLength(1));
    await snapshot(tester, 'a03_page_one');

    // More pages, then scroll down to the third.
    await addPageAfter(tester);
    await addPageAfter(tester);
    expect(pageIds(), hasLength(3));
    await press(tester, LogicalKeyboardKey.keyP);
    await stylusStroke(tester, wave(c + const Offset(-100, 0)));
    expect(strokes(), 4);
    PagedDocumentView view() => tester.widget<PagedDocumentView>(find.byType(PagedDocumentView));
    expect(view().controller.currentPage, 2);
    await wheel(tester, c, const Offset(0, -400), times: 12);
    expect(view().controller.currentPage, 0, reason: 'scrolled back to the top');
    await wheel(tester, c, const Offset(0, 400), times: 12);
    expect(view().controller.currentPage, greaterThan(0));
    await press(tester, LogicalKeyboardKey.end);
    expect(view().controller.currentPage, 2);
    await snapshot(tester, 'a04_page_three');

    // Export the whole notebook as PDF to a real file.
    final pdf = '${E2E.out}/field-notes.pdf';
    if (File(pdf).existsSync()) File(pdf).deleteSync();
    files.saveQueue.add(pdf);
    await press(tester, LogicalKeyboardKey.keyE, ctrl: true);
    await pumpUntil(tester, find.widgetWithText(FilledButton, 'Export'));
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await waitFor(tester, () => File(pdf).existsSync(), reason: 'the PDF file');
    await settle(tester);
    final bytes = File(pdf).readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length, 3);
    soft(String.fromCharCodes(bytes).contains('/Image'), 'the PDF embeds the image');
    expect(files.shown, contains('save'));

    // Back to the library: the editor remembers page 3.
    await tapTooltip(tester, 'Back');
    await pumpUntil(tester, find.byType(NotebookCard));
    expect(s.settings.editorView(nb.id), isNotNull);

    // --- An infinite canvas -------------------------------------------------
    await createNotebook(tester, 'Big board', canvas: true);
    final board = s.notebooks.list().firstWhere((n) => n.title == 'Big board');
    await stylusStroke(tester, wave(c + const Offset(-100, 0)));
    // Pan far away (about 6000 px right and down) and draw again.
    await wheel(tester, c, const Offset(400, 300), times: 15);
    await stylusStroke(tester, wave(c + const Offset(-100, 0)));
    final rows = s.database.db.select(
      'SELECT points FROM strokes WHERE deleted = 0 AND surface_id = ?',
      [board.id],
    );
    expect(rows, hasLength(2));
    final chunks = s.database.db.select(
      'SELECT DISTINCT cx, cy FROM stroke_chunks WHERE surface_id = ?',
      [board.id],
    );
    expect(chunks.length, greaterThanOrEqualTo(2), reason: 'far apart: different chunks');
    await snapshot(tester, 'a05_canvas');
    await tapTooltip(tester, 'Back');
    await pumpUntil(tester, find.byType(NotebookCard));

    // --- Search -------------------------------------------------------------
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'photosynthesis');
    await pumpUntil(tester, find.textContaining('Field notes', findRichText: true));
    await settle(tester);
    await snapshot(tester, 'a06_search');
    await tester.enterText(find.widgetWithText(TextField, 'Search'), '');
    await settle(tester);

    // --- Trash and restore -----------------------------------------------
    await notebookMenu(tester, 'Big board');
    await tapText(tester, 'Move to trash');
    expect(s.notebooks.trashed().single.title, 'Big board');
    await tapText(tester, 'Trash');
    await notebookMenu(tester, 'Big board');
    await tapText(tester, 'Restore');
    expect(s.notebooks.trashed(), isEmpty);
    await tapText(tester, 'Library');

    // --- Sync -----------------------------------------------------------------
    if (E2E.server.isNotEmpty) {
      await connectSync(tester, s);
      await syncNow(tester, s); // Nothing left behind.
      final server = await serverRecords();
      List<Map<String, dynamic>> live(String c) =>
          (server[c] ?? const []).where((r) => r['deleted'] != true).toList();
      expect(live('notebooks').map((r) => (r['data'] as Map)['title']).toSet(), {
        'Field notes',
        'Big board',
      });
      expect(live('pages'), hasLength(3));
      expect(live('strokes'), hasLength(count(s, 'strokes')));
      expect(live('elements'), hasLength(2));
      for (final row in s.database.db.select('SELECT sha256 FROM blobs')) {
        expect(await serverHasBlob(row['sha256'] as String), isTrue, reason: 'blob uploaded');
      }
    }

    // Leave a text box half-typed on page 2 and close the window: the
    // relaunch must find both (relaunch_test).
    await tester.tap(
      find.ancestor(of: find.text('Field notes'), matching: find.byType(NotebookCard)),
    );
    await pumpUntil(tester, find.byType(PagedDocumentView));
    await settle(tester);
    expect(view().controller.currentPage, 2, reason: 'reopens where it was left');
    await press(tester, LogicalKeyboardKey.pageUp);
    expect(view().controller.currentPage, 1);
    await press(tester, LogicalKeyboardKey.keyT);
    await mouseStroke(tester, [c + const Offset(-200, 0)]);
    await pumpUntil(tester, field);
    await tester.enterText(field, 'Draft on page two');
    await tester.pump();
    await snapshot(tester, 'a07_closing');
    await requestWindowClose(tester);

    await closeApp(tester);
    expectCleanLog();
  });
}

/// The first point of each live stroke on [surface], by id.
Map<String, Offset> strokeStarts(AppServices s, String surface) => {
  for (final stroke in s.strokes.loadChunks(surface, [
    for (var x = -1; x <= 2; x++)
      for (var y = -1; y <= 2; y++) (x: x, y: y),
  ]))
    stroke.id: stroke.points.first.offset,
};

/// Writes a 400×300 PNG with coloured bands (drawn and encoded by the engine).
Future<String> writeTestPng(String path) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final colors = [const Color(0xFF3B5BDB), const Color(0xFFF08C00), const Color(0xFF2F9E44)];
  for (var i = 0; i < 3; i++) {
    canvas.drawRect(Rect.fromLTWH(0, i * 100.0, 400, 100), Paint()..color = colors[i]);
  }
  final image = await recorder.endRecording().toImage(400, 300);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
  return path;
}
