import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/search/editor/editor_search_bar.dart';
import 'package:len/ink/recognition/handwriting_indexer.dart';

import 'handwriting_clustering_test.dart' show twoLines;
import 'handwriting_index_test.dart' show words;
import 'search_ui_test.dart' show pumpEditorFor, typeSearch;
import 'support/fake_recognizer.dart';

void main() {
  testWidgets('editor search finds handwriting and highlights the matched word', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final ideas = services.notebooks.create(
      title: 'Ideas',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    // Far from the start, so revealing it has to pan.
    services.strokes.save([
      for (final s in twoLines(ideas.id))
        s.withPoints([for (final p in s.points) StrokePoint(p.x + 3000, p.y + 2000, p.pressure)]),
    ]);
    final indexer = HandwritingIndexer(
      services.database,
      recognizer: FakeRecognizer(words: {...words}),
      language: () => 'en-US',
      idleDelay: Duration.zero,
      pauseBetweenLines: Duration.zero,
    );
    addTearDown(indexer.dispose);
    await indexer.indexSurface(ideas.id);

    await pumpEditorFor(tester, services, ideas);
    final viewport = tester.widget<CanvasView>(find.byType(CanvasView)).navigation.viewport;
    await tester.tap(find.byTooltip('Search (Ctrl+F)'));
    await tester.pumpAndSettle();
    await typeSearch(tester, 'gamma');
    await tester.tap(find.byTooltip('Next (Enter)'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);

    final controller = tester.widget<EditorSearchBar>(find.byType(EditorSearchBar)).controller;
    final rects = controller.rectsOf(controller.currentMatch!);
    expect(rects.single.rect.left, closeTo(3000 + 269 - 2, 0.2), reason: 'just "gamma"');
    expect(viewport.visibleWorld.contains(rects.single.rect.center), isTrue);
  });

  test('the migration queues surfaces drawn before handwriting search', () {
    final dir = Directory.systemTemp.createTempSync('len_ink_mig_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/len.db';
    var db = AppDatabase.open(path);
    for (final t in ['ink_text', 'ink_text_queue']) {
      db.db.execute('DROP TABLE $t'); // Drops the triggers on them too.
    }
    for (final t in ['ink_text_strokes_ai', 'ink_text_strokes_au', 'ink_text_strokes_ad']) {
      db.db.execute('DROP TRIGGER $t');
    }
    db.db.execute(
      'INSERT INTO strokes (id, surface_id, tool, color, width, points, created_at, updated_at, '
      "device_id) VALUES ('s1', 'old-page', 'pen', 0, 2, x'00', 1, 1, 'd')",
    );
    db.db.execute('PRAGMA user_version = ${AppDatabase.versionBeforeInkText}');
    db.close();

    db = AppDatabase.open(path);
    addTearDown(db.close);
    final queued = db.db.select('SELECT surface_id FROM ink_text_queue');
    expect(queued.map((r) => r['surface_id']), ['old-page']);
  });
}
