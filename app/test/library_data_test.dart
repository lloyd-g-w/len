import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/folder_repository.dart';
import 'package:len/data/notebook_repository.dart';
import 'package:len/data/page_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/cover_style.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';

import 'data_test.dart' show FakeClock, stroke;
import 'support/fake_server.dart' show FakeServer, apiFor, device;

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late StrokeRepository strokes;
  late PageRepository pages;
  late NotebookRepository notebooks;
  late FolderRepository folders;

  setUp(() {
    db = AppDatabase.inMemory();
    clock = FakeClock();
    strokes = StrokeRepository(db, deviceId: 'dev-a', clock: clock);
    pages = PageRepository(db, deviceId: 'dev-a', clock: clock);
    notebooks = NotebookRepository(
      db,
      deviceId: 'dev-a',
      pages: pages,
      strokes: strokes,
      clock: clock,
    );
    folders = FolderRepository(db, deviceId: 'dev-a', clock: clock);
  });

  tearDown(() => db.close());

  Notebook notebook(String title, {NotebookKind kind = NotebookKind.paged, String? folderId}) =>
      notebooks.create(
        title: title,
        kind: kind,
        paper: PaperStyle.lined,
        coverColor: 1,
        folderId: folderId,
      );

  group('FolderRepository', () {
    test('nests folders and builds breadcrumb paths', () {
      final school = folders.create(name: 'School', color: 1);
      final maths = folders.create(name: 'Maths', parentId: school.id, color: 2);
      final algebra = folders.create(name: 'Algebra', parentId: maths.id, color: 3);

      expect(folders.childrenOf(null).map((f) => f.name), ['School']);
      expect(folders.childrenOf(school.id).map((f) => f.name), ['Maths']);
      expect(folders.pathTo(algebra.id).map((f) => f.name), ['School', 'Maths', 'Algebra']);
      expect(folders.subtreeOf(school.id), {school.id, maths.id, algebra.id});
    });

    test('refuses to move a folder into itself or a descendant', () {
      final a = folders.create(name: 'A', color: 1);
      final b = folders.create(name: 'B', parentId: a.id, color: 1);
      expect(folders.move(a.id, b.id), isNull);
      expect(folders.move(a.id, a.id), isNull);
      expect(folders.move(b.id, null)!.parentId, isNull);
      expect(folders.childrenOf(null).map((f) => f.name), ['A', 'B']);
    });

    test('a cycle from concurrent remote moves surfaces at the top level', () {
      final a = folders.create(name: 'A', color: 1);
      final b = folders.create(name: 'B', parentId: a.id, color: 1);
      final c = folders.create(name: 'C', parentId: b.id, color: 1);
      // Another device moved A into B at the same time.
      folders.applyRemote(
        SyncRecord(
          collection: 'folders',
          id: a.id,
          updatedAt: 1 << 40,
          deviceId: 'dev-b',
          deleted: false,
          data: {'name': 'A', 'parentId': b.id, 'color': 1, 'createdAt': 0},
        ),
      );
      expect(folders.childrenOf(null).map((f) => f.name), ['A', 'B']);
      expect(folders.childrenOf(b.id).map((f) => f.id), [c.id]);
    });

    test('deleting a folder deletes its subfolders and trashes their notebooks', () {
      final a = folders.create(name: 'A', color: 1);
      final b = folders.create(name: 'B', parentId: a.id, color: 1);
      final inB = notebook('in B', folderId: b.id);
      final outside = notebook('outside');

      notebooks.trashAllIn(folders.delete(a.id));

      expect(folders.list(), isEmpty);
      expect(notebooks.list().map((n) => n.id), [outside.id]);
      expect(notebooks.trashed().map((n) => n.id), [inB.id]);
      // Restoring puts it back at the root, since its folder is gone.
      notebooks.restore(inB.id);
      expect(notebooks.get(inB.id)!.folderId, isNull);
      expect(notebooks.get(inB.id)!.isTrashed, isFalse);
    });
  });

  group('NotebookRepository organisation', () {
    test('trash hides, restore returns, delete forever and empty trash', () {
      final a = notebook('A');
      final b = notebook('B');
      notebooks.trash(a.id);
      expect(notebooks.list().map((n) => n.id), [b.id]);
      expect(notebooks.trashed().single.id, a.id);
      expect(notebooks.get(a.id)!.isTrashed, isTrue);

      notebooks.restore(a.id);
      expect(notebooks.trashed(), isEmpty);
      expect(notebooks.list(), hasLength(2));

      notebooks.trash(a.id);
      notebooks.trash(b.id);
      notebooks.emptyTrash();
      expect(notebooks.trashed(), isEmpty);
      expect(notebooks.get(a.id), isNull);
      expect(pages.pagesOf(a.id), isEmpty);
    });

    test('favourite and move do not change the last-edited time', () {
      final a = notebook('A');
      final folder = folders.create(name: 'F', color: 1);
      clock.now += 1000;
      notebooks.setFavorite(a.id, true);
      notebooks.moveTo(a.id, folder.id);
      final moved = notebooks.get(a.id)!;
      expect(moved.favorite, isTrue);
      expect(moved.folderId, folder.id);
      expect(moved.editedAt, a.editedAt);
      expect(moved.updatedAt, greaterThan(a.updatedAt));

      notebooks.touch(a.id);
      expect(notebooks.get(a.id)!.editedAt, clock.now);
    });

    test('duplicate copies pages and strokes under new ids', () {
      final source = notebook('Physics');
      final page = pages.pagesOf(source.id).single;
      pages.addPage(source.id, paper: PaperStyle.grid, after: page);
      strokes.save([
        stroke('s1', const Offset(10, 10), surface: page.id),
        stroke('s2', const Offset(600, 600), surface: page.id),
      ]);
      strokes.delete(['s2']);

      final copy = notebooks.duplicate(source.id)!;
      expect(copy.id, isNot(source.id));
      expect(copy.title, 'Physics (copy)');

      final copiedPages = pages.pagesOf(copy.id);
      expect(copiedPages, hasLength(2));
      expect(copiedPages.map((p) => p.paper), [PaperStyle.lined, PaperStyle.grid]);
      expect(copiedPages.map((p) => p.id).toSet().intersection({page.id}), isEmpty);

      final range = ChunkGrid.rangeFor(const Rect.fromLTWH(0, 0, 2000, 2000));
      final copiedPage = copiedPages.first.id;
      final copied = strokes.loadChunks(copiedPage, strokes.populatedChunks(copiedPage, range));
      expect(copied, hasLength(1)); // The erased stroke is not copied.
      expect(copied.single.id, isNot('s1'));
      expect(copied.single.points, strokes.loadChunks(page.id, [(x: 0, y: 0)]).single.points);
      // The source is untouched.
      expect(pages.pagesOf(source.id), hasLength(2));
      expect(
        strokes.dirtyRecords(100).where((r) => r.data?['surfaceId'] == copiedPage),
        hasLength(1),
      );
    });

    test('duplicate keeps paper colour, bookmarks and PDF backgrounds', () {
      final source = notebook('Paper');
      final sha = 'a' * 64;
      final pdfPage = pages.insertPages(source.id, [
        (
          size: const Size(612, 792),
          paper: PaperStyle.blank,
          color: PaperColor.white,
          background: PageBackground.pdf(blob: sha, pageIndex: 2),
        ),
      ]).single;
      final first = pages.pagesOf(source.id).first;
      pages.setPaper([first.id], style: PaperStyle.cornell, color: PaperColor.cream);
      pages.setBookmarked(pdfPage.id, true);

      final copy = notebooks.duplicate(source.id)!;
      final copied = pages.pagesOf(copy.id);
      expect(copied.map((p) => p.paper), [PaperStyle.cornell, PaperStyle.blank]);
      expect(copied.map((p) => p.paperColor), [PaperColor.cream, PaperColor.white]);
      expect(copied.map((p) => p.bookmarked), [false, true]);
      expect(copied.last.background, PageBackground.pdf(blob: sha, pageIndex: 2));
      expect(copied.last.size, const Size(612, 792));
      // Blobs are content-addressed and shared, not copied.
      expect(pages.referencedBlobs(), {sha});
    });

    test('duplicate of a canvas copies its strokes onto the new surface', () {
      final canvas = notebook('Board', kind: NotebookKind.canvas);
      strokes.save([stroke('s1', const Offset(-5000, 3000), surface: canvas.id)]);
      final copy = notebooks.duplicate(canvas.id)!;
      final range = ChunkGrid.rangeFor(const Rect.fromLTRB(-6000, 2000, 0, 4000));
      expect(strokes.populatedChunks(copy.id, range), isNotEmpty);
      expect(pages.pagesOf(copy.id), isEmpty);
    });

    test('records from older clients without library fields still parse', () {
      notebooks.applyRemote(
        const SyncRecord(
          collection: 'notebooks',
          id: 'old',
          updatedAt: 5,
          deviceId: 'dev-old',
          deleted: false,
          data: {
            'title': 'Legacy',
            'kind': 'canvas',
            'paper': 'grid',
            'coverColor': 7,
            'createdAt': 1,
            'coverStyle': 'from-the-future',
          },
        ),
      );
      final n = notebooks.get('old')!;
      expect(n.folderId, isNull);
      expect(n.favorite, isFalse);
      expect(n.isTrashed, isFalse);
      expect(n.coverStyle, CoverStyle.plain);
      expect(n.paperColor, PaperColor.white);
      expect(n.editedAt, 5);
    });

    test('an edit from an older client keeps the library fields it omits', () {
      final folder = folders.create(name: 'School', color: 1);
      final nb = notebook('Algebra', folderId: folder.id);
      notebooks.setFavorite(nb.id, true);
      notebooks.trash(nb.id);
      notebooks.update(
        notebooks.get(nb.id)!.copyWith(coverStyle: CoverStyle.waves, paperColor: PaperColor.dark),
      );
      final before = notebooks.get(nb.id)!;
      final applied = notebooks.applyRemote(
        SyncRecord(
          collection: 'notebooks',
          id: nb.id,
          updatedAt: before.updatedAt + 10,
          deviceId: 'dev-old',
          deleted: false,
          data: {
            'title': 'Renamed on an old phone',
            'kind': 'paged',
            'paper': 'lined',
            'coverColor': 1,
            'createdAt': before.createdAt,
          },
        ),
      );
      expect(applied, isTrue);
      final after = notebooks.get(nb.id)!;
      expect(after.title, 'Renamed on an old phone');
      expect(after.folderId, folder.id);
      expect(after.favorite, isTrue);
      expect(after.trashedAt, before.trashedAt);
      expect(after.coverStyle, CoverStyle.waves);
      expect(after.paperColor, PaperColor.dark);
      expect(after.editedAt, before.editedAt);
    });

    test('fields a newer record does send replace local values, null included', () {
      final folder = folders.create(name: 'School', color: 1);
      final nb = notebook('Algebra', folderId: folder.id);
      notebooks.applyRemote(
        SyncRecord(
          collection: 'notebooks',
          id: nb.id,
          updatedAt: nb.updatedAt + 10,
          deviceId: 'dev-b',
          deleted: false,
          data: {
            'title': 'Algebra',
            'kind': 'paged',
            'paper': 'lined',
            'coverColor': 1,
            'createdAt': nb.createdAt,
            'folderId': null,
            'favorite': false,
            'trashedAt': null,
            'paperColor': 'cream',
          },
        ),
      );
      expect(notebooks.get(nb.id)!.folderId, isNull);
      expect(notebooks.get(nb.id)!.paperColor, PaperColor.cream);
      // And it round-trips through the wire format.
      expect(notebooks.dirtyRecords(10), isEmpty);
      notebooks.update(notebooks.get(nb.id)!);
      expect(notebooks.dirtyRecords(10).single.data!['paperColor'], 'cream');
    });
  });

  test('folders, favourites, moves and trash sync between devices', () async {
    final server = FakeServer();
    final a = device(server);
    final b = device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    final school = a.folders.create(name: 'School', color: 0xFF112233);
    final maths = a.folders.create(name: 'Maths', parentId: school.id, color: 1);
    final nb = a.notebooks.create(
      title: 'Algebra',
      kind: NotebookKind.paged,
      paper: PaperStyle.grid,
      coverColor: 1,
      coverStyle: CoverStyle.waves,
      folderId: maths.id,
    );
    a.notebooks.setFavorite(nb.id, true);
    await a.sync.engine.sync(apiFor(server));
    final changes = await b.sync.engine.sync(apiFor(server));

    expect(changes.folders, isTrue);
    expect(b.folders.pathTo(maths.id).map((f) => f.name), ['School', 'Maths']);
    final synced = b.notebooks.get(nb.id)!;
    expect(synced.folderId, maths.id);
    expect(synced.favorite, isTrue);
    expect(synced.coverStyle, CoverStyle.waves);

    b.notebooks.trash(nb.id);
    b.folders.delete(school.id);
    await b.sync.engine.sync(apiFor(server));
    await a.sync.engine.sync(apiFor(server));
    expect(a.folders.list(), isEmpty);
    expect(a.notebooks.trashed().single.id, nb.id);
  });
}
