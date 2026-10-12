import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/search_index.dart';
import 'package:len/data/search/search_query.dart';
import 'package:len/data/search/search_schema.dart';
import 'package:len/data/stroke_codec.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/sync/blob_sync.dart';
import 'package:len/sync/sync_engine.dart';
import 'package:sqlite3/common.dart';

import 'support/fake_server.dart';

// -----------------------------------------------------------------------------
// Two devices, one server: every collection in both directions.

/// Wall-clock time shared by the devices of a test (plus per-device skew).
class _Time {
  int now = 1000;
  void tick([int ms = 10]) => now += ms;
}

class _DeviceClock extends Clock {
  _DeviceClock(this.time, this.prefix);

  final _Time time;
  final String prefix;
  int skew = 0;
  int _ids = 0;

  @override
  int nowMs() => time.now + skew;

  /// Ids are unique per device ('a0', 'a1', … / 'b0', …); the first one is
  /// the device id, so device 'b' wins LWW ties against device 'a'.
  @override
  String newId() => '$prefix${_ids++}';
}

/// An app installation with its own in-memory database.
class _Device {
  _Device(this.server, _Time time, String prefix) : clock = _DeviceClock(time, prefix) {
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
  }

  final FakeServer server;
  final _DeviceClock clock;
  late final AppServices s;

  Future<RemoteChanges> sync() => s.sync.engine.sync(apiFor(server));

  SurfaceCopier get content => SurfaceCopier(s.strokes, elements: s.elements);

  CommonDatabase get db => s.database.db;

  /// `kind:ref_id` → body of every search document.
  Map<String, String> get searchDocs => {
    for (final r in db.select('SELECT kind, ref_id, body FROM search_docs'))
      '${r['kind']}:${r['ref_id']}': r['body'] as String,
  };

  List<SearchHit> search(String query) => s.search.index.search(SearchQuery(query));

  /// Every row with unpushed changes, in any synced table.
  List<SyncRecord> get dirty => [
    for (final store in s.sync.engine.stores) ...store.dirtyRecords(1000),
  ];

