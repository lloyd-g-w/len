import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/data/surface_stats.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text_data.dart';
import 'package:len/features/editor/document/page_actions.dart';
import 'package:len/features/library/thumbnails/thumbnail_renderer.dart';

import 'content_tools_ui_test.dart' show key, mouseDrag;
import 'data_test.dart' show FakeClock;
import 'document_editor_test.dart' show closeEditor, inkOf, pumpEditor;

/// The lasso, shape, text and laser tools inside paged documents (several
/// page surfaces seen through one viewport), and elements in the notebook
/// operations that came with documents and the library.

SurfaceElement textBox(String id, String surface, {Offset at = const Offset(100, 100)}) =>
    SurfaceElement(
      id: id,
      surfaceId: surface,
      type: ElementType.text.name,
      rect: Rect.fromLTWH(at.dx, at.dy, 300, 40),
      z: 1,
      createdAt: 1,
      data: const TextData(text: 'Hello').toJson(),
    );

List<SurfaceElement> elementsOf(AppServices s, String surface) =>
    SurfaceCopier(s.strokes, elements: s.elements).loadAllElements(surface);

Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(k);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('continuous scrolling: text and lasso work on the page under the pointer, '
      'with notebook-wide undo', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final pages = s.pages.pagesOf(nb.id);

    // A text box on page 2 (visible below page 1), in page coordinates.
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 1150)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    expect(field, findsOneWidget);
    // The editor sits where the pointer was, not where page 1 would put it.
    expect(tester.getTopLeft(field).dx, closeTo(300, 2));
    expect(tester.getCenter(field).dy, closeTo(1150, 6));
    await tester.enterText(field, 'Page two');
    await tester.tap(find.byTooltip('Done (Esc)'));
    await tester.pumpAndSettle();
    final text = elementsOf(s, pages[1].id).single;
    expect(TextData.fromJson(text.data).text, 'Page two');
    expect(pages[1].bounds.contains(text.rect.topLeft), isTrue);
    expect(text.rect.top, lessThan(500)); // Page-local, not document space.
    expect(elementsOf(s, pages[0].id), isEmpty);

    // Lasso the wave on page 1 and move it down.
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [
      Offset(170, 224),
      Offset(580, 224),
      Offset(580, 324),
      Offset(170, 324),
      Offset(170, 234),
    ]);
    expect(find.byTooltip('Delete (Del)'), findsOneWidget);
    await mouseDrag(tester, const [Offset(360, 276), Offset(360, 334), Offset(360, 376)]);
    final moved = inkOf(s, pages[0]).single;
    expect(moved.id, isNot('w1'));
    expect(moved.points.first.y, greaterThan(250));
    expect(inkOf(s, pages[1]).single.id, 'w2'); // Other pages untouched.

    // Undo spans pages: the move on page 1, then the text on page 2.
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(inkOf(s, pages[0]).single.id, 'w1');
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(elementsOf(s, pages[1].id), isEmpty);
    await tester.tap(find.byTooltip('Redo (Ctrl+Shift+Z)'));
    await tester.pump();
    expect(elementsOf(s, pages[1].id), hasLength(1));
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('a selection keeps its page when grabbed outside it', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final pages = s.pages.pagesOf(nb.id);
    // Page 1 starts below the top bar and toolbar (~132 px).
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [
      Offset(170, 224),
      Offset(580, 224),
      Offset(580, 324),
      Offset(170, 324),
      Offset(170, 234),
    ]);
    // Drag it down over the bottom edge of page 1 (~949 px), then grab it
    // below that edge: it is still page 1's selection.
    await mouseDrag(tester, const [Offset(360, 276), Offset(360, 684), Offset(360, 946)]);
    expect(find.byTooltip('Delete (Del)'), findsOneWidget);
    await mouseDrag(tester, const [Offset(360, 964), Offset(360, 934), Offset(360, 884)]);
    expect(find.byTooltip('Delete (Del)'), findsOneWidget);
    final y = inkOf(s, pages[0]).single.points.first.y;
    expect(y, greaterThan(900)); // Moved by both drags, in page 1's coordinates.
    expect(inkOf(s, pages[1]).single.id, 'w2');
    expect(elementsOf(s, pages[1].id), isEmpty);
    await closeEditor(tester);
  });

  testWidgets('single-page flow: text goes onto the page shown', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One page at a time'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();

    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(640, 450)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    expect(tester.getTopLeft(field).dx, closeTo(640, 2));
    await tester.enterText(field, 'Second');
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final pages = s.pages.pagesOf(nb.id);
    expect(elementsOf(s, pages[1].id), hasLength(1));
    expect(elementsOf(s, pages[0].id), isEmpty);
    await closeEditor(tester);
  });

  group('elements in notebook operations', () {
    late AppServices s;
    late Notebook nb;
    late NotebookPage page;

    setUp(() {
      s = AppServices.create(AppDatabase.inMemory(), clock: FakeClock());
      nb = s.notebooks.create(
        title: 'N',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      page = s.pages.pagesOf(nb.id).single;
      s.elements.save([textBox('t1', page.id), textBox('t2', page.id)]);
      s.elements.delete(['t2']);
    });

    tearDown(() => s.dispose());

    test('duplicating a notebook copies its live elements', () {
      final copy = s.notebooks.duplicate(nb.id)!;
      final copiedPage = s.pages.pagesOf(copy.id).single;
      final copied = elementsOf(s, copiedPage.id).single;
      expect(copied.id, isNot('t1'));
      expect(copied.rect, textBox('t1', page.id).rect);
      expect(copied.data, textBox('t1', page.id).data);
      expect(elementsOf(s, page.id).single.id, 't1'); // Source untouched.
      expect(
        s.elements.dirtyRecords(100).where((r) => r.data?['surfaceId'] == copiedPage.id),
        hasLength(1),
      );
    });

    test('duplicating a canvas copies its elements', () {
      final canvas = s.notebooks.create(
        title: 'C',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      s.elements.save([textBox('c1', canvas.id, at: const Offset(-5000, 7000))]);
      final copy = s.notebooks.duplicate(canvas.id)!;
      expect(elementsOf(s, copy.id), hasLength(1));
    });

    test('deleting forever (and emptying the trash) tombstones elements', () {
      s.notebooks.trash(nb.id);
      expect(elementsOf(s, page.id), hasLength(1)); // Trash keeps content.
      s.notebooks.emptyTrash();
      expect(elementsOf(s, page.id), isEmpty);
      expect(s.elements.dirtyRecords(100).where((r) => r.id == 't1').single.deleted, isTrue);
    });

    test('page duplicate, delete and restore carry elements', () {
      final actions = PageActions(s, nb.id);
      final copy = actions.duplicate(page);
      expect(elementsOf(s, copy.id), hasLength(1));
      final deleted = actions.delete(page);
      expect(elementsOf(s, page.id), isEmpty);
      actions.restore(deleted);
      expect(elementsOf(s, page.id).single.id, 't1');
    });

    test('thumbnails show text-only pages and refresh on element edits', () {
      final renderer = ThumbnailRenderer(pages: s.pages, strokes: s.strokes, elements: s.elements);
      expect(renderer.render(nb, width: 60), isNotNull);
      final stats = SurfaceStats(s.database);
      final before = stats.fingerprint(page.id);
      s.elements.save([
        textBox('t1', page.id).copyWith(data: const TextData(text: 'Changed').toJson()),
      ]);
      expect(stats.fingerprint(page.id), isNot(before));
    });
  });

  test('strokes alone still copy without an element repository', () {
    final s = AppServices.create(AppDatabase.inMemory(), clock: FakeClock());
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'N',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = s.pages.pagesOf(nb.id).single;
    s.strokes.save([
      Stroke(
        id: 'a',
        surfaceId: page.id,
        tool: InkTool.pen,
        color: 0xFF000000,
        width: 2,
        points: const [StrokePoint(1, 1, 0.5), StrokePoint(9, 9, 0.5)],
        createdAt: 1,
      ),
    ]);
    s.elements.save([textBox('t', page.id)]);
    final copier = SurfaceCopier(s.strokes);
    expect(copier.copy(from: page.id, to: 'other'), 1);
    expect(elementsOf(s, 'other'), isEmpty);
  });
}
