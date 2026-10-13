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
      shared: services.recognition.indexer.shared,
      language: () => 'en-US',
      idleDelay: Duration.zero,
      pauseBetweenLines: Duration.zero,
    );
    addTearDown(indexer.dispose);
    await indexer.indexSurface(ideas.id);

    await pumpEditorFor(tester, services, ideas);
    final viewport = tester.widget<CanvasView>(find.byType(CanvasView)).navigation.viewport;
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search in notebook'));
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
}
