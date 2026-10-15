import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/name_order.dart';
import 'package:len/data/surface_stats.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/library/cover_grid.dart';
import 'package:len/features/library/library_controller.dart';
import 'package:len/features/library/library_query.dart';
import 'package:len/features/library/new_notebook/default_title.dart';
import 'package:len/features/library/thumbnails/thumbnail_cache.dart';
import 'package:len/features/library/thumbnails/thumbnail_renderer.dart';
import 'package:len/ink/render/content_painter.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'data_test.dart' show FakeClock, stroke;

Notebook nb(String title, {int created = 0, int edited = 0}) => Notebook(
  id: title,
  title: title,
  kind: NotebookKind.paged,
  paper: Paper.blank,
  coverColor: 0,
  createdAt: created,
  updatedAt: edited,
);

void main() {
  test('a short viewport narrows covers so a whole row with titles fits', () {
    // A phone upright: covers of about 150 dp, two columns.
    expect(CoverGridDelegate.columnsFor(358, 150, 16, height: 844, captionHeight: 68), 2);
    // Held sideways: 804 dp wide, 390 high. Without the height, four
    // covers about 190 dp wide (264 dp tall); with it, a cover and its
    // caption take at most 60 % of the height.
    expect(CoverGridDelegate.columnsFor(804, 150, 16), 4);
    final columns = CoverGridDelegate.columnsFor(804, 150, 16, height: 390, captionHeight: 68);
    final tile = (804 - 16 * (columns - 1)) / columns;
    expect(tile / 0.72 + 68, lessThanOrEqualTo(390 * 0.6));
    // Large text: covers stop narrowing at 96 dp.
    final big = CoverGridDelegate.columnsFor(804, 150, 16, height: 390, captionHeight: 124);
    expect((804 - 16 * (big - 1)) / big, greaterThanOrEqualTo(96));
    // Tall windows are unaffected.
    expect(CoverGridDelegate.columnsFor(1100, 150, 24, height: 800, captionHeight: 68), 6);
  });

  test('a notebook without a title is named after the day, numbered when taken', () {
    final day = DateTime(2026, 10, 13);
    expect(defaultNotebookTitle(day, const []), '13 October');
    expect(defaultNotebookTitle(day, const [], language: PlannerLanguage.enUS), 'October 13');
    expect(defaultNotebookTitle(day, const [], language: PlannerLanguage.de), '13. Oktober');
    expect(defaultNotebookTitle(day, const ['13 October']), '13 October (2)');
    expect(defaultNotebookTitle(day, const ['13 October', '13 October (2)']), '13 October (3)');
  });

  group('LibraryQuery', () {
    test('matches every term case-insensitively', () {
      expect(LibraryQuery.matches('Physics — Mechanics', 'mech phys'), isTrue);
      expect(LibraryQuery.matches('Physics', 'chem'), isFalse);
      expect(LibraryQuery.matches('Anything', '  '), isTrue);
    });

    test('sorts by edit time, creation time or name', () {
      final list = [
        nb('b', created: 3, edited: 1),
        nb('A', created: 1, edited: 3),
        nb('c', created: 2, edited: 2),
      ];
      String titles(LibrarySort s) => LibraryQuery.sorted(list, s).map((n) => n.title).join();
      expect(titles(LibrarySort.edited), 'Acb');
      expect(titles(LibrarySort.created), 'bcA');
      expect(titles(LibrarySort.name), 'Abc');
    });

    test('sorts names with Unicode case and accents folded, ties by id', () {
      final list = [
        for (final t in ['Zoë', 'Яблоко', 'Émile', 'apple', 'Ärger', 'арбуз']) nb(t),
      ];
      expect(LibraryQuery.sorted(list, LibrarySort.name).map((n) => n.title), [
        'apple',
        'Ärger',
        'Émile',
        'Zoë',
        'арбуз',
        'Яблоко',
      ]);
      // Equal once folded: by id (here the title).
      final twins = [nb('Été'), nb('ete')];
      expect(LibraryQuery.sorted(twins, LibrarySort.name).map((n) => n.id), ['ete', 'Été']);
    });

    test('sorts numbers in names by value (R16-1)', () {
      final titles = [
        'Lecture 10',
        'Lecture 2',
        'Lecture 1',
        'Lecture 02',
        'Lecture',
        'Lecture 1b',
        'Lecture 21',
        'Week 3 notes',
        'Week 12',
      ];
      final sorted = LibraryQuery.sorted([for (final t in titles) nb(t)], LibrarySort.name);
      expect(sorted.map((n) => n.title), [
        'Lecture',
        'Lecture 1',
        'Lecture 1b',
        'Lecture 2',
        'Lecture 02',
        'Lecture 10',
        'Lecture 21',
        'Week 3 notes',
        'Week 12',
      ]);
      expect(NameOrder.compareKeys('a99999999999999999999', 'a100000000000000000000'), lessThan(0));
    });

    test('filters ignoring accents, as full-text search does', () {
      expect(LibraryQuery.matches('Café notes', 'cafe'), isTrue);
      expect(LibraryQuery.matches('Cafe notes', 'CAFÉ'), isTrue);
    });
  });

  group('LibraryController', () {
    late FakeClock clock;
    late AppServices services;
    late LibraryController c;

    setUp(() {
      clock = FakeClock();
      services = AppServices.create(AppDatabase.inMemory(), clock: clock);
      c = LibraryController(services);
    });

    tearDown(() {
      c.dispose();
      services.dispose();
    });

    test('creates notebooks and folders in the open folder', () {
      final school = c.createFolder('School', color: 1);
      c.openFolder(school.id);
      final maths = c.createFolder('Maths', color: 2);
      final notebook = c.createNotebook(
        title: 'Algebra',
        kind: NotebookKind.paged,
        paper: PaperStyle.gridLarge,
        coverColor: 1,
      );
      expect(maths.parentId, school.id);
      expect(notebook.folderId, school.id);
      expect(c.visibleFolders.map((f) => f.name), ['Maths']);
      expect(c.visibleNotebooks.map((n) => n.title), ['Algebra']);
      expect(c.breadcrumbs.map((f) => f.name), ['School']);
      expect(c.itemCountIn(school.id), 2);
      // Searching in the folder keeps it the parent (R10-19).
      c.query = 'zzz';
      expect(c.createFolder('Physics', color: 3).parentId, school.id);
      c.query = '';

      c.openFolder(maths.id);
      expect(c.breadcrumbs.map((f) => f.name), ['School', 'Maths']);
      expect(c.goUp(), isTrue);
      expect(c.folderId, school.id);
      expect(c.goUp(), isTrue);
      expect(c.goUp(), isFalse);
    });

    test('undoing a folder deletion restores what synced in just before it', () {
      final work = c.createFolder('Work', color: 1);
      // Sync brings a notebook and a subfolder in, and renames the folder,
      // before the library reloads.
      final synced = services.notebooks.create(
        title: 'Synced',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
        folderId: work.id,
      );
      final sub = services.folders.create(name: 'Sub', parentId: work.id, color: 2);
      services.folders.update(services.folders.get(work.id)!.copyWith(name: 'Job'));

      final deletion = c.deleteFolder(work.id);
      expect(deletion.notebookIds, [synced.id]);
      expect(services.notebooks.get(synced.id)!.isTrashed, isTrue);
      expect(services.folders.list(), isEmpty);

      c.undoDeleteFolder(deletion);
      expect(services.notebooks.get(synced.id)!.isTrashed, isFalse);
      expect(services.notebooks.get(synced.id)!.folderId, work.id);
      expect(services.folders.list().map((f) => f.name), ['Job', 'Sub']);
      expect(services.folders.get(sub.id)!.parentId, work.id);
    });

    test('deleting a folder deleted meanwhile leaves the notebooks it showed at the top', () {
      final work = c.createFolder('Work', color: 1);
      final orphan = services.notebooks.create(
        title: 'Orphan',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
        folderId: work.id,
      );
      services.folders.delete(work.id); // By sync; the notebook shows at the top.
      c.reload();
      expect(c.visibleNotebooks.map((n) => n.id), [orphan.id]);

      final deletion = c.deleteFolder(work.id); // From a stale menu.
      expect(deletion.folders, isEmpty);
      expect(deletion.notebookIds, isEmpty);
      expect(services.notebooks.get(orphan.id)!.isTrashed, isFalse);
    });

    test('a search found by a recording says which (R8-11)', () {
      final lecture = c.createNotebook(
        title: 'Physics',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      services.recordings.save(
        notebookId: lecture.id,
        parts: [RecordingPart('cd' * 32, 1000)],
        mime: 'audio/mp4',
        title: 'Lecture 4',
        segments: const [RecordingSegment(0, 1000)],
      );
      c.reload();
      c.query = 'lecture';
      expect(c.visibleNotebooks.map((n) => n.title), ['Physics']);
      expect(c.recordingMatchOf(lecture), 'Lecture 4');
      c.query = 'phys';
      expect(c.recordingMatchOf(lecture), isNull); // Its title matched.
      // Recent shows no caption at the top level.
      expect(c.folderPathOf(lecture), isNull);
      expect(c.locationOf(lecture), 'Library');
    });

    test('search spans folders; favourites and trash have their own views', () {
      final f = c.createFolder('Work', color: 1);
      c.openFolder(f.id);
      final deep = c.createNotebook(
        title: 'Quarterly plan',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      c.openFolder(null);
      c.createNotebook(
        title: 'Shopping',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      c.query = 'plan';
      expect(c.visibleNotebooks.map((n) => n.title), ['Quarterly plan']);
      expect(c.locationOf(deep), 'Work');

      c.query = '';
      c.setFavorites([deep.id], true);
      c.showSection(LibrarySection.favorites);
      expect(c.visibleNotebooks.map((n) => n.id), [deep.id]);

      c.trashNotebooks([deep.id]);
      expect(c.visibleNotebooks, isEmpty);
      c.showSection(LibrarySection.trash);
      expect(c.visibleNotebooks.map((n) => n.id), [deep.id]);
      c.emptyTrash();
      expect(c.visibleNotebooks, isEmpty);
    });

    group('batch operations start from the database (sync may be ahead of the view)', () {
      Notebook make(String title, {String? folderId}) => services.notebooks.create(
        title: title,
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
        folderId: folderId,
      );
      late int notified;
      setUp(() {
        notified = 0;
        c.addListener(() => notified++);
      });

      test('trash takes only live notebooks; Undo restores just those', () {
        final a = make('A');
        final b = make('B');
        c.reload();
        services.notebooks.trash(b.id); // Another device trashed it.
        final trashedAt = services.notebooks.get(b.id)!.trashedAt;
        clock.now += 1000;
        notified = 0;

        final trashed = c.trashNotebooks([a.id, b.id]);
        expect(trashed, [a.id]);
        expect(services.notebooks.get(b.id)!.trashedAt, trashedAt);
        expect(notified, 1);

        expect(c.restoreNotebooks(trashed).map((n) => n.id), [a.id]);
        expect(services.notebooks.get(a.id)!.isTrashed, isFalse);
        expect(services.notebooks.get(b.id)!.isTrashed, isTrue);
      });

      test('restore says which notebooks came back', () {
        final a = make('A');
        final b = make('B');
        c.trashNotebooks([a.id]);
        services.notebooks.delete(b.id);
        expect(c.restoreNotebooks([a.id, b.id]).map((n) => n.id), [a.id]);
      });

      test('moves remember where each notebook was', () {
        final work = services.folders.create(name: 'Work', color: 1);
        final home = services.folders.create(name: 'Home', color: 1);
        final a = make('A');
        final b = make('B');
        c.reload();
        services.notebooks.moveTo(a.id, work.id); // Synced in.
        notified = 0;
        expect(c.moveNotebooks([a.id, b.id, 'gone'], home.id), {a.id: work.id, b.id: null});
        expect(notified, 1);
        expect(services.notebooks.get(b.id)!.folderId, home.id);
      });

      test('a drop on a folder deleted meanwhile files at the top level', () {
        final gone = c.createFolder('Gone', color: 1);
        final f = c.createFolder('F', color: 1);
        final a = make('A');
        final trashed = make('T');
        c.reload();
        // Sync deletes the folder and trashes a notebook while dragging.
        services.folders.delete(gone.id);
        services.notebooks.trash(trashed.id);

        expect(c.moveNotebooks([a.id, trashed.id], gone.id), {a.id: null});
        expect(services.notebooks.get(a.id)!.folderId, isNull);
        expect(services.notebooks.get(trashed.id)!.folderId, isNull);
        expect(c.moveFolder(f.id, gone.id), (from: null));
        expect(services.folders.get(f.id)!.parentId, isNull);
      });

      test('favourites change only what differs', () {
        final a = make('A');
        final b = make('B');
        services.notebooks.setFavorite(b.id, true);
        expect(c.setFavorites([a.id, b.id], true), [a.id]);
        expect(services.notebooks.get(a.id)!.favorite, isTrue);
      });

      test('folder edits and moves keep what sync changed meanwhile', () {
        final f = c.createFolder('F', color: 1);
        final g = c.createFolder('G', color: 2);
        final h = c.createFolder('H', color: 3);
        services.folders.move(f.id, g.id); // Synced in, not yet reloaded.

        final before = c.editFolder(f.id, (now) => now.copyWith(name: 'F2'));
        expect(before!.name, 'F');
        expect(services.folders.get(f.id)!.parentId, g.id);
        expect(services.folders.get(f.id)!.name, 'F2');

        expect(c.moveFolder(f.id, h.id), (from: g.id));
        expect(c.moveFolder(h.id, f.id), isNull); // Into its own child.
        expect(c.editFolder('gone', (f) => f), isNull);
      });

      test('a folder exports the notebooks the database holds in it', () {
        final f = c.createFolder('F', color: 1);
        final inside = make('Synced', folderId: f.id);
        expect(c.notebooksIn(f.id).map((n) => n.id), [inside.id]);
      });
    });

    test('a folder deleted remotely while open falls back to the root', () {
      final f = c.createFolder('Gone', color: 1);
      c.openFolder(f.id);
      services.folders.delete(f.id);
      c.reload();
      expect(c.folderId, isNull);
    });
  });

  group('Thumbnails', () {
    late AppServices services;
    late ThumbnailRenderer renderer;

    setUp(() {
      services = AppServices.create(AppDatabase.inMemory(), clock: FakeClock());
      renderer = ThumbnailRenderer(pages: services.pages, strokes: services.strokes);
    });

    tearDown(() => services.dispose());

    Notebook create(NotebookKind kind) => services.notebooks.create(
      title: 'T',
      kind: kind,
      paper: PaperStyle.wideRuled,
      coverColor: 0,
    );

    test('empty notebooks have no preview; drawn ones do', () {
      final paged = create(NotebookKind.paged);
      final canvas = create(NotebookKind.canvas);
      expect(renderer.render(paged, width: 60), isNull);
      expect(renderer.render(canvas, width: 60), isNull);

      final page = services.pages.pagesOf(paged.id).single;
      services.strokes.save([stroke('a', const Offset(100, 100), surface: page.id)]);
      services.strokes.save([stroke('b', const Offset(-3000, 9000), surface: canvas.id)]);
      final image = renderer.render(paged, width: 60)!;
      expect(image.width, 60);
      expect(image.height, (60 / ThumbnailRenderer.aspect).round());
      expect(renderer.render(canvas, width: 60), isNotNull);
    });

    test('previews draw thin ink as plain lines, without building outlines', () {
      void paint(Stroke s, double scale) => ContentPainter.paint(
        Canvas(PictureRecorder()),
        [s],
        const [],
        pixelScale: scale,
        sketchThin: true,
      );
      final thin = stroke('thin', const Offset(10, 10));
      paint(thin, 0.1);
      expect(StrokeRenderer.hasPath(thin), isFalse);
      final wide = stroke('wide', const Offset(10, 10));
      paint(wide, 10);
      expect(StrokeRenderer.hasPath(wide), isTrue);
    });

    testWidgets('the cache renders lazily and refreshes when content changes', (tester) async {
      final paged = create(NotebookKind.paged);
      final page = services.pages.pagesOf(paged.id).single;
      final cache = ThumbnailCache(
        renderer: renderer,
        stats: SurfaceStats(services.database),
        width: 40,
      );
      addTearDown(cache.dispose);
      var notified = 0;
      cache.addListener(() => notified++);

      expect(cache.imageFor(paged), isNull); // Queued.
      await tester.pump(const Duration(milliseconds: 1));
      expect(cache.imageFor(paged), isNull); // Rendered: nothing drawn.

      services.strokes.save([stroke('a', const Offset(100, 100), surface: page.id)]);
      cache.invalidate([paged.id]);
      cache.imageFor(paged);
      await tester.pump(const Duration(milliseconds: 1));
      expect(cache.imageFor(paged), isNotNull);
      expect(notified, greaterThanOrEqualTo(2));
    });

    testWidgets('empty notebooks never notify; a new page paper re-renders', (tester) async {
      final notebooks = [for (var i = 0; i < 5; i++) create(NotebookKind.paged)];
      final cache = ThumbnailCache(
        renderer: renderer,
        stats: SurfaceStats(services.database),
        width: 40,
      );
      addTearDown(cache.dispose);
      var notified = 0;
      cache.addListener(() => notified++);
      for (final n in notebooks) {
        cache.imageFor(n);
      }
      await tester.pump(const Duration(milliseconds: 1));
      expect(notified, 0, reason: 'plain covers stay plain');

      final drawn = notebooks.first;
      final page = services.pages.pagesOf(drawn.id).single;
      services.strokes.save([stroke('a', const Offset(100, 100), surface: page.id)]);
      cache.invalidate([drawn.id]);
      cache.imageFor(drawn);
      await tester.pump(const Duration(milliseconds: 1));
      final first = cache.imageFor(drawn);
      expect(first, isNotNull);

      services.database.db.execute("UPDATE pages SET paper = 'gridLarge' WHERE id = ?", [page.id]);
      cache.invalidate([drawn.id]);
      cache.imageFor(drawn);
      await tester.pump(const Duration(milliseconds: 1));
      expect(cache.imageFor(drawn), isNot(same(first)));
    });

    testWidgets('more covers on screen than its capacity settle (no re-render loop)', (
      tester,
    ) async {
      final count = ThumbnailCache.capacity + 20;
      final notebooks = [for (var i = 0; i < count; i++) create(NotebookKind.paged)];
      for (final n in notebooks) {
        final page = services.pages.pagesOf(n.id).single;
        services.strokes.save([stroke('s${n.id}', const Offset(100, 100), surface: page.id)]);
      }
      final cache = ThumbnailCache(
        renderer: renderer,
        stats: SurfaceStats(services.database),
        width: 8,
      );
      addTearDown(cache.dispose);
      // Every cover is on screen: each notification rebuilds all of them.
      void build() {
        for (final n in notebooks) {
          cache.imageFor(n);
        }
      }

      var notified = 0;
      cache.addListener(() {
        notified++;
        build();
      });
      build();
      for (var i = 0; i < 400 && notified < 400; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      final settled = notified;
      await tester.pump(const Duration(milliseconds: 50));
      expect(notified, settled, reason: 'no more renders once all are cached');
      expect(notebooks.every((n) => cache.imageFor(n) != null), isTrue);
    });
  });
}
