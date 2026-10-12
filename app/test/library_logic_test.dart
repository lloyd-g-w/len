import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_stats.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/library/library_controller.dart';
import 'package:len/features/library/library_query.dart';
import 'package:len/features/library/thumbnails/thumbnail_cache.dart';
import 'package:len/features/library/thumbnails/thumbnail_renderer.dart';
import 'package:len/ink/render/content_painter.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'data_test.dart' show FakeClock, stroke;

Notebook nb(String title, {int created = 0, int edited = 0}) => Notebook(
  id: title,
  title: title,
  kind: NotebookKind.paged,
  paper: PaperStyle.blank,
  coverColor: 0,
  createdAt: created,
  updatedAt: edited,
);

void main() {
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
  });

  group('LibraryController', () {
    late AppServices services;
    late LibraryController c;

    setUp(() {
      services = AppServices.create(AppDatabase.inMemory(), clock: FakeClock());
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

      c.openFolder(maths.id);
      expect(c.breadcrumbs.map((f) => f.name), ['School', 'Maths']);
      expect(c.goUp(), isTrue);
      expect(c.folderId, school.id);
      expect(c.goUp(), isTrue);
      expect(c.goUp(), isFalse);
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
      c.setFavorite(deep.id, true);
      c.showSection(LibrarySection.favorites);
      expect(c.visibleNotebooks.map((n) => n.id), [deep.id]);

      c.trashNotebook(deep.id);
      expect(c.visibleNotebooks, isEmpty);
      c.showSection(LibrarySection.trash);
      expect(c.visibleNotebooks.map((n) => n.id), [deep.id]);
      c.emptyTrash();
      expect(c.visibleNotebooks, isEmpty);
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
