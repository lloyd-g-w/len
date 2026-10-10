import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/search_index.dart';
import 'package:len/data/search/search_query.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/cover_style.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text_data.dart';
import 'package:sqlite3/common.dart';

import 'data_test.dart' show FakeClock;

const _sha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// One app installation on an in-memory database with a manual clock.
class _App {
  _App() {
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    // Text of page 0 of the PDF used by [addNotebook]'s PDF page.
    db.execute("INSERT INTO pdf_text VALUES ('$_sha', 0, 'Thermodynamics lecture')");
  }

  final clock = FakeClock()..now = 1000;
  late final AppServices s;

  CommonDatabase get db => s.database.db;

  SurfaceCopier get content => SurfaceCopier(s.strokes, elements: s.elements);

  /// `kind:ref_id` → `surface_id|body` of every search document.
  Map<String, String> get searchDocs => {
    for (final r in db.select('SELECT kind, ref_id, surface_id, body FROM search_docs'))
      '${r['kind']}:${r['ref_id']}': '${r['surface_id']}|${r['body']}',
  };

  List<SearchHit> search(String query) => s.search.index.search(SearchQuery(query));

  /// Marks every row clean, as after a successful push.
  void markAllClean() {
    for (final store in s.sync.engine.stores) {
      store.markClean([
        for (final r in store.dirtyRecords(100000)) (id: r.id, updatedAt: r.updatedAt),
      ]);
    }
  }

  /// `deleted`, `dirty` and `updated_at` of row [id] of [table].
  ({bool deleted, bool dirty, int updatedAt}) state(String table, String id) {
    final row = db.select('SELECT deleted, dirty, updated_at FROM $table WHERE id = ?', [
      id,
    ]).single;
    return (
      deleted: row['deleted'] == 1,
      dirty: row['dirty'] == 1,
      updatedAt: row['updated_at'] as int,
    );
  }

  /// Chunk cells (`cx,cy`) indexed for stroke or element [id].
  Set<String> chunksOf(String id, {bool element = false}) {
    final table = element ? 'element_chunks' : 'stroke_chunks';
    final column = element ? 'element_id' : 'stroke_id';
    return {
      for (final r in db.select('SELECT cx, cy FROM $table WHERE $column = ?', [id]))
        '${r['cx']},${r['cy']}',
    };
  }

  /// A paged notebook with a ruled page (two strokes, one erased; a text
  /// box) and a PDF page (one stroke, one text box, one deleted text box),
  /// plus a canvas notebook with a stroke and a text box.
  ({Notebook paged, Notebook canvas, List<NotebookPage> pages}) addNotebooks(String name) {
    final folder = s.folders.create(name: '$name folder', color: 1);
    final paged = s.notebooks.create(
      title: '$name paged',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      paperColor: PaperColor.cream,
      coverColor: 0xFF445566,
      coverStyle: CoverStyle.stripes,
      folderId: folder.id,
    );
    final ruled = s.pages.pagesOf(paged.id).single;
    s.pages.setBookmarked(ruled.id, true);
    final pdf = s.pages.insertPages(paged.id, [
      (
        size: const Size(612, 792),
        paper: PaperStyle.blank,
        color: PaperColor.grey,
        background: const PageBackground.pdf(blob: _sha, pageIndex: 0),
      ),
    ]).single;
    final canvas = s.notebooks.create(
      title: '$name canvas',
      kind: NotebookKind.canvas,
      paper: PaperStyle.dotted,
      coverColor: 1,
    );
    s.strokes.save([
      _stroke('$name-s1', ruled.id, const Offset(10, 10)),
      _stroke('$name-s2', ruled.id, const Offset(3000, 50)),
      _stroke('$name-erased', ruled.id, const Offset(40, 40)),
      _stroke('$name-s3', pdf.id, const Offset(100, 700)),
      _stroke('$name-s4', canvas.id, const Offset(-5000, 9000)),
    ]);
    s.strokes.delete(['$name-erased']);
    s.elements.save([
      _text('$name-t1', ruled.id, '$name ruled words'),
      _text('$name-t2', pdf.id, '$name pdf words'),
      _text('$name-gone', pdf.id, '$name deleted words'),
      _text('$name-t3', canvas.id, '$name canvas words', at: const Offset(-4000, -4000)),
    ]);
    s.elements.delete(['$name-gone']);
    return (paged: paged, canvas: canvas, pages: [ruled, pdf]);
  }
}