  /// Whether row [id] of [table] is a tombstone (null if unknown).
  bool? deleted(String table, String id) {
    final rows = db.select('SELECT deleted FROM $table WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first['deleted'] == 1;
  }
}

/// Two devices on one fresh server.
(_Time, FakeServer, _Device, _Device) _twoDevices() {
  final time = _Time();
  final server = FakeServer();
  return (time, server, _Device(server, time, 'a'), _Device(server, time, 'b'));
}

/// Syncs [from] and then [to], so [to] sees everything [from] did.
Future<void> _send(_Device from, _Device to) async {
  await from.sync();
  await to.sync();
}

Map<String, Object?> _record(
  String collection,
  String id,
  int updatedAt, {
  Map<String, Object?>? data,
  String deviceId = 'remote',
}) => {
  'collection': collection,
  'id': id,
  'updatedAt': updatedAt,
  'deviceId': deviceId,
  'deleted': data == null,
  'data': data,
};

/// A complete `notebooks` payload (every field is required on the wire).
Map<String, Object?> _notebookData(String title, {String kind = 'canvas'}) => {
  'title': title,
  'kind': kind,
  'paper': 'blank',
  'paperData': {'look': PaperLook.standard.toJson()},
  'paperColor': 'white',
  'coverColor': 0,
  'createdAt': 1,
  'editedAt': 1,
  'folderId': null,
  'favorite': false,
  'trashedAt': null,
};

/// A complete `pages` payload.
Map<String, Object?> _pageData(String notebookId, {Object? background}) => {
  'notebookId': notebookId,
  'sortKey': 1.0,
  'width': 600,
  'height': 800,
  'paper': 'blank',
  'paperData': {'look': PaperLook.standard.toJson()},
  'paperColor': 'white',
  'bookmarked': false,
  'background': background,
};

/// A complete `elements` payload of a text box.
Map<String, Object?> _textData(String surfaceId, String text, {double w = 100, double h = 20}) => {
  'surfaceId': surfaceId,
  'type': 'text',
  'x': 0,
  'y': 0,
  'w': w,
  'h': h,
  'rotation': 0,
  'z': 1,
  'createdAt': 1,
  'data': {'text': text},
};

String _points(List<StrokePoint> points) => base64Encode(StrokeCodec.encode(points));

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

SurfaceElement _textBox(
  String id,
  String surface,
  String text, {
  Rect rect = const Rect.fromLTWH(10, 20, 200, 50),
  Map<String, Object?> extra = const {},
}) => SurfaceElement(
  id: id,
  surfaceId: surface,
  type: 'text',
  rect: rect,
  rotation: 0.5,
  z: 3,
  createdAt: 7,
  data: {
    ...TextData.rich(
      text: text,
      spans: [StyledRange(0, text.length, const SpanStyle(bold: true, color: 0xFFC2255C))],
      paras: const [ParaStyle(list: ListKind.check, checked: true)],
      font: TextFont.caveat,
      align: TextAlignment.center,
    ).toJson(),
    ...extra,
  },
);

Stroke _stroke(String id, String surface, {InkTool tool = InkTool.ballpoint, StrokeStyle? style}) =>
    Stroke(
      id: id,
      surfaceId: surface,
      tool: tool,
      color: 0xFF102030,
      width: 4.5,
      points: const [StrokePoint(1, 2, 0.25), StrokePoint(30.5, 40, 0.75), StrokePoint(60, 8, 1)],
      createdAt: 5,
      style: style,
    );

void main() {
  group('two devices', () {
    test('folders: create, rename, nest, delete subtree', () async {
      final (time, _, a, b) = _twoDevices();
      final school = a.s.folders.create(name: 'School', color: 1);
      final math = a.s.folders.create(name: 'Math', parentId: school.id, color: 2);
      final algebra = a.s.folders.create(name: 'Algebra', parentId: math.id, color: 3);
      final other = a.s.folders.create(name: 'Other', color: 4);
      final homework = a.s.notebooks.create(
        title: 'Homework',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
        folderId: algebra.id,
      );
      await a.sync();
      final changes = await b.sync();
      expect(changes.folders, isTrue);
      expect(b.s.folders.childrenOf(null).map((f) => f.name), ['Other', 'School']);
      expect(b.s.folders.childrenOf(school.id).single.id, math.id);
      final syncedAlgebra = b.s.folders.get(algebra.id)!;
      expect(syncedAlgebra.parentId, math.id);
      expect(syncedAlgebra.color, 3);
      expect(syncedAlgebra.createdAt, algebra.createdAt);
      expect(b.searchDocs, containsPair('folder:${algebra.id}', 'Algebra'));

      // Rename on B.
      time.tick();
      b.s.folders.update(b.s.folders.get(math.id)!.copyWith(name: 'Maths'));
      await _send(b, a);
      expect(a.s.folders.get(math.id)!.name, 'Maths');
      expect(a.s.search.index.searchFolders(SearchQuery('maths')).map((h) => h.refId), [math.id]);

      // Nest on A, un-nest on B.
      time.tick();
      a.s.folders.move(other.id, school.id);
      await _send(a, b);
      expect(b.s.folders.get(other.id)!.parentId, school.id);
      time.tick();
      b.s.folders.move(math.id, null);
      await _send(b, a);
      expect(a.s.folders.childrenOf(null).map((f) => f.id), unorderedEquals([school.id, math.id]));
      expect(a.s.folders.pathTo(algebra.id).map((f) => f.id), [math.id, algebra.id]);

      // Delete Math with its subtree on A (as the library does).
      time.tick();
      a.s.notebooks.trashAllIn(a.s.folders.delete(math.id));
      await _send(a, b);
      expect(b.s.folders.get(math.id), isNull);
      expect(b.s.folders.get(algebra.id), isNull);
      expect(b.s.folders.list().map((f) => f.id), unorderedEquals([school.id, other.id]));
      expect(b.s.notebooks.get(homework.id)!.isTrashed, isTrue);
      expect(b.searchDocs.keys, isNot(contains('folder:${math.id}')));
      expect(b.searchDocs.keys, isNot(contains('folder:${algebra.id}')));
      expect(b.dirty, isEmpty);
      await a.sync();
      expect(a.dirty, isEmpty);
    });

    test('notebooks: every optional field, trash and restore', () async {
      final (time, _, a, b) = _twoDevices();
      final folder = a.s.folders.create(name: 'Journals', color: 1);
      final created = a.s.notebooks.create(
        title: 'Journal',
        kind: NotebookKind.canvas,
        paper: PaperStyle.isometric,
        coverColor: 0xFF112233,
        paperColor: PaperColor.dark,
        folderId: folder.id,
      );
      time.tick();
      a.s.notebooks.setFavorite(created.id, true);
      time.tick();
      a.s.notebooks.touch(created.id);
      time.tick();
      a.s.notebooks.setFavorite(created.id, true); // Organising after the edit.
      await _send(a, b);

      void expectSame(Notebook? got, Notebook want) {
        expect(got, isNotNull);
        expect(got!.title, want.title);
        expect(got.kind, want.kind);
        expect(got.paper, want.paper);
        expect(got.paperColor, want.paperColor);
        expect(got.coverColor, want.coverColor);
        expect(got.createdAt, want.createdAt);
        expect(got.updatedAt, want.updatedAt);
        expect(got.editedAt, want.editedAt);
        expect(got.folderId, want.folderId);
        expect(got.favorite, want.favorite);
        expect(got.trashedAt, want.trashedAt);
      }

      final onA = a.s.notebooks.get(created.id)!;
      expect(onA.favorite, isTrue);
      expect(onA.editedAt, lessThan(onA.updatedAt));
      expectSame(b.s.notebooks.get(created.id), onA);

      // Trash on B.
      time.tick();
      b.s.notebooks.trash(created.id);
      await _send(b, a);
      expectSame(a.s.notebooks.get(created.id), b.s.notebooks.get(created.id)!);
      expect(a.s.notebooks.get(created.id)!.trashedAt, time.now);
      expect(a.s.notebooks.trashed().map((n) => n.id), [created.id]);
      expect(a.s.notebooks.list(), isEmpty);
      expect(a.search('journal'), isEmpty, reason: 'trashed notebooks are not found');

      // Restore on A.
      time.tick();
      a.s.notebooks.restore(created.id);
      await _send(a, b);
      expect(b.s.notebooks.get(created.id)!.trashedAt, isNull);
      expect(b.s.notebooks.get(created.id)!.folderId, folder.id);
      expect(b.s.notebooks.list().map((n) => n.id), [created.id]);

      // Clear optional fields on B: root, unstarred, other cover and paper.
      time.tick();
      b.s.notebooks.update(
        b.s.notebooks
            .get(created.id)!
            .copyWith(
              folderId: null,
              favorite: false,
              paperColor: PaperColor.cream,
              paper: const Paper(PaperStyle.music),
            ),
      );
      await _send(b, a);
      expectSame(a.s.notebooks.get(created.id), b.s.notebooks.get(created.id)!);
      expect(a.s.notebooks.get(created.id)!.folderId, isNull);
      expect(a.s.notebooks.get(created.id)!.paperColor, PaperColor.cream);
      expect(a.dirty, isEmpty);
    });

    test('notebooks: delete forever tombstones pages, strokes and elements remotely', () async {
      final (time, server, a, b) = _twoDevices();
      final paged = a.s.notebooks.create(
        title: 'Doomed paged',
        kind: NotebookKind.paged,
        paper: PaperStyle.wideRuled,
        coverColor: 0,
      );
      final p1 = a.s.pages.pagesOf(paged.id).single;
      final p2 = a.s.pages.addPage(paged.id, after: p1);
      final canvas = a.s.notebooks.create(
        title: 'Doomed canvas',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      a.s.strokes.save([_stroke('s1', p1.id), _stroke('s2', p2.id), _stroke('s3', canvas.id)]);
      a.s.elements.save([
        _textBox('e1', p2.id, 'paged words'),
        _textBox('e2', canvas.id, 'canvas words'),
      ]);
      await _send(a, b);
      expect(b.content.loadAll(p1.id), hasLength(1));
      expect(b.searchDocs, containsPair('text:e1', 'paged words'));

      time.tick();
      a.s.notebooks.delete(paged.id);
      a.s.notebooks.trash(canvas.id);
      a.s.notebooks.emptyTrash();
      await a.sync();
      final changes = await b.sync();

      expect(changes.notebooks, isTrue);
      expect(changes.pagesOfNotebooks, contains(paged.id));
      expect(changes.strokeSurfaces, containsAll([p1.id, p2.id, canvas.id]));
      expect(b.s.notebooks.get(paged.id), isNull);
      expect(b.s.notebooks.get(canvas.id), isNull);
      expect(b.s.pages.pagesOf(paged.id), isEmpty);
      for (final (table, id) in [
        ('notebooks', paged.id),
        ('notebooks', canvas.id),
        ('pages', p1.id),
        ('pages', p2.id),
        ('strokes', 's1'),
        ('strokes', 's2'),
        ('strokes', 's3'),
        ('elements', 'e1'),
        ('elements', 'e2'),
      ]) {
        expect(b.deleted(table, id), isTrue, reason: '$table/$id on B');
        expect(server.stored(table, id)!['deleted'], isTrue, reason: '$table/$id on the server');
      }
      for (final surface in [p1.id, p2.id, canvas.id]) {
        expect(b.content.loadAll(surface), isEmpty);
        expect(b.content.loadAllElements(surface), isEmpty);
      }
      expect(b.db.select('SELECT * FROM stroke_chunks'), isEmpty);
      expect(b.db.select('SELECT * FROM element_chunks'), isEmpty);
      expect(b.searchDocs, isEmpty);
      expect(b.dirty, isEmpty);
    });

    test('pages: order, paper, colour, bookmarks, PDF backgrounds, deletion', () async {
      final (time, _, a, b) = _twoDevices();
      final nb = a.s.notebooks.create(
        title: 'Doc',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final p1 = a.s.pages.pagesOf(nb.id).single;
      final p2 = a.s.pages.addPage(nb.id, after: p1);
      final p3 = a.s.pages.addPage(nb.id, after: p2);
      final pdf = a.s.pages.insertPages(nb.id, [
        (
          size: const Size(612, 792),
          paper: Paper(PaperStyle.blank),
          color: PaperColor.white,
          background: const PageBackground.pdf(blob: _sha, pageIndex: 2),
        ),
      ]).single;
      time.tick();
      a.s.pages.move(p3, 0);
      a.s.pages.setPaper([p2.id], paper: Paper(PaperStyle.gridSmall), color: PaperColor.cream);
      a.s.pages.setBookmarked(p1.id, true);
      final changes = await (() async {
        await a.sync();
        return b.sync();
      })();
      expect(changes.pagesOfNotebooks, {nb.id});

      List<String> order(_Device d) => d.s.pages.pagesOf(nb.id).map((p) => p.id).toList();
      expect(order(a), [p3.id, p1.id, p2.id, pdf.id]);
      expect(order(b), order(a));
      expect(
        b.s.pages.pagesOf(nb.id).map((p) => p.sortKey),
        a.s.pages.pagesOf(nb.id).map((p) => p.sortKey),
      );
      final b2 = b.s.pages.get(p2.id)!;
      expect(b2.paper.style, PaperStyle.gridSmall);
      expect(b2.paperColor, PaperColor.cream);
      expect(b.s.pages.get(p1.id)!.bookmarked, isTrue);
      expect(b.s.pages.get(p3.id)!.bookmarked, isFalse);
      final bPdf = b.s.pages.get(pdf.id)!;
      expect(bPdf.background, const PageBackground.pdf(blob: _sha, pageIndex: 2));
      expect(bPdf.size, const Size(612, 792));
      expect(b.s.pages.referencedBlobs(), {_sha});

      // B reorders, recolours and unbookmarks; A follows.
      time.tick();
      b.s.pages.move(b.s.pages.get(p3.id)!, 3);
      b.s.pages.setBookmarked(p1.id, false);
      b.s.pages.setPaper([pdf.id], color: PaperColor.dark);
      await _send(b, a);
      expect(order(a), [p1.id, p2.id, pdf.id, p3.id]);
      expect(a.s.pages.get(p1.id)!.bookmarked, isFalse);
      expect(a.s.pages.get(pdf.id)!.paperColor, PaperColor.dark);
      expect(a.s.pages.get(pdf.id)!.background, isNotNull, reason: 'background kept');

      // A deletes a page (as the editor does).
      time.tick();
      a.s.strokes.deleteSurfaces([p2.id]);
      a.s.elements.deleteSurfaces([p2.id]);
      a.s.pages.delete(p2.id);
      await _send(a, b);
      expect(order(b), [p1.id, pdf.id, p3.id]);
      expect(a.dirty, isEmpty);
      expect(b.dirty, isEmpty);
    });

    test('templates: planner pages, image templates and My templates', () async {
      final (time, server, a, b) = _twoDevices();
      final plan = PlannerPlan(start: DateTime.utc(2024, 2, 1), linked: true);
      final nb = a.s.notebooks.create(
        title: 'Planner',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
        papers: plan.papersFor(PaperStyle.monthlyCalendar),
      );
      final mine = a.s.templates.create(name: 'Grid A', blob: _sha, size: const Size(800, 600));
      final first = a.s.pages.pagesOf(nb.id).first;
      a.s.pages.setPaper([first.id], paper: Paper.image(_sha));
      await _send(a, b);

      List<Paper> papers(_Device d) => [for (final p in d.s.pages.pagesOf(nb.id)) p.paper];
      expect(papers(b), papers(a));
      expect(papers(b).first, Paper.image(_sha));
      expect(papers(b)[1], Paper.planner(PaperStyle.weeklyPlanner, DateTime.utc(2024, 1, 29)));
      expect(papers(b).where((p) => p.style == PaperStyle.dailyPlanner), hasLength(35));
      final leapDay = Paper.planner(PaperStyle.dailyPlanner, DateTime.utc(2024, 2, 29));
      final leapPage = a.s.pages.pagesOf(nb.id).singleWhere((p) => p.paper == leapDay);
      expect(server.stored('pages', leapPage.id)!['data'], containsPair('paper', 'dailyPlanner'));
      expect((server.stored('pages', leapPage.id)!['data']! as Map)['paperData'], {
        'date': '2024-02-29',
        'weekStart': 'monday',
        'locale': 'en-GB',
        'look': PaperLook.standard.toJson(),
      });
      expect(b.s.templates.list().single.name, 'Grid A');
      expect(b.s.templates.list().single.size, const Size(800, 600));

      time.tick();
      b.s.templates.rename(mine.id, 'Grid B');
      await _send(b, a);
      expect(a.s.templates.get(mine.id)!.name, 'Grid B');
      time.tick();
      a.s.templates.delete(mine.id);
      final changes = await (() async {
        await a.sync();
        return b.sync();
      })();
      expect(changes.templates, isTrue);
      expect(b.s.templates.list(), isEmpty);
      expect(b.s.pages.get(first.id)!.paper, Paper.image(_sha), reason: 'pages keep the image');

      // Malformed template records and planner pages are skipped.
      server.injected.addAll([
        _record(
          'templates',
          'no-blob',
          10,
          data: {'name': 'x', 'width': 1, 'height': 1, 'createdAt': 0},
        ),
        _record(
          'templates',
          'bad-blob',
          10,
          data: {'name': 'x', 'blob': 'abc', 'width': 1, 'height': 1, 'createdAt': 0},
        ),
        _record('pages', 'undated', 10, data: {..._pageData(nb.id), 'paper': 'dailyPlanner'}),
        for (final (id, paperData) in [
          ('no-locale', {'date': '2024-02-29', 'weekStart': 'monday'}),
          ('no-week-start', {'date': '2024-02-29', 'locale': 'de'}),
          ('bad-locale', {'date': '2024-02-29', 'weekStart': 'monday', 'locale': 'xx'}),
          ('bad-week-start', {'date': '2024-02-29', 'weekStart': 'friday', 'locale': 'de'}),
        ])
          _record(
            'pages',
            id,
            10,
            data: {
              ..._pageData(nb.id),
              'paper': 'yearlyOverview',
              'paperData': {...paperData, 'look': PaperLook.standard.toJson()},
            },
          ),
        _record(
          'pages',
          'sunday-year',
          10,
          data: {
            ..._pageData(nb.id),
            'paper': 'yearlyOverview',
            'paperData': {
              'date': '2024-01-01',
              'weekStart': 'sunday',
              'locale': 'el',
              'look': PaperLook.standard.toJson(),
            },
          },
        ),
        _record(
          'notebooks',
          'planner-default',
          10,
          data: {..._notebookData('P'), 'paper': 'weeklyPlanner'},
        ),
      ]);
      await b.sync();
      expect(b.s.templates.get('no-blob'), isNull);
      expect(b.s.templates.get('bad-blob'), isNull);
      expect(b.s.pages.get('undated'), isNull);
      for (final id in ['no-locale', 'no-week-start', 'bad-locale', 'bad-week-start']) {
        expect(b.s.pages.get(id), isNull, reason: id);
      }
      expect(
        b.s.pages.get('sunday-year')!.paper,
        Paper.planner(
          PaperStyle.yearlyOverview,
          DateTime.utc(2024),
          calendar: const PlannerCalendar(
            weekStart: WeekStart.sunday,
            language: PlannerLanguage.el,
          ),
        ),
      );
      expect(b.s.notebooks.get('planner-default'), isNull);
    });

    test('recordings: audio, waveform, segments, rename and delete', () async {
      final (time, server, a, b) = _twoDevices();
      final nb = a.s.notebooks.create(
        title: 'Lecture',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final wave = 'b' * 64;
      final r = a.s.recordings.save(
        notebookId: nb.id,
        parts: [RecordingPart(_sha, 2000)],
        mime: 'audio/webm',
        title: 'Talk',
        segments: const [RecordingSegment(5000, 1200), RecordingSegment(9000, 800)],
        waveform: wave,
      );
      var changes = await (() async {
        await a.sync();
        return b.sync();
      })();
      expect(changes.recordingsOfNotebooks, {nb.id});
      final got = b.s.recordings.get(r.id)!;
      expect(
        (got.notebookId, got.blobs.single, got.mime, got.title, got.waveform, got.durationMs),
        (nb.id, _sha, 'audio/webm', 'Talk', wave, 2000),
      );
      expect(got.startedAt, 5000);
      expect(got.segments, r.segments);

      time.tick();
      b.s.recordings.rename(r.id, 'Renamed');
      await _send(b, a);
      expect(a.s.recordings.get(r.id)!.title, 'Renamed');
      expect(a.s.recordings.get(r.id)!.waveform, wave, reason: 'kept through edits');

      time.tick();
      a.s.recordings.delete(r.id);
      changes = await (() async {
        await a.sync();
        return b.sync();
      })();
      expect(changes.recordingsOfNotebooks, {nb.id});
      expect(b.s.recordings.listOf(nb.id), isEmpty);
      expect(b.deleted('recordings', r.id), isTrue);

      // A malformed waveform id is skipped; one without a waveform is fine.
      Map<String, Object?> data(String waveform) => {
        'notebookId': nb.id,
        'audio': [
          [_sha, 1000],
        ],
        'durationMs': 1000,
        'startedAt': 1,
        'title': 'x',
        'mime': 'audio/mp4',
        'segments': [
          [1, 1000],
        ],
        'waveform': waveform,
        'trimStartMs': 0,
        'trimEndMs': 1000,
      };
      server.injected.addAll([
        _record('recordings', 'bad-wave', 10, data: data('xyz')),
        _record('recordings', 'no-wave', 10, data: data('')),
      ]);
      await b.sync();
      expect(b.s.recordings.get('bad-wave'), isNull);
      expect(b.s.recordings.get('no-wave')!.waveform, '');
    });

    test('strokes: tool, colour, width, points and style', () async {
      final (time, _, a, b) = _twoDevices();
      final nb = a.s.notebooks.create(
        title: 'Ink',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      const style = StrokeStyle(
        opacity: 0.375,
        thinning: 0.125,
        streamline: 0.75,
        taperStart: 20,
        taperEnd: 15,
      );
      a.s.strokes.save([
        _stroke('hl', nb.id, tool: InkTool.highlighter, style: style),
        _stroke('bp', nb.id),
        _stroke('old', nb.id, tool: InkTool.pen),
      ]);
      await a.sync();
      final changes = await b.sync();
      expect(changes.strokeSurfaces, {nb.id});

      final want = {for (final s in a.content.loadAll(nb.id)) s.id: s};
      final got = {for (final s in b.content.loadAll(nb.id)) s.id: s};
      expect(got.keys, unorderedEquals(want.keys));
      for (final id in want.keys) {
        expect(got[id]!.tool, want[id]!.tool, reason: id);
        expect(got[id]!.color, want[id]!.color, reason: id);
        expect(got[id]!.width, want[id]!.width, reason: id);
        expect(got[id]!.points, want[id]!.points, reason: id);
        expect(got[id]!.createdAt, want[id]!.createdAt, reason: id);
        expect(got[id]!.style, want[id]!.style, reason: id);
        expect(got[id]!.bounds, want[id]!.bounds, reason: id);
      }
      expect(got['hl']!.style, style);
      expect(got['bp']!.style, StrokeStyle.defaultsFor(InkTool.ballpoint));
      expect(b.s.strokes.chunkDensity(nb.id), a.s.strokes.chunkDensity(nb.id));

      // B erases one; A follows.
      time.tick();
      b.s.strokes.delete(['hl']);
      final back = await (() async {
        await b.sync();
        return a.sync();
      })();
      expect(back.strokeSurfaces, {nb.id});
      expect(a.content.loadAll(nb.id).map((s) => s.id), unorderedEquals(['bp', 'old']));
    });

    test('elements: text box create, edit, move, delete', () async {
      final (time, _, a, b) = _twoDevices();
      final nb = a.s.notebooks.create(
        title: 'Board',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final box = _textBox('tb', nb.id, 'Hello world', extra: {'future': 'keep me'});
      a.s.elements.save([box]);
      a.s.elements.save([
        SurfaceElement(
          id: 'sticker',
          surfaceId: nb.id,
          type: 'sticker',
          rect: const Rect.fromLTWH(0, 0, 10, 10),
          z: 1,
          createdAt: 1,
          data: const {'emoji': 'x'},
        ),
      ]);
      await a.sync();
      final changes = await b.sync();
      expect(changes.strokeSurfaces, {nb.id});

      final got = {for (final e in b.content.loadAllElements(nb.id)) e.id: e};
      expect(got.keys, unorderedEquals(['tb', 'sticker']));
      expect(got['tb']!.type, 'text');
      expect(got['tb']!.rect, box.rect);
      expect(got['tb']!.rotation, box.rotation);
      expect(got['tb']!.z, box.z);
      expect(got['tb']!.createdAt, box.createdAt);
      expect(got['tb']!.data, box.data);
      // Rich text (spans, list paragraphs, font) survives the round trip.
      final synced = TextData.fromJson(got['tb']!.data);
      expect(synced, TextData.fromJson(box.data));
      expect(
        (synced.isRich, synced.font, synced.paras.single.checked),
        (true, TextFont.caveat, true),
      );
      expect(got['sticker']!.type, 'sticker', reason: 'unknown types are kept');
      expect(got['sticker']!.data, {'emoji': 'x'});
      final hello = b.search('hello').single;
      expect((hello.kind, hello.refId, hello.surfaceId), (SearchHitKind.text, 'tb', nb.id));

      // Edit the text on B (as the editor does: merge into the old data).
      time.tick();
      final edited = TextData.fromJson(got['tb']!.data).copyWith(text: 'Goodbye moon');
      b.s.elements.save([got['tb']!.copyWith(data: edited.toJson(got['tb']!.data))]);
      await _send(b, a);
      final onA = a.content.loadAllElements(nb.id).firstWhere((e) => e.id == 'tb');
      expect(onA.data['text'], 'Goodbye moon');
      expect(onA.data['future'], 'keep me');
      expect(a.search('hello'), isEmpty);
      expect(a.search('goodbye').single.refId, 'tb');

      // Move it far away on A: B re-indexes its chunks.
      time.tick();
      const moved = Rect.fromLTWH(5000, -3000, 200, 50);
      a.s.elements.save([onA.copyWith(rect: moved)]);
      await _send(a, b);
      final near = ChunkGrid.rangeFor(const Rect.fromLTRB(-100, -100, 400, 400));
      final far = ChunkGrid.rangeFor(moved.inflate(200));
      expect(
        b.s.elements.loadChunks(nb.id, b.s.elements.populatedChunks(nb.id, near)).map((e) => e.id),
        ['sticker'],
      );
      expect(
        b.s.elements.loadChunks(nb.id, b.s.elements.populatedChunks(nb.id, far)).single.rect,
        moved,
      );
      expect(b.search('goodbye').single.refId, 'tb', reason: 'moving keeps it indexed');

      // Delete on B.
      time.tick();
      b.s.elements.delete(['tb']);
      await _send(b, a);
      expect(a.content.loadAllElements(nb.id).map((e) => e.id), ['sticker']);
      expect(a.search('goodbye'), isEmpty);
      expect(a.searchDocs.keys, isNot(contains('text:tb')));
    });

    test('concurrent edits resolve by last-write-wins on both devices', () async {
      final (time, _, a, b) = _twoDevices();
      final nb = a.s.notebooks.create(
        title: 'Shared',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      a.s.elements.save([_textBox('tb', nb.id, 'original')]);
      await _send(a, b);

      String titleOn(_Device d) => d.s.notebooks.get(nb.id)!.title;
      Future<void> converge() async {
        await a.sync();
        await b.sync();
        await a.sync();
      }

      // Later write wins, whichever device syncs first.
      time.tick();
      b.s.notebooks.update(b.s.notebooks.get(nb.id)!.copyWith(title: 'Earlier on B'));
      time.tick();
      a.s.notebooks.update(a.s.notebooks.get(nb.id)!.copyWith(title: 'Later on A'));
      await b.sync();
      await a.sync();
      await b.sync();
      expect(titleOn(a), 'Later on A');
      expect(titleOn(b), 'Later on A');

      // Same timestamp: the greater device id ('b0' > 'a0') wins.
      time.tick();
      a.s.notebooks.update(a.s.notebooks.get(nb.id)!.copyWith(title: 'Tie A'));
      b.s.notebooks.update(b.s.notebooks.get(nb.id)!.copyWith(title: 'Tie B'));
      expect(
        a.s.notebooks.get(nb.id)!.updatedAt,
        b.s.notebooks.get(nb.id)!.updatedAt,
        reason: 'a real tie',
      );
      await converge();
      expect(titleOn(a), 'Tie B');
      expect(titleOn(b), 'Tie B');

      // B's clock runs an hour ahead; A's later edit must still win.
      time.tick();
      b.clock.skew = 3600 * 1000;
      b.s.notebooks.update(b.s.notebooks.get(nb.id)!.copyWith(title: 'From the future'));
      await _send(b, a);
      time.tick();
      a.s.notebooks.update(a.s.notebooks.get(nb.id)!.copyWith(title: 'Edited after'));
      await converge();
      expect(titleOn(a), 'Edited after');
      expect(titleOn(b), 'Edited after');
      expect(b.search('edited').map((h) => h.refId), [nb.id]);
      expect(b.search('future'), isEmpty);

      // Elements: concurrent move (A) and edit (B) — the whole later record wins.
      b.clock.skew = 0;
      time.tick(3600 * 1000);
      final onA = a.content.loadAllElements(nb.id).single;
      a.s.elements.save([onA.copyWith(rect: const Rect.fromLTWH(1, 1, 50, 50))]);
      time.tick();
      final onB = b.content.loadAllElements(nb.id).single;
      b.s.elements.save([
        onB.copyWith(data: {...onB.data, 'text': 'B wins'}),
      ]);
      await converge();
      for (final d in [a, b]) {
        final e = d.content.loadAllElements(nb.id).single;
        expect(e.data['text'], 'B wins');
        expect(e.rect, onB.rect);
      }
      expect(a.dirty, isEmpty);
      expect(b.dirty, isEmpty);
    });

    test('a tombstone pulled before an older live record prevents resurrection', () async {
      final (_, server, _, b) = _twoDevices();
      const nb = 'ghost-nb';
      final live = {
        'folders': {'name': 'Ghost folder', 'parentId': null, 'color': 1, 'createdAt': 1},
        'notebooks': _notebookData('Ghost notebook'),
        'pages': _pageData(nb, background: {'type': 'pdf', 'blob': _sha, 'page': 0}),
        'strokes': {
          'surfaceId': nb,
          'tool': 'ballpoint',
          'color': 0,
          'width': 2,
          'points': _points(const [StrokePoint(1, 1, 0.5), StrokePoint(9, 9, 0.5)]),
          'createdAt': 1,
        },
        'elements': _textData(nb, 'Ghost text'),
      };
      String idOf(String collection) => collection == 'notebooks' ? nb : 'ghost-$collection';
      server.injected.addAll([
        for (final c in live.keys) ...[
          _record(c, idOf(c), 200),
          _record(c, idOf(c), 100, data: live[c]),
        ],
      ]);
      b.db.execute("INSERT INTO pdf_text VALUES ('$_sha', 0, 'ghost pdf text')");

      for (var round = 0; round < 2; round++) {
        await b.sync();
        expect(b.s.folders.list(), isEmpty);
        expect(b.s.notebooks.get(nb), isNull);
        expect(b.s.notebooks.list(), isEmpty);
        expect(b.s.pages.get('ghost-pages'), isNull);
        expect(b.content.loadAll(nb), isEmpty);
        expect(b.content.loadAllElements(nb), isEmpty);
        for (final c in live.keys) {
          expect(b.deleted(c, idOf(c)), isTrue, reason: c);
        }
        expect(b.searchDocs, isEmpty);
        expect(b.search('ghost'), isEmpty);
        expect(b.dirty, isEmpty, reason: 'remote tombstones are not re-pushed');
      }

      // A newer live version does revive it (LWW, not a permanent delete).
      server.injected.add(_record('notebooks', nb, 300, data: live['notebooks']));
      await b.sync();
      expect(b.s.notebooks.get(nb)!.title, 'Ghost notebook');
      expect(b.search('ghost').map((h) => h.refId), [nb]);
    });

    test('unknown collections and malformed records are skipped, later ones applied', () async {
      final (time, server, a, b) = _twoDevices();
      a.s.notebooks.create(
        title: 'Before',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      await a.sync();
      final goodNotebook = _notebookData('Injected fine');
      server.injected.addAll([
        _record('future_things', 'f1', 10, data: {'anything': true}),
        _record('notebooks', 'bad-nb', 10, data: {'title': 5}),
        _record('folders', 'bad-folder', 10, data: {'name': null, 'createdAt': 1}),
        _record('pages', 'bad-page', 10, data: {..._pageData('n'), 'width': -1}),
        // Every field is required, and enum values must be known.
        _record('notebooks', 'partial-nb', 10, data: {...goodNotebook}..remove('editedAt')),
        _record('notebooks', 'odd-paper', 10, data: {...goodNotebook, 'paper': 'hexagon'}),
        _record('pages', 'partial-page', 10, data: {..._pageData('n')}..remove('bookmarked')),
        _record('pages', 'odd-color', 10, data: {..._pageData('n'), 'paperColor': 'sepia'}),
        _record('pages', 'odd-bg', 10, data: _pageData('n', background: {'type': 'video'})),
        _record(
          'strokes',
          'bad-stroke',
          10,
          data: {
            'surfaceId': 's',
            'tool': 'pen',
            'color': 0,
            'width': 0,
            'points': _points(const [StrokePoint(0, 0, 1)]),
            'createdAt': 0,
          },
        ),
        _record('elements', 'bad-element', 10, data: {..._textData('s', 'x'), 'type': ''}),
        _record('elements', 'no-z', 10, data: {..._textData('s', 'x')}..remove('z')),
        // Absurd coordinates would make chunk indexing (and outlining) hang.
        _record(
          'strokes',
          'far-stroke',
          10,
          data: {
            'surfaceId': 's',
            'tool': 'pen',
            'color': 0,
            'width': 2,
            'points': _points(const [StrokePoint(0, 0, 1), StrokePoint(3e38, 3e38, 1)]),
            'createdAt': 0,
          },
        ),
        _record('elements', 'huge-element', 10, data: _textData('s', 'x', w: 1e15, h: 1e15)),
        _record('notebooks', 'no-device', 10, data: goodNotebook)..remove('deviceId'),
        {..._record('notebooks', 'no-data', 10, data: goodNotebook), 'data': null},
        _record('notebooks', 'good-nb', 10, data: goodNotebook),
      ]);

      await b.sync();
      expect(
        b.s.notebooks.list().map((n) => n.title),
        unorderedEquals(['Before', 'Injected fine']),
      );
      for (final (table, id) in [
        ('notebooks', 'bad-nb'),
        ('notebooks', 'no-device'),
        ('notebooks', 'no-data'),
        ('folders', 'bad-folder'),
        ('pages', 'bad-page'),
        ('notebooks', 'partial-nb'),
        ('notebooks', 'odd-paper'),
        ('pages', 'partial-page'),
        ('pages', 'odd-color'),
        ('pages', 'odd-bg'),
        ('elements', 'no-z'),
        ('strokes', 'bad-stroke'),
        ('elements', 'bad-element'),
        ('strokes', 'far-stroke'),
        ('elements', 'huge-element'),
      ]) {
        expect(b.deleted(table, id), isNull, reason: '$table/$id must not be stored');
      }
      final seq = b.s.settings.syncLastSeq;
      expect(seq, greaterThan(0));

      // The feed keeps moving.
      time.tick();
      a.s.notebooks.create(
        title: 'After',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      await _send(a, b);
      expect(b.s.notebooks.list().map((n) => n.title), contains('After'));
      expect(b.s.settings.syncLastSeq, greaterThan(seq));
      expect(b.dirty, isEmpty);
    });

    test('search on the receiving device reflects synced titles and text boxes', () async {
      final (time, _, a, b) = _twoDevices();
      final folder = a.s.folders.create(name: 'Finance', color: 1);
      final nb = a.s.notebooks.create(
        title: 'Quarterly report',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
        folderId: folder.id,
      );
      final p1 = a.s.pages.pagesOf(nb.id).single;
      final p2 = a.s.pages.addPage(nb.id, after: p1);
      a.s.elements.save([_textBox('tb', p2.id, 'Budget forecast')]);
      await _send(a, b);

      expect(b.search('quart').map((h) => (h.kind, h.refId)), [
        (SearchHitKind.notebookTitle, nb.id),
      ]);
      final budget = b.search('budg').single;
      expect(budget.kind, SearchHitKind.text);
      expect(budget.notebookId, nb.id);
      expect(budget.surfaceId, p2.id);
      expect(budget.pageIndex, 1);
      expect(b.s.search.index.searchFolders(SearchQuery('fin')).map((h) => h.refId), [folder.id]);

      // Reorder, rename and trash on A; B's index follows.
      time.tick();
      a.s.pages.move(p2, 0);
      a.s.notebooks.update(a.s.notebooks.get(nb.id)!.copyWith(title: 'Annual report'));
      await _send(a, b);
      expect(b.search('budg').single.pageIndex, 0);
      expect(b.search('quart'), isEmpty);
      expect(b.search('annual').single.refId, nb.id);
      time.tick();
      a.s.notebooks.trash(nb.id);
      await _send(a, b);
      expect(b.search('annual'), isEmpty);
      expect(b.search('budg'), isEmpty);
      expect(b.searchDocs, containsPair('notebook:${nb.id}', 'Annual report'));
    });

    test('blobs: uploaded before the records, fetched lazily, indexed', () async {
      final (_, server, a, b) = _twoDevices();
      final bytes = Uint8List.fromList(utf8.encode('%PDF-1.7 fake pdf'));
      final sha = await a.s.blobs.putBytes(bytes, mime: 'application/pdf');
      final nb = a.s.notebooks.create(
        title: 'Imported',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final page = a.s.pages.insertPages(nb.id, [
        (
          size: const Size(612, 792),
          paper: Paper(PaperStyle.blank),
          color: PaperColor.white,
          background: PageBackground.pdf(blob: sha, pageIndex: 0),
        ),
      ]).single;
      await a.sync();
      expect(server.blobs[sha], bytes);
      expect(server.log.indexOf('PUT blob'), lessThan(server.log.indexOf('push')));
      expect(a.s.blobs.pendingUploads(), isEmpty);

      final logBefore = server.log.length;
      await b.sync();
      expect(server.log.skip(logBefore), isNot(contains('GET blob')), reason: 'lazy');
      expect(b.s.pages.get(page.id)!.background, PageBackground.pdf(blob: sha, pageIndex: 0));
      expect(await b.s.blobs.has(sha), isFalse);
      expect(await BlobSync(b.s.blobs).download(apiFor(server), sha), isTrue);
      expect(await b.s.blobs.read(sha), bytes);
      expect(b.s.blobs.pendingUploads(), isEmpty, reason: 'downloaded blobs are not re-uploaded');

      // Text extracted on B lands in its index for the synced page.
      b.db.execute('INSERT INTO pdf_text VALUES (?, 0, ?)', [sha, 'Invoice total']);
      SearchSchema.indexPdfPages(b.db, sha);
      final hit = b.search('invoice').single;
      expect((hit.kind, hit.refId, hit.notebookId), (SearchHitKind.pdf, page.id, nb.id));
    });
  });
}
