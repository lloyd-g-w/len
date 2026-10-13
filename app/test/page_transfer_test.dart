import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/link_target.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'data_test.dart' show stroke;

final _sha = 'ab' * 32;

/// Moving and copying pages to another notebook (UX_AUDIT R7-9).
void main() {
  late AppServices s;
  setUp(() => s = AppServices.create(AppDatabase.inMemory()));
  tearDown(() => s.dispose());

  Notebook paged(String title) => s.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: PaperStyle.wideRuled,
    coverColor: 0,
  );

  Recording record(String notebookId, int from) => s.recordings.save(
    notebookId: notebookId,
    parts: [RecordingPart(_sha, 5000)],
    mime: 'audio/mp4',
    title: 'Lecture',
    segments: [RecordingSegment(from, 5000)],
  );

  test('copied pages bring ink, links among them, outline and their recordings', () {
    final source = paged('Physics'), target = paged('Notes');
    final p1 = s.pages.pagesOf(source.id).single;
    final p2 = s.pages.addPage(source.id, paper: const Paper(PaperStyle.gridLarge));
    final p3 = s.pages.addPage(source.id);
    s.pages.setBookmarked(p2.id, true);
    s.strokes.save([stroke('ink', const Offset(10, 10), surface: p1.id)]); // Written at 1.
    s.elements.save([
      LinkElements.create(
        id: 'to-p2',
        surfaceId: p1.id,
        rect: const Rect.fromLTWH(10, 10, 50, 20),
        target: PageLinkTarget(notebookId: source.id, pageId: p2.id),
        createdAt: 1,
        z: -1,
      ),
      LinkElements.create(
        id: 'to-p3',
        surfaceId: p2.id,
        rect: const Rect.fromLTWH(10, 10, 50, 20),
        target: PageLinkTarget(notebookId: source.id, pageId: p3.id),
        createdAt: 1,
        z: -1,
      ),
    ]);
    final parent = s.outline.add(notebookId: source.id, pageId: p3.id, title: 'Part 2');
    s.outline.add(notebookId: source.id, pageId: p2.id, title: 'Forces', parentId: parent.id);
    record(source.id, 0); // While the ink was written.
    record(source.id, 100000); // Later: no ink of these pages.

    final copied = s.notebooks.copyPages(source.id, [p1.id, p2.id], target.id);
    final pages = s.pages.pagesOf(target.id);
    expect(pages, hasLength(3)); // After the page it had.
    expect(pages.skip(1).map((p) => p.id), copied.pages);
    expect(pages.skip(1).map((p) => p.paper.style), [PaperStyle.wideRuled, PaperStyle.gridLarge]);
    expect(pages.last.bookmarked, isTrue);
    final content = SurfaceCopier(s.strokes, elements: s.elements);
    expect(content.loadAll(copied.pages.first).single.points, content.loadAll(p1.id).single.points);
    // A link to a copied page leads to its copy; to a page left behind, there.
    expect(
      LinkElements.targetOf(content.loadAllElements(copied.pages.first).single),
      PageLinkTarget(notebookId: target.id, pageId: copied.pages.last),
    );
    expect(
      LinkElements.targetOf(content.loadAllElements(copied.pages.last).single),
      PageLinkTarget(notebookId: source.id, pageId: p3.id),
    );
    // The entry of a copied page comes along, at the top level (its parent stayed).
    final outline = s.outline.entriesOf(target.id);
    expect(outline.single.title, 'Forces');
    expect(outline.single.pageId, copied.pages.last);
    expect(outline.single.parentId, isNull);
    // The recording the ink was written during, so it replays there.
    final recordings = s.recordings.listOf(target.id);
    expect(recordings.single.startedAt, 0);
    expect(recordings.single.blobs, [_sha]);
    // Copying again doesn't repeat the recording.
    final again = s.notebooks.copyPages(source.id, [p1.id], target.id);
    expect(again.recordings, isEmpty);
    expect(s.recordings.listOf(target.id), hasLength(1));

    s.notebooks.removeCopies(again);
    s.notebooks.removeCopies(copied);
    expect(s.pages.pagesOf(target.id), hasLength(1));
    expect(s.outline.entriesOf(target.id), isEmpty);
    expect(s.recordings.listOf(target.id), isEmpty);
    expect(s.pages.pagesOf(source.id), hasLength(3)); // Untouched.
  });

  testWidgets('the overview moves and copies selected pages, with Undo', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = paged('Physics'), target = paged('Notes');
    paged('Other');
    s.pages.addPage(source.id, paper: const Paper(PaperStyle.dotted));
    s.pages.addPage(source.id, paper: const Paper(PaperStyle.gridLarge));
    final original = [for (final p in s.pages.pagesOf(source.id)) p.id];
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: source),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> selectAndSend({required bool copy}) async {
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('page-tile-1')));
      await tester.tap(find.byKey(const ValueKey('page-tile-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move or copy…'));
      await tester.pumpAndSettle();
      expect(find.text('Move or copy 2 pages'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Physics'), findsNothing); // Not to itself.
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      await tester.tap(
        copy
            ? find.widgetWithText(OutlinedButton, 'Copy')
            : find.widgetWithText(FilledButton, 'Move'),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    await selectAndSend(copy: false);
    expect(find.text('Moved 2 pages to “Notes”'), findsOneWidget);
    expect(s.pages.pagesOf(source.id).map((p) => p.id), [original.first]);
    expect(s.pages.pagesOf(target.id).map((p) => p.paper.style), [
      PaperStyle.wideRuled,
      PaperStyle.dotted,
      PaperStyle.gridLarge,
    ]);
    expect(find.text('1 page'), findsOneWidget); // The overview shows what is left.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(source.id).map((p) => p.id), original);
    expect(s.pages.pagesOf(target.id), hasLength(1));

    await selectAndSend(copy: true);
    expect(find.text('Copied 2 pages to “Notes”'), findsOneWidget);
    expect(s.pages.pagesOf(source.id).map((p) => p.id), original);
    expect(s.pages.pagesOf(target.id), hasLength(3));

    // Undo in the editor takes the copies back too: one step.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(target.id), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('pages move to a new notebook, links follow them, one Undo', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final folder = s.folders.create(name: 'School', color: 0);
    final source = s.notebooks.create(
      title: 'Physics',
      kind: NotebookKind.paged,
      paper: PaperStyle.dotted,
      paperColor: PaperColor.cream,
      coverColor: 0xFF336699,
      folderId: folder.id,
    );
    final p1 = s.pages.pagesOf(source.id).single;
    final p2 = s.pages.addPage(source.id, paper: const Paper(PaperStyle.gridLarge));
    // A link left behind to the page that moves, and one from another notebook.
    final elsewhere = paged('Notes');
    final there = s.pages.pagesOf(elsewhere.id).single;
    SurfaceElement link(String id, String surface) => LinkElements.create(
      id: id,
      surfaceId: surface,
      rect: const Rect.fromLTWH(10, 10, 50, 20),
      target: PageLinkTarget(notebookId: source.id, pageId: p2.id),
      createdAt: 1,
      z: -1,
    );
    s.elements.save([link('here', p1.id), link('there', there.id)]);
    final content = SurfaceCopier(s.strokes, elements: s.elements);
    LinkTarget? targetOf(String surface) =>
        LinkElements.targetOf(content.loadAllElements(surface).single);

    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: source),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move or copy…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New notebook…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Forces');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('Forces'), findsOneWidget); // The row, now chosen.
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();
    expect(find.text('Moved 1 page to “Forces”'), findsOneWidget);

    final made = s.notebooks.list().singleWhere((n) => n.title == 'Forces');
    expect(made.folderId, folder.id);
    expect(made.coverColor, source.coverColor);
    expect(made.paper.style, PaperStyle.dotted);
    expect(made.paperColor, PaperColor.cream);
    final moved = s.pages.pagesOf(made.id).single; // Only the moved page.
    expect(moved.paper.style, PaperStyle.gridLarge);
    final follows = PageLinkTarget(notebookId: made.id, pageId: moved.id);
    expect(targetOf(p1.id), follows);
    expect(targetOf(there.id), follows);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(s.notebooks.get(made.id), isNull);
    expect(s.pages.pagesOf(source.id).map((p) => p.id), [p1.id, p2.id]);
    final back = PageLinkTarget(notebookId: source.id, pageId: p2.id);
    expect(targetOf(p1.id), back);
    expect(targetOf(there.id), back);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