Stroke _stroke(String id, String surface, Offset at) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.highlighter,
  color: 0xFF00AA00,
  width: 6,
  points: [StrokePoint(at.dx, at.dy, 0.5), StrokePoint(at.dx + 700, at.dy + 30, 0.75)],
  createdAt: 3,
);

SurfaceElement _text(String id, String surface, String text, {Offset at = const Offset(20, 30)}) =>
    SurfaceElement(
      id: id,
      surfaceId: surface,
      type: 'text',
      rect: Rect.fromLTWH(at.dx, at.dy, 900, 40),
      z: 2,
      createdAt: 4,
      data: {
        ...TextData(text: text).toJson(),
        'future': 1,
      },
    );

void main() {
  test('duplicate copies pages, strokes, elements, chunk rows and search rows', () {
    final app = _App();
    final src = app.addNotebooks('src');
    app.markAllClean();
    app.clock.now = 5000;

    final copy = app.s.notebooks.duplicate(src.paged.id)!;
    expect(copy.id, isNot(src.paged.id));
    expect(copy.title, 'src paged (copy)');
    final original = app.s.notebooks.get(src.paged.id)!;
    expect(copy.kind, original.kind);
    expect(copy.paper, original.paper);
    expect(copy.paperColor, original.paperColor);
    expect(copy.coverColor, original.coverColor);
    expect(copy.coverStyle, original.coverStyle);
    expect(copy.folderId, original.folderId);
    expect(copy.editedAt, 5000);
    expect(app.state('notebooks', copy.id).dirty, isTrue);

    final copiedPages = app.s.pages.pagesOf(copy.id);
    expect(copiedPages, hasLength(2));
    for (var i = 0; i < 2; i++) {
      final from = src.pages[i], to = copiedPages[i];
      expect(to.id, isNot(from.id));
      expect(to.sortKey, from.sortKey);
      expect(to.size, from.size);
      expect(to.paper, from.paper);
      expect(to.paperColor, app.s.pages.get(from.id)!.paperColor);
      expect(to.bookmarked, app.s.pages.get(from.id)!.bookmarked);
      expect(to.background, from.background);
      expect(app.state('pages', to.id).dirty, isTrue);

      // Strokes and elements: same content, new ids, same chunk cells.
      final strokes = app.content.loadAll(from.id)..sort((a, b) => a.id.compareTo(b.id));
      final copiedStrokes = app.content.loadAll(to.id);
      expect(copiedStrokes, hasLength(strokes.length));
      for (final c in copiedStrokes) {
        final s = strokes.singleWhere((s) => s.points.first == c.points.first);
        expect(c.id, isNot(s.id));
        expect(
          (c.surfaceId, c.tool, c.color, c.width, c.style),
          (to.id, s.tool, s.color, s.width, s.style),
        );
        expect(app.chunksOf(c.id), app.chunksOf(s.id));
        expect(app.chunksOf(c.id), isNotEmpty);
        expect(app.state('strokes', c.id).dirty, isTrue);
      }
      final elements = app.content.loadAllElements(from.id);
      final copiedElements = app.content.loadAllElements(to.id);
      expect(copiedElements, hasLength(elements.length));
      for (final c in copiedElements) {
        final e = elements.singleWhere((e) => e.data['text'] == c.data['text']);
        expect(c.id, isNot(e.id));
        expect((c.rect, c.z), (e.rect, e.z));
        expect(c.data, e.data);
        expect(app.chunksOf(c.id, element: true), app.chunksOf(e.id, element: true));
        expect(app.state('elements', c.id).dirty, isTrue);
        expect(app.searchDocs['text:${c.id}'], '${to.id}|${c.data['text']}');
      }
    }
    // Erased ink and deleted text boxes are not copied.
    expect(app.content.loadAll(copiedPages[0].id), hasLength(2));
    expect(app.content.loadAllElements(copiedPages[1].id), hasLength(1));
    expect(
      app.db.select('SELECT COUNT(*) AS n FROM strokes WHERE deleted = 1').single['n'],
      1,
      reason: 'no tombstones were copied',
    );

    // Search rows: the copy's title, text boxes and PDF page.
    final docs = app.searchDocs;
    expect(docs['notebook:${copy.id}'], '${copy.id}|src paged (copy)');
    expect(docs['pdf:${copiedPages[1].id}'], '${copiedPages[1].id}|Thermodynamics lecture');
    final pdfHits = app.search('thermo').where((h) => h.kind == SearchHitKind.pdf);
    expect(pdfHits.map((h) => h.notebookId), unorderedEquals([src.paged.id, copy.id]));
    expect(app.search('ruled').map((h) => h.notebookId), unorderedEquals([src.paged.id, copy.id]));

    // The original is untouched (still clean).
    expect(app.state('notebooks', src.paged.id).dirty, isFalse);
    expect(app.state('strokes', 'src-s1').dirty, isFalse);

    // Canvas notebooks are their own surface.
    final canvasCopy = app.s.notebooks.duplicate(src.canvas.id, title: 'Canvas 2')!;
    final copiedInk = app.content.loadAll(canvasCopy.id).single;
    expect(copiedInk.points, app.content.loadAll(src.canvas.id).single.points);
    expect(app.chunksOf(copiedInk.id), app.chunksOf('src-s4'));
    final copiedText = app.content.loadAllElements(canvasCopy.id).single;
    expect(copiedText.data['future'], 1);
    expect(app.searchDocs['text:${copiedText.id}'], '${canvasCopy.id}|src canvas words');
    expect(app.searchDocs['notebook:${canvasCopy.id}'], '${canvasCopy.id}|Canvas 2');
  });

  group('delete forever', () {
    void expectGone(
      _App app,
      String name,
      ({Notebook paged, Notebook canvas, List<NotebookPage> pages}) nbs,
      int before,
    ) {
      final rows = [
        ('notebooks', nbs.paged.id),
        ('notebooks', nbs.canvas.id),
        for (final p in nbs.pages) ('pages', p.id),
        for (final id in ['s1', 's2', 's3', 's4']) ('strokes', '$name-$id'),
        for (final id in ['t1', 't2', 't3']) ('elements', '$name-$id'),
      ];
      for (final (table, id) in rows) {
        final state = app.state(table, id);
        expect(state.deleted, isTrue, reason: '$table/$id tombstoned');
        expect(state.dirty, isTrue, reason: '$table/$id dirty');
        expect(state.updatedAt, greaterThan(before), reason: '$table/$id re-versioned');
      }
      for (final r in app.s.strokes.dirtyRecords(1000)) {
        if (r.id.startsWith('$name-')) expect(r.deleted, isTrue);
      }
      final surfaces = [nbs.canvas.id, ...nbs.pages.map((p) => p.id)];
      for (final surface in surfaces) {
        expect(app.content.loadAll(surface), isEmpty);
        expect(app.content.loadAllElements(surface), isEmpty);
        expect(
          app.db.select('SELECT 1 FROM stroke_chunks WHERE surface_id = ?', [surface]),
          isEmpty,
        );
        expect(
          app.db.select('SELECT 1 FROM element_chunks WHERE surface_id = ?', [surface]),
          isEmpty,
        );
      }
      final docs = app.searchDocs;
      for (final id in [nbs.paged.id, nbs.canvas.id]) {
        expect(docs.keys, isNot(contains('notebook:$id')));
      }
      for (final p in nbs.pages) {
        expect(docs.keys, isNot(contains('pdf:${p.id}')));
      }
      for (final id in ['t1', 't2', 't3']) {
        expect(docs.keys, isNot(contains('text:$name-$id')));
      }
      expect(app.search(name), isEmpty);
      expect(app.s.notebooks.get(nbs.paged.id), isNull);
      expect(app.s.pages.pagesOf(nbs.paged.id), isEmpty);
    }

    void expectIntact(
      _App app,
      String name,
      ({Notebook paged, Notebook canvas, List<NotebookPage> pages}) nbs,
    ) {
      expect(app.s.notebooks.get(nbs.paged.id), isNotNull);
      expect(app.state('notebooks', nbs.paged.id).dirty, isFalse);
      expect(app.state('strokes', '$name-s1').dirty, isFalse);
      expect(app.content.loadAll(nbs.pages[0].id), hasLength(2));
      expect(
        app.searchDocs.keys,
        containsAll(['notebook:${nbs.paged.id}', 'text:$name-t1', 'pdf:${nbs.pages[1].id}']),
      );
    }

    test('delete tombstones pages, strokes, elements and drops their search rows', () {
      final app = _App();
      final doomed = app.addNotebooks('doomed');
      final kept = app.addNotebooks('kept');
      expect(app.searchDocs.keys, contains('pdf:${doomed.pages[1].id}'));
      app.markAllClean();
      final before = app.clock.now;
      app.clock.now += 1000;

      app.s.notebooks.delete(doomed.paged.id);
      app.s.notebooks.delete(doomed.canvas.id);

      expectGone(app, 'doomed', doomed, before);
      expectIntact(app, 'kept', kept);
      // The folders survive a notebook deletion.
      expect(app.s.folders.list(), hasLength(2));
    });

    test('emptyTrash deletes exactly the trashed notebooks', () {
      final app = _App();
      final doomed = app.addNotebooks('doomed');
      final kept = app.addNotebooks('kept');
      app.s.notebooks.trash(doomed.paged.id);
      app.s.notebooks.trash(doomed.canvas.id);
      app.markAllClean();
      final before = app.clock.now;
      app.clock.now += 1000;
      expect(app.search('doomed'), isEmpty, reason: 'trashed notebooks are not found');
      expect(app.searchDocs.keys, contains('notebook:${doomed.paged.id}'));

      app.s.notebooks.emptyTrash();

      expect(app.s.notebooks.trashed(), isEmpty);
      expectGone(app, 'doomed', doomed, before);
      expectIntact(app, 'kept', kept);
      expect(
        app.s.notebooks.list().map((n) => n.id),
        unorderedEquals([kept.paged.id, kept.canvas.id]),
      );
    });
  });

  test('deleting a folder trashes the notebooks of its subtree and drops folder search rows', () {
    final app = _App();
    final folders = app.s.folders;
    final root = folders.create(name: 'Root', color: 1);
    final child = folders.create(name: 'Child', parentId: root.id, color: 1);
    final grandchild = folders.create(name: 'Grandchild', parentId: child.id, color: 1);
    final sibling = folders.create(name: 'Sibling', color: 1);
    Notebook notebookIn(String? folder, String title) => app.s.notebooks.create(
      title: title,
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
      folderId: folder,
    );
    final inRoot = notebookIn(root.id, 'In root');
    final inGrandchild = notebookIn(grandchild.id, 'In grandchild');
    final alreadyTrashed = notebookIn(child.id, 'Already trashed');
    final inSibling = notebookIn(sibling.id, 'In sibling');
    final atTop = notebookIn(null, 'At top');
    app.s.notebooks.trash(alreadyTrashed.id);
    final trashedAt = app.s.notebooks.get(alreadyTrashed.id)!.trashedAt;
    app.markAllClean();
    app.clock.now += 1000;

    final deleted = folders.delete(root.id);
    app.s.notebooks.trashAllIn(deleted);

    expect(deleted, {root.id, child.id, grandchild.id});
    for (final id in deleted) {
      final state = app.state('folders', id);
      expect((state.deleted, state.dirty), (true, true), reason: id);
      expect(app.searchDocs.keys, isNot(contains('folder:$id')));
    }
    expect(app.state('folders', sibling.id).dirty, isFalse);
    expect(folders.list().map((f) => f.id), [sibling.id]);
    expect(app.searchDocs, containsPair('folder:${sibling.id}', '${sibling.id}|Sibling'));
    expect(app.s.search.index.searchFolders(SearchQuery('child')), isEmpty);
    expect(app.s.search.index.searchFolders(SearchQuery('sib')).single.refId, sibling.id);

    final trashed = app.s.notebooks.trashed().map((n) => n.id);
    expect(trashed, unorderedEquals([inRoot.id, inGrandchild.id, alreadyTrashed.id]));
    expect(app.state('notebooks', inRoot.id).dirty, isTrue);
    expect(app.state('notebooks', inGrandchild.id).dirty, isTrue);
    expect(app.s.notebooks.get(alreadyTrashed.id)!.trashedAt, trashedAt);
    expect(app.s.notebooks.list().map((n) => n.id), unorderedEquals([inSibling.id, atTop.id]));
    expect(app.state('notebooks', inSibling.id).dirty, isFalse);
    expect(app.search('grandchild'), isEmpty, reason: 'trashed notebooks are not found');
    expect(
      app.searchDocs.keys,
      contains('notebook:${inGrandchild.id}'),
      reason: 'still restorable',
    );

    // Restoring brings it back to the library root, findable again.
    app.s.notebooks.restore(inGrandchild.id);
    expect(app.s.notebooks.get(inGrandchild.id)!.folderId, isNull);
    expect(app.search('grandchild').single.refId, inGrandchild.id);
  });
}
