import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/syncable.dart';
import 'package:len/data/versions/canonical_json.dart';
import 'package:len/data/versions/version_packs.dart';
import 'package:len/data/versions/version_table.dart';
import 'package:len/data/versions/versions.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';

/// A clock tests move by hand; ids `v0`, `v1`, …
class _Clock extends Clock {
  int now = DateTime.utc(2026, 10, 1, 12).millisecondsSinceEpoch;
  int _ids = 0;

  void advance(Duration d) => now += d.inMilliseconds;

  @override
  int nowMs() => now;

  @override
  String newId() => 'v${_ids++}';
}

Stroke _ink(String id, String surface, {double x = 10, int createdAt = 0}) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF102030,
  width: 3,
  points: [StrokePoint(x, 10, 0.5), StrokePoint(x + 20, 30, 0.5)],
  createdAt: createdAt,
);

String _sha(int n) => sha256.convert([n]).toString();

void main() {
  late _Clock clock;
  late AppServices s;
  Versions versions() => s.versions;
  Future<VersionBody> body(NotebookVersion v) => s.versions.content.body(v);

  setUp(() {
    clock = _Clock();
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
  });
  tearDown(() => s.dispose());

  Notebook paged({int pages = 2}) {
    final n = s.notebooks.create(
      title: 'Lab',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 1,
    );
    for (var i = 1; i < pages; i++) {
      s.pages.addPage(n.id);
    }
    return n;
  }

  List<String> pageIds(Notebook n) => [for (final p in s.pages.pagesOf(n.id)) p.id];
  Set<String> strokesOn(String surface) => {
    for (final row in s.database.db.select(
      'SELECT id FROM strokes WHERE surface_id = ? AND deleted = 0',
      [surface],
    ))
      row['id'] as String,
  };

  group('canonical bytes', () {
    test('numbers, keys and strings are written one way', () {
      expect(
        CanonicalJson.encode({'b': 1.0, 'a': 2.5, 'c': -0.0, 'd': 1e21, 'e': 1e-7}),
        ('{"a":2.5,"b":1,"c":0,"d":1e+21,"e":1e-7}'),
      );
      expect(CanonicalJson.encode('q"\\\n\u0001\ud800😀'), r'"q\"\\\n\u0001\ud800😀"');
      expect(() => CanonicalJson.encode(double.nan), throwsArgumentError);
    });

    test('a pack is the same bytes whether numbers came as ints or doubles', () {
      // The web hands integral doubles over as ints; native code keeps 10.0.
      final native = VersionPacks.encode([
        (
          'e',
          <String, Object?>{
            'x': 10.0,
            'w': 200.0,
            'rotation': 0.0,
            'data': {'z': 1.0},
          },
        ),
      ]);
      final web = VersionPacks.encode([
        (
          'e',
          <String, Object?>{
            'data': {'z': 1},
            'rotation': 0,
            'w': 200,
            'x': 10,
          },
        ),
      ]);
      expect(native, web);
      expect(native.sublist(0, 3), [0x4C, 0x50, 2], reason: 'LP, format 2');
    });

    test('pack bytes are pinned (the web writes these too)', () {
      // Checked against dart2js and dart2wasm builds under Node: the same SHA-256.
      final pack = VersionPacks.encode([
        for (var i = 0; i < 40; i++)
          ('s$i', <String, Object?>{'x': i * 1.5, 'n': i, 'p': 'é$i', 'w': 3.0}),
      ]);
      expect(pack.length, lessThan(CanonicalJson.bytes(['x']).length * 400));
      expect(
        sha256.convert(pack).toString(),
        'ffd3aa6ebda48515e396afea256f554d711f950dfe9fde8b915fcad794074ee8',
        reason: 'changing the encoding (or the compressor) splits dedupe across app versions',
      );
      final (id, data) = VersionPacks.decode(pack)!.first;
      expect(id, 's0');
      expect(data, {'n': 0, 'p': 'é0', 'w': 3, 'x': 0});
    });

    test('table blobs are reference blobs: LR, 1, then deflated rows', () {
      final rows = [
        {
          't': 'page',
          'id': 'p',
          'ink': [_sha(1)],
        },
      ];
      final bytes = VersionTable.encode(rows);
      expect(bytes.sublist(0, 3), [0x4C, 0x52, 1]);
      expect(VersionTable.decode(bytes), rows);
      expect(VersionTable.decode(VersionPacks.encode(const [])), isNull);
    });
  });

  group('recordings, outline and recognised handwriting', () {
    String recording(Notebook n, int part) => s.recordings
        .save(
          notebookId: n.id,
          parts: [RecordingPart(_sha(part), 1000)],
          mime: 'audio/aac',
          title: 'Lecture $part',
          segments: const [RecordingSegment(1, 1000)],
        )
        .id;

    test('a restore brings them back as they were', () async {
      final n = paged();
      final [first, second] = pageIds(n);
      final text = s.versions.repositories.recognisedText;
      s.strokes.save([_ink('a0', first)]);
      text.write(first, 'en', {'k1': 'hello'});
      final kept = recording(n, 1);
      s.recordings.trim(kept, 100, 900);
      final entry = s.outline.add(notebookId: n.id, pageId: second, title: 'Results');
      final v1 = (await versions().record(n.id))!;
      final b1 = await body(v1);
      expect(b1.recordings!.single.id, kept);
      expect(b1.outline!.single.id, entry.id);
      expect(b1.pages.first.content.text, {
        'language': 'en',
        'lines': [
          ['k1', 'hello'],
        ],
      });

      // Afterwards: the recording trimmed back and another made, the entry
      // renamed and one added, the text read again.
      s.recordings.trim(kept, 0, 1000);
      final later = recording(n, 2);
      s.outline.update(entry.copyWith(title: 'Renamed'));
      s.outline.add(notebookId: n.id, pageId: first, title: 'Intro');
      text.write(first, 'en', {'k2': 'other'});
      text.write(second, 'en', {'k3': 'new'});
      clock.advance(const Duration(minutes: 3));

      final done = await versions().restore(v1);
      final trimmed = s.recordings.get(kept)!;
      expect((trimmed.trimStartMs, trimmed.trimEndMs), (100, 900));
      expect(s.recordings.get(later), isNull);
      expect(s.outline.entriesOf(n.id).map((e) => (e.id, e.title)), [(entry.id, 'Results')]);
      expect(text.read(first)!.lines, {'k1': 'hello'});
      expect(text.read(second), isNull);

      // And undone: the version saved before holds them all.
      clock.advance(const Duration(minutes: 1));
      await versions().restore(done.before!);
      expect(s.recordings.get(later), isNotNull);
      expect(s.recordings.get(kept)!.trimEndMs, 1000);
      expect(s.outline.entriesOf(n.id), hasLength(2));
      expect(text.read(second)!.lines, {'k3': 'new'});
    });

    test('one page brings back its text and the outline entries leading to it', () async {
      final n = paged();
      final [first, second] = pageIds(n);
      final text = s.versions.repositories.recognisedText;
      text.write(second, 'en', {'k': 'kept'});
      final entry = s.outline.add(notebookId: n.id, pageId: second, title: 'Two');
      s.outline.add(notebookId: n.id, pageId: first, title: 'One');
      final v1 = (await versions().record(n.id))!;
      s.notebooks.deletePage(second);
      s.outline.delete(entry.id);
      final other = s.outline.entriesOf(n.id).single;
      s.outline.update(other.copyWith(title: 'One, renamed'));
      clock.advance(const Duration(minutes: 1));

      await versions().restorePage(v1, second);
      expect(text.read(second)!.lines, {'k': 'kept'});
      expect({for (final e in s.outline.entriesOf(n.id)) e.title}, {'Two', 'One, renamed'});
    });

    test('a copy has its own recordings and outline on its own pages', () async {
      final n = paged();
      final [_, second] = pageIds(n);
      final rec = recording(n, 1);
      final parent = s.outline.add(notebookId: n.id, pageId: second, title: 'Part');
      s.outline.add(notebookId: n.id, pageId: second, title: 'Sub', parentId: parent.id);
      final v1 = (await versions().record(n.id))!;
      final copy = (await versions().copy(v1, title: 'Copy'))!;
      final copied = s.recordings.listOf(copy.id).single;
      expect(copied.id, isNot(rec));
      expect(copied.parts.single.blob, _sha(1), reason: 'the same audio');
      final pages = [for (final p in s.pages.pagesOf(copy.id)) p.id];
      final entries = {for (final e in s.outline.entriesOf(copy.id)) e.title: e};
      expect(entries['Part']!.pageId, pages[1]);
      expect(entries['Sub']!.parentId, entries['Part']!.id);
      expect(s.recordings.listOf(n.id).single.id, rec, reason: 'the original keeps its own');
    });
  });

  group('format 1', () {
    test('a record of format 1 with JSON packs still reads and restores', () async {
      final n = paged(pages: 1);
      final page = pageIds(n).single;
      s.strokes.save([_ink('old', page)]);
      final stroke = s.strokes.rowToRecord(
        s.database.db.select('SELECT * FROM strokes WHERE id = ?', ['old']).single,
      );
      final pack = await s.blobs.putBytes(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'v': 1,
              'items': [
                [
                  'old',
                  {...stroke.data!}..remove('surfaceId'),
                ],
              ],
            }),
          ),
        ),
        mime: VersionPacks.mime,
      );
      final built = (await versions().snapshots.build(n.id))!;
      final fields = (await body(built)).pages.single.fields;
      s.versions.store.writeRemote(
        SyncRecord(
          collection: 'versions',
          id: 'old-version',
          updatedAt: 5,
          deviceId: 'other',
          deleted: false,
          data: {
            'notebookId': n.id,
            'createdAt': clock.now - 1000,
            'kind': 'auto',
            'name': null,
            'deviceId': 'other',
            'deviceName': 'Linux',
            'notebook': built.notebook,
            'pages': [
              {
                'id': page,
                ...fields,
                'ink': [pack],
                'items': <String>[],
              },
            ],
            'canvas': null,
            'blobs': <String>[],
            'summary': const VersionSummary(pages: 1, strokes: 1).toJson(),
            'size': 10,
          },
        ),
      );
      final old = s.versions.store.get('old-version')!;
      expect(old.table, isEmpty);
      expect((await body(old)).recordings, isNull, reason: 'not kept then');
      s.strokes.delete(['old']);
      s.strokes.save([_ink('new', page)]);
      final rec = s.recordings.save(
        notebookId: n.id,
        parts: [RecordingPart(_sha(9), 10)],
        mime: 'audio/aac',
        title: 'Kept',
        segments: const [RecordingSegment(1, 10)],
      );
      await versions().restore(old);
      expect(strokesOn(page), {'old'});
      expect(s.recordings.get(rec.id), isNotNull, reason: 'format 1 leaves recordings be');
      // Renamed, it stays format 1.
      versions().rename(old.id, 'Named');
      expect(s.versions.store.get(old.id)!.inline, isNotNull);
    });
  });

  group('long notebooks', () {
    test('a version of 1000 pages is a small record; an edit shares the table', () async {
      final n = paged(pages: 1000);
      final ids = pageIds(n);
      s.strokes.save([_ink('a', ids[10])]);
      final v1 = (await versions().record(n.id))!;
      final record = jsonEncode(v1.toData());
      expect(record.length, lessThan(4096), reason: 'was ~100 KB with the pages inline');
      expect(v1.table.length, greaterThan(10));
      expect((await body(v1)).pages, hasLength(1000));

      s.strokes.save([_ink('b', ids[500], createdAt: 5)]);
      clock.advance(const Duration(minutes: 5));
      final v2 = (await versions().record(n.id))!;
      final fresh = v2.table.toSet().difference(v1.table.toSet());
      expect(fresh.length, lessThanOrEqualTo(2), reason: 'only the edited page’s run');
      expect(v2.summary.pagesEdited, 1);
      expect(v2.summary.focus, ids[500]);
    });

    test('uploads and garbage collection follow the table into its packs', () async {
      final n = paged(pages: 1);
      final page = pageIds(n).single;
      s.strokes.save([_ink('a', page)]);
      final v = (await versions().record(n.id))!;
      final packs = (await body(v)).packs;
      final references = s.sync.engine.blobReferences;
      expect(references.all(), containsAll([...v.table, ...packs]));
      expect(packs.every((sha) => references.keeps(sha, clock.now)), isTrue);
      final record = s.versions.store.dirtyRecords(1).single;
      expect(references.ofRecord(record), containsAll(packs), reason: 'its push waits for them');

      s.strokes.delete(['a']);
      for (var i = 0; i < 2; i++) {
        clock.advance(const Duration(days: 40));
        await s.blobGc.run();
      }
      for (final sha in [...v.table, ...packs]) {
        expect(await s.blobs.has(sha), isTrue, reason: sha);
      }
      versions().delete([v.id]);
      for (var i = 0; i < 2; i++) {
        clock.advance(const Duration(days: 8));
        await s.blobGc.run();
      }
      for (final sha in [...v.table, ...packs]) {
        expect(await s.blobs.has(sha), isFalse, reason: sha);
      }
      expect(s.database.db.select('SELECT * FROM blob_links'), isEmpty, reason: 'pruned');
    });

    test('a table blob fetched from elsewhere notes what it names', () async {
      final n = paged(pages: 1);
      s.strokes.save([_ink('a', pageIds(n).single)]);
      final v = (await versions().record(n.id))!;
      final packs = (await body(v)).packs;
      s.database.db.execute('DELETE FROM blob_links');
      expect(s.sync.engine.blobReferences.all(), isNot(containsAll(packs)));
      // A fresh reader (another start of the app) reads the table again.
      final reader = VersionContent(blobs: s.blobs, links: s.sync.engine.blobReferences.links);
      await reader.body(v);
      expect(s.sync.engine.blobReferences.all(), containsAll(packs));
    });
  });

  test('versions keep elements with a rect as numbers that read back', () async {
    final n = paged(pages: 1);
    final page = pageIds(n).single;
    s.elements.save([
      SurfaceElement(
        id: 't',
        surfaceId: page,
        type: 'text',
        rect: const Rect.fromLTWH(10, 20, 200, 40),
        z: 1,
        createdAt: 3,
        data: const TextData(text: 'hi').toJson(),
      ),
    ]);
    final v = (await versions().record(n.id))!;
    final c = await versions().content.load((await body(v)).pages.single.content, page);
    expect(c.elements.single.rect, const Rect.fromLTWH(10, 20, 200, 40));
  });
}
