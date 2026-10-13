import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/folder_repository.dart';
import 'package:len/data/notebook_repository.dart';
import 'package:len/data/page_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/chunk_grid.dart';
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
        paper: PaperStyle.wideRuled,
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

    test('the trash deletes notebooks forever after 30 days', () {
      final old = notebook('Old');
      final recent = notebook('Recent');
      notebooks.trash(old.id);
      clock.now += const Duration(days: 20).inMilliseconds;
      notebooks.trash(recent.id);
      clock.now += const Duration(days: 10).inMilliseconds;
      expect(notebooks.purgeTrash(), 0); // Exactly 30 days: kept.
      clock.now += 1;
      expect(notebooks.purgeTrash(), 1);
      expect(notebooks.get(old.id), isNull);
      expect(pages.pagesOf(old.id), isEmpty);
      expect(notebooks.trashed().single.id, recent.id);
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
      pages.addPage(source.id, paper: const Paper(PaperStyle.gridLarge), after: page);
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
      expect(copiedPages.map((p) => p.paper.style), [PaperStyle.wideRuled, PaperStyle.gridLarge]);
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
          paper: Paper(PaperStyle.blank),
          color: PaperColor.white,
          background: PageBackground.pdf(blob: sha, pageIndex: 2),
        ),
      ]).single;
      final first = pages.pagesOf(source.id).first;
      pages.setPaper([first.id], paper: Paper(PaperStyle.cornell), color: PaperColor.cream);
      pages.setBookmarked(pdfPage.id, true);

      final copy = notebooks.duplicate(source.id)!;
      final copied = pages.pagesOf(copy.id);
      expect(copied.map((p) => p.paper.style), [PaperStyle.cornell, PaperStyle.blank]);
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

    test('notebook records missing a field or with an unknown value are malformed', () {
      final complete = {
        'title': 'Full',
        'kind': 'canvas',
        'paper': 'dotted',
        'paperData': {'look': PaperLook.standard.toJson()},
        'paperColor': 'white',
        'coverColor': 7,
        'createdAt': 1,
        'editedAt': 2,
        'folderId': null,
        'favorite': false,
        'trashedAt': null,
      };
      SyncRecord record(Map<String, Object?> data) => SyncRecord(
        collection: 'notebooks',
        id: 'nb',
        updatedAt: 5,
        deviceId: 'dev-b',
        deleted: false,
        data: data,
      );
      for (final key in complete.keys) {
        final missing = {...complete}..remove(key);
        expect(() => notebooks.applyRemote(record(missing)), throwsFormatException, reason: key);
      }
      for (final (key, value) in [
        ('kind', 'scroll'),
        ('paper', 'hexagons'),
        ('paperColor', 'mauve'),
        ('paperData', <String, Object?>{}),
        ('favorite', 1),
      ]) {
        final odd = {...complete, key: value};
        expect(() => notebooks.applyRemote(record(odd)), throwsFormatException, reason: key);
      }
      expect(notebooks.get('nb'), isNull);
      expect(notebooks.applyRemote(record({...complete, 'unknown': 1})), isTrue);
      expect(notebooks.get('nb')!.title, 'Full');
    });

    test('remote records replace every field, null included', () {
      final folder = folders.create(name: 'School', color: 1);
      final nb = notebook('Algebra', folderId: folder.id);
      notebooks.setFavorite(nb.id, true);
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
            'paper': 'dotted',
            'paperData': {'look': const PaperLook(dotSize: 2, header: true).toJson()},
            'paperColor': '#F0E6FF',
            'coverColor': 1,
            'createdAt': nb.createdAt,
            'editedAt': 42,
            'folderId': null,
            'favorite': false,
            'trashedAt': null,
          },
        ),
      );
      final after = notebooks.get(nb.id)!;
      expect(after.folderId, isNull);
      expect(after.favorite, isFalse);
      expect(
        after.paper,
        const Paper(PaperStyle.dotted, look: PaperLook(dotSize: 2, header: true)),
      );
      expect(after.paperColor, PaperColor.custom(0xFFF0E6FF));
      expect(after.editedAt, 42);
      // And it round-trips through the wire format.
      expect(notebooks.dirtyRecords(10), isEmpty);
      notebooks.update(notebooks.get(nb.id)!);
      expect(notebooks.dirtyRecords(10).single.data!['paperColor'], '#F0E6FF');
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
      paper: PaperStyle.gridLarge,
      coverColor: 1,
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

    b.notebooks.trash(nb.id);
    b.folders.delete(school.id);
    await b.sync.engine.sync(apiFor(server));
    await a.sync.engine.sync(apiFor(server));
    expect(a.folders.list(), isEmpty);
    expect(a.notebooks.trashed().single.id, nb.id);
  });
}
