import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/pdf_text_indexer.dart';
import 'package:len/data/search/pdf_text_source.dart';
import 'package:len/data/search/search_index.dart';
import 'package:len/data/search/search_query.dart';
import 'package:len/data/search/search_schema.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';

import 'support/fake_server.dart' show FakeServer, apiFor, device;

/// A PDF "reader" serving canned page texts per blob.
class FakePdfSource implements PdfTextSource {
  FakePdfSource(this.texts);

  final Map<String, List<String>> texts;
  int opened = 0;
  int pagesRead = 0;

  @override
  Future<PdfTextDocument> open(Uint8List bytes) async {
    opened++;
    final pages = texts[String.fromCharCodes(bytes)];
    if (pages == null) throw const FormatException('not a PDF');
    return _FakeDoc(this, pages);
  }
}

class _FakeDoc implements PdfTextDocument {
  _FakeDoc(this.source, this.pages);
  final FakePdfSource source;
  final List<String> pages;

  @override
  int get pageCount => pages.length;

  @override
  Future<String> pageText(int index) async {
    source.pagesRead++;
    return pages[index];
  }

  @override
  Future<PdfGlyphs?> glyphs(int index) async => null;

  @override
  Future<void> dispose() async {}
}

/// Blob ids are SHA-256 hex; the fake "file content" is the id itself.
String sha(int n) => n.toRadixString(16).padLeft(64, '0');

SurfaceElement textBox(String id, String surface, String text, {Rect? rect}) => SurfaceElement(
  id: id,
  surfaceId: surface,
  type: 'text',
  rect: rect ?? const Rect.fromLTWH(10, 20, 200, 40),
  z: 1,
  createdAt: 1,
  data: {'text': text, 'size': 24},
);

void main() {
  late AppServices s;
  late SearchIndex index;
  setUp(() {
    s = AppServices.create(AppDatabase.inMemory());
    index = s.search.index;
  });
  tearDown(() => s.dispose());

  List<SearchHit> find(String q, {String? notebookId}) =>
      index.search(SearchQuery(q), notebookId: notebookId);

  Notebook paged(String title) => s.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
  );

  test('the bundled SQLite has FTS5', () {
    expect(index.usesFts, isTrue);
    expect(
      s.database.db.select("SELECT sqlite_compileoption_used('ENABLE_FTS5') AS on_").first['on_'],
      1,
    );
  });

  test('notebook titles and folder names are indexed, renamed, trashed, deleted', () {
    final nb = paged('Organic Chemistry');
    final folder = s.folders.create(name: 'Science', color: 0);
    expect(
      find('chem').single,
      isA<SearchHit>().having((h) => h.kind, 'kind', SearchHitKind.notebookTitle),
    );
    expect(index.searchFolders(SearchQuery('sci')).single.refId, folder.id);

    s.notebooks.update(s.notebooks.get(nb.id)!.copyWith(title: 'Physics'));
    expect(find('chem'), isEmpty);
    expect(find('phys').single.notebookId, nb.id);

    s.notebooks.trash(nb.id);
    expect(find('phys'), isEmpty, reason: 'trashed notebooks are not searched');
    s.notebooks.restore(nb.id);
    expect(find('phys'), hasLength(1));
    s.notebooks.delete(nb.id);
    expect(find('phys'), isEmpty);
    s.folders.delete(folder.id);
    expect(index.searchFolders(SearchQuery('sci')), isEmpty);
  });

  test('text boxes: page numbers, edits, moves, deletes', () {
    final nb = paged('Notes');
    final first = s.pages.pagesOf(nb.id).single;
    final second = s.pages.addPage(nb.id);
    final third = s.pages.addPage(nb.id);
    s.elements.save([
      textBox('t1', second.id, 'Mitochondria are the powerhouse'),
      textBox('t2', third.id, 'More about mitosis'),
      textBox('t3', first.id, '   '), // Blank boxes are not indexed.
    ]);
    final hits = find('mito', notebookId: nb.id);
    expect([for (final h in hits) (h.refId, h.pageIndex)], [('t1', 1), ('t2', 2)]);
    expect(hits.first.surfaceId, second.id);
    expect(hits.first.kind, SearchHitKind.text);

    // Moving a box does not touch the index row.
    final rowId = s.database.db
        .select("SELECT id FROM search_docs WHERE ref_id = 't1'")
        .single['id'];
    s.elements.save([
      textBox(
        't1',
        second.id,
        'Mitochondria are the powerhouse',
        rect: const Rect.fromLTWH(99, 99, 50, 50),
      ),
    ]);
    expect(
      s.database.db.select("SELECT id FROM search_docs WHERE ref_id = 't1'").single['id'],
      rowId,
    );

    s.elements.save([textBox('t1', second.id, 'Ribosomes')]);
    expect(find('mitochondria'), isEmpty);
    expect(find('ribo').single.refId, 't1');

    s.elements.delete(['t2']);
    expect(find('mitosis'), isEmpty);

    // Deleting the page hides its boxes; reordering renumbers.
    s.pages.delete(second.id);
    expect(find('ribo'), isEmpty);
  });

  test('canvas text boxes have no page number; images are not indexed', () {
    final canvas = s.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    s.elements.save([
      textBox('c1', canvas.id, 'Quarterly roadmap'),
      SurfaceElement(
        id: 'img',
        surfaceId: canvas.id,
        type: 'image',
        rect: Rect.zero,
        z: 0,
        createdAt: 1,
        data: const {'text': 'roadmap'},
      ),
    ]);
    final hit = find('roadmap').single;
    expect(
      (hit.refId, hit.notebookId, hit.surfaceId, hit.pageIndex),
      ('c1', canvas.id, canvas.id, null),
    );
  });

  test('ranking prefers matches of every word, accents and case are folded', () {
    final nb = paged('Café notes');
    final page = s.pages.pagesOf(nb.id).single;
    s.elements.save([
      textBox('a', page.id, 'The cafe opens at nine; cafe, cafe, CAFÉ!'),
      textBox(
        'b',
        page.id,
        'A long unrelated paragraph that mentions a café only once among '
            'many other words about trains, weather, groceries and errands',
      ),
    ]);
    final hits = find('CAFE');
    expect(hits.map((h) => h.refId), containsAll(['a', 'b', nb.id]));
    expect(
      hits.indexWhere((h) => h.refId == 'a'),
      lessThan(hits.indexWhere((h) => h.refId == 'b')),
    );
    expect(find('cafe nine').single.refId, 'a', reason: 'all words must match');
    expect(find('afe'), isEmpty, reason: 'terms match word prefixes only');
  });

  test('records applied by sync are indexed (element, notebook, tombstones)', () {
    final nb = paged('Remote');
    final page = s.pages.pagesOf(nb.id).single;
    final record = SyncRecord(
      collection: 'elements',
      id: 'remote-1',
      updatedAt: 5000,
      deviceId: 'other',
      deleted: false,
      data: {
        'surfaceId': page.id,
        'type': 'text',
        'x': 0,
        'y': 0,
        'w': 100,
        'h': 20,
        'createdAt': 1,
        'data': {'text': 'Synchronised photosynthesis'},
      },
    );
    expect(s.elements.applyRemote(record), isTrue);
    expect(find('photo').single.refId, 'remote-1');
    s.elements.applyRemote(
      SyncRecord(
        collection: 'elements',
        id: 'remote-1',
        updatedAt: 6000,
        deviceId: 'other',
        deleted: true,
        data: null,
      ),
    );
    expect(find('photo'), isEmpty);
  });

  test('two devices: text typed on one is found on the other after sync', () async {
    final server = FakeServer();
    final a = device(server);
    final b = device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final nb = a.notebooks.create(
      title: 'Shared lab book',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = a.pages.pagesOf(nb.id).single;
    a.elements.save([textBox('x', page.id, 'Titration results')]);
    await a.sync.engine.sync(apiFor(server));
    await b.sync.engine.sync(apiFor(server));
    final hit = b.search.search('titration').single;
    expect((hit.notebookId, hit.pageIndex), (nb.id, 0));
    expect(b.search.search('lab').single.kind, SearchHitKind.notebookTitle);

    // Edited on B, renamed on A: both reach the other side.
    b.elements.save([textBox('x', page.id, 'Chromatography results')]);
    a.notebooks.update(a.notebooks.get(nb.id)!.copyWith(title: 'Renamed'));
    await b.sync.engine.sync(apiFor(server));
    await a.sync.engine.sync(apiFor(server));
    await b.sync.engine.sync(apiFor(server));
    expect(a.search.search('titration'), isEmpty);
    expect(a.search.search('chromato').single.refId, 'x');
    expect(b.search.search('renamed').single.notebookId, nb.id);
    expect(b.search.search('lab'), isEmpty);
  });

  group('PDF text', () {
    late FakePdfSource source;
    late PdfTextIndexer indexer;
    final blobs = <String, Uint8List>{};

    setUp(() {
      blobs.clear();
      source = FakePdfSource({
        sha(1): ['Introduction to thermodynamics', '', 'Entropy always increases'],
        sha(2): ['Broken'],
      });
      indexer = PdfTextIndexer(
        s.database,
        readBlob: (id) async => blobs[id],
        source: source,
        batchSize: 2,
      );
    });
    tearDown(() => indexer.dispose());

    Notebook importPdf(String title, String blob, int pages) {
      final nb = paged(title);
      final blank = s.pages.pagesOf(nb.id).single;
      s.pages.insertPages(nb.id, [
        for (var i = 0; i < pages; i++)
          (
            size: const Size(600, 800),
            paper: PaperStyle.blank,
            color: PaperColor.white,
            background: PageBackground.pdf(blob: blob, pageIndex: i),
          ),
      ]);
      s.pages.delete(blank.id);
      return nb;
    }

    test('extracts each blob once, indexes every page showing it', () async {
      final lecture = importPdf('Lecture', sha(1), 3);
      final copy = importPdf('Copy', sha(1), 3);
      expect(indexer.pendingBlobs(), [sha(1)]);
      await indexer.schedule();
      expect(indexer.pendingBlobs(), [sha(1)], reason: 'the blob is not on this device yet');
      expect(source.opened, 0);

      blobs[sha(1)] = Uint8List.fromList(sha(1).codeUnits);
      await indexer.schedule(retryFailed: true);
      expect(indexer.pendingBlobs(), isEmpty);
      expect(source.opened, 1);
      expect(source.pagesRead, 3);

      final hits = find('entropy');
      expect(
        {for (final h in hits) (h.notebookId, h.pageIndex, h.kind)},
        {(lecture.id, 2, SearchHitKind.pdf), (copy.id, 2, SearchHitKind.pdf)},
      );

      // Pages added later with the same PDF are indexed by the trigger.
      final more = importPdf('Third', sha(1), 1);
      expect(find('thermo').map((h) => h.notebookId), contains(more.id));
      await indexer.schedule();
      expect(source.opened, 1);

      // Deleting a page drops it from results.
      s.pages.delete(s.pages.pagesOf(lecture.id)[2].id);
      expect(find('entropy').single.notebookId, copy.id);
    });

    test('unreadable PDFs are skipped this session and retried later', () async {
      importPdf('Bad', sha(3), 1);
      blobs[sha(3)] = Uint8List.fromList('garbage'.codeUnits);
      await indexer.schedule();
      await indexer.schedule();
      expect(source.opened, 1);
      expect(indexer.pendingBlobs(), [sha(3)]);
    });

    test('an interrupted extraction resumes without re-reading pages', () async {
      importPdf('Lecture', sha(1), 3);
      s.database.db.execute(
        "INSERT INTO pdf_text (blob, page, text) VALUES (?, 0, 'Introduction to thermodynamics')",
        [sha(1)],
      );
      blobs[sha(1)] = Uint8List.fromList(sha(1).codeUnits);
      await indexer.schedule();
      expect(source.pagesRead, 2);
      expect(find('entropy'), hasLength(1));
    });
  });

  test('rebuild and re-running the migration reproduce the trigger-maintained index', () {
    final nb = paged('Alpha');
    s.elements.save([textBox('t', s.pages.pagesOf(nb.id).single.id, 'beta gamma')]);
    final before = s.database.db.select(
      'SELECT kind, ref_id, body FROM search_docs ORDER BY ref_id',
    );
    index.rebuild();
    SearchSchema.create(s.database.db);
    final after = s.database.db.select(
      'SELECT kind, ref_id, body FROM search_docs ORDER BY ref_id',
    );
    expect(after.map((r) => r.values), before.map((r) => r.values));
    expect(find('gam').single.refId, 't');
  });

  test('the migration indexes existing data (and is idempotent)', () {
    final dir = Directory.systemTemp.createTempSync('len_search_mig_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/len.db';
    var db = AppDatabase.open(path);
    // Simulate a database from before search: data, no index.
    for (final t in ['search_fts', 'search_docs', 'pdf_text', 'pdf_text_blobs']) {
      db.db.execute('DROP TABLE IF EXISTS $t');
    }
    for (final r in db.db.select("SELECT name FROM sqlite_master WHERE type = 'trigger'")) {
      db.db.execute('DROP TRIGGER ${r['name']}');
    }
    db.db.execute(
      'INSERT INTO notebooks (id, title, kind, paper, cover_color, created_at, updated_at, '
      "device_id) VALUES ('n', 'Old Physics', 'canvas', 'blank', 0, 1, 1, 'd')",
    );
    db.db.execute('PRAGMA user_version = ${AppDatabase.versionBeforeSearchIndex}');
    db.close();

    db = AppDatabase.open(path);
    addTearDown(db.close);
    expect(SearchIndex(db).search(SearchQuery('physics')).single.notebookId, 'n');
    SearchSchema.create(db.db); // Re-running changes nothing.
    expect(SearchIndex(db).search(SearchQuery('physics')), hasLength(1));
  });

  test('without FTS5 queries fall back to LIKE with the same word rules', () {
    final like = SearchIndex(s.database, preferFts: false);
    final nb = paged('Fallback');
    s.elements.save([textBox('t', s.pages.pagesOf(nb.id).single.id, 'Graph theory 101_%')]);
    expect(like.usesFts, isFalse);
    expect(like.search(SearchQuery('theo')).single.refId, 't');
    expect(like.search(SearchQuery('heory')), isEmpty);
    expect(like.search(SearchQuery('fall')).single.kind, SearchHitKind.notebookTitle);
  });

  group('SearchQuery', () {
    test('folds case and accents, keeps offsets', () {
      expect(SearchText.fold('Ça Éclaire ŁÓDŹ'), 'ca eclaire lodz');
      final q = SearchQuery('ecl');
      expect(q.ranges('Ça Éclaire'), [(start: 3, end: 6)]);
    });

    test('ranges merge overlaps and only match word starts', () {
      final q = SearchQuery('the them');
      expect(q.ranges('them, theme; other'), [(start: 0, end: 4), (start: 6, end: 10)]);
      expect(q.ftsExpression, '"them"* "the"*');
    });

    test('snippets centre on the first match with ellipses', () {
      final body = '${'word ' * 30}the needle is here ${'tail ' * 30}';
      final snippet = SearchSnippet.of(body, SearchQuery('needle'));
      expect(snippet.text, startsWith('…'));
      expect(snippet.text, endsWith('…'));
      final h = snippet.highlights.single;
      expect(snippet.text.substring(h.start, h.end), 'needle');
      expect(SearchSnippet.of('short needle', SearchQuery('needle')).text, 'short needle');
    });
  });
}
