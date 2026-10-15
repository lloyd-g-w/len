import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_references.dart';
import 'package:len/data/tombstone_payloads.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/platform/blob_backend_native.dart';

import 'support/fake_server.dart';

/// A clock tests can move forward.
class _Clock extends Clock {
  int now = DateTime(2026, 10, 1).millisecondsSinceEpoch;

  void advance(Duration d) => now += d.inMilliseconds;

  @override
  int nowMs() => now;
}

void main() {
  late Directory dir;
  late _Clock clock;
  late AppServices s;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_blob_gc_test_');
    clock = _Clock();
    s = AppServices.create(
      AppDatabase.inMemory(),
      clock: clock,
      blobBackend: FileBlobBackend(dir.path),
    );
  });
  tearDown(() {
    s.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<String> blob(String content) =>
      s.blobs.putBytes(Uint8List.fromList(utf8.encode(content)), mime: 'application/octet-stream');

  Notebook notebook() => s.notebooks.create(
    title: 'N',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
  );

  NotebookPage pdfPage(Notebook n, String sha) => s.pages.insertPages(n.id, [
    (
      size: const Size(100, 140),
      paper: Paper(PaperStyle.blank),
      color: PaperColor.white,
      background: PageBackground.pdf(blob: sha, pageIndex: 0),
    ),
  ]).single;

  SurfaceElement image(String surfaceId, String sha) {
    final e = SurfaceElement(
      id: clock.newId(),
      surfaceId: surfaceId,
      type: 'image',
      rect: const Rect.fromLTWH(0, 0, 10, 10),
      z: -1,
      createdAt: clock.nowMs(),
      data: ImageData(blob: sha, width: 10, height: 10).toJson(),
    );
    s.elements.save([e]);
    return e;
  }

  Recording recording(Notebook n, String sha) => s.recordings.save(
    notebookId: n.id,
    parts: [RecordingPart(sha, 1000)],
    mime: 'audio/mp4',
    title: 'R',
    segments: [RecordingSegment(clock.nowMs(), 1000)],
  );

  Set<String> referenced() => BlobReferences(s.database).all();

  group('reference graph', () {
    test('page backgrounds, image elements and recordings reference blobs', () async {
      final pdf = await blob('pdf'), img = await blob('img'), audio = await blob('audio');
      await blob('orphan');
      final n = notebook();
      final page = pdfPage(n, pdf);
      image(page.id, img);
      recording(n, audio);
      expect(referenced(), {pdf, img, audio});
    });

    test('the trash still references; deleting forever releases', () async {
      final pdf = await blob('pdf'), img = await blob('img'), audio = await blob('audio');
      final n = notebook();
      final page = pdfPage(n, pdf);
      image(page.id, img);
      recording(n, audio);

      s.notebooks.trash(n.id);
      expect(referenced(), {pdf, img, audio});

      s.notebooks.emptyTrash();
      expect(referenced(), isEmpty);
    });

    test('deleted pages, elements and recordings release their blobs', () async {
      final pdf = await blob('pdf'), img = await blob('img'), audio = await blob('audio');
      final n = notebook();
      final page = pdfPage(n, pdf);
      final other = s.pages.pagesOf(n.id).first;
      final e = image(other.id, img);
      final r = recording(n, audio);
      s.pages.delete(page.id);
      s.elements.delete([e.id]);
      s.recordings.delete(r.id);
      expect(referenced(), isEmpty);
    });

    test('image templates of pages and My templates reference blobs', () async {
      final paper = await blob('paper'), mine = await blob('mine');
      final n = notebook();
      final page = s.pages.pagesOf(n.id).single;
      s.pages.setPaper([page.id], paper: Paper.image(paper));
      final template = s.templates.create(name: 'T', blob: mine, size: const Size(100, 100));
      expect(referenced(), {paper, mine});

      s.templates.delete(template.id);
      s.pages.setPaper([page.id], paper: Paper.blank);
      expect(referenced(), isEmpty);
    });

    test('blob ids anywhere in JSON (unknown element types included)', () {
      final sha = 'ab' * 32;
      expect(
        BlobReferences.inValue({
          'a': [
            1,
            {'b': sha},
          ],
          'c': 'x',
          'd': sha.toUpperCase(),
        }),
        {sha},
      );
      expect(BlobReferences.inJson('{"nested":{"blob":"$sha"}}'), {sha});
      expect(BlobReferences.inJson('not json'), isEmpty);
      expect(BlobReferences.inJson('["$sha", "${sha}0", "x$sha"]'), {sha});
      expect(BlobReferences.inJson('{"text":"${sha}0"}'), isEmpty);
    });
  });

  group('local garbage collection', () {
    test('deletes a blob unreferenced for 7 days, keeps referenced ones', () async {
      final keep = await blob('keep'), drop = await blob('drop');
      recording(notebook(), keep);

      expect(await s.blobGc.run(), isEmpty); // Day 0: marked.
      clock.advance(const Duration(days: 6));
      expect(await s.blobGc.run(), isEmpty);
      clock.advance(const Duration(days: 1));
      expect(await s.blobGc.run(), [drop]);

      expect(await s.blobs.has(drop), isFalse);
      expect(File(s.blobs.localPath(drop)!).existsSync(), isFalse);
      expect(s.blobs.sizeOf(drop), isNull);
      expect(await s.blobs.has(keep), isTrue);
    });

    test('a blob referenced again (or stored again) restarts its grace period', () async {
      final sha = await blob('comes back');
      await s.blobGc.run();
      clock.advance(const Duration(days: 5));
      final r = recording(notebook(), sha);
      await s.blobGc.run(); // Referenced: unmarked.
      s.recordings.delete(r.id);
      clock.advance(const Duration(days: 8));
      // A deletion may still be undone by sync (TombstonePayloads).
      expect(await s.blobGc.run(), isEmpty);
      clock.advance(TombstonePayloads.retention);
      await s.blobGc.run(); // Marked anew.
      clock.advance(const Duration(days: 5));
      expect(await s.blobGc.run(), isEmpty);

      await blob('comes back'); // Re-imported, e.g. pasted again.
      clock.advance(const Duration(days: 3));
      expect(await s.blobGc.run(), isEmpty);
      clock.advance(const Duration(days: 7));
      expect(await s.blobGc.run(), [sha]);
    });

    test('a blob stored again while collection runs survives', () async {
      final sha = await blob('again');
      await s.blobGc.run();
      clock.advance(const Duration(days: 8));
      // Both orders: collection first (deletes, then the put stores it
      // anew), or the put first (restarting the grace period).
      final results = await Future.wait([s.blobGc.run(), blob('again')]);
      expect(results[1], sha);
      expect(await s.blobs.has(sha), isTrue);
      expect(s.blobs.pendingUploads(), [sha]);
      clock.advance(const Duration(days: 8));
      await blob('again');
      expect(await s.blobGc.run(), isEmpty);
      expect(await s.blobs.has(sha), isTrue);
    });

    test('blobs in the trash are kept', () async {
      final sha = await blob('pdf');
      final n = notebook();
      pdfPage(n, sha);
      s.notebooks.trash(n.id);
      await s.blobGc.run();
      clock.advance(const Duration(days: 30));
      expect(await s.blobGc.run(), isEmpty);
      expect(await s.blobs.has(sha), isTrue);
    });

    test('a cancelled import keeps a blob a deleted page may still need', () async {
      final sha = await blob('pdf');
      final page = pdfPage(notebook(), sha);
      s.notebooks.deletePage(page.id); // Undo or a deletion conflict may bring it back.
      // The same PDF imported again, then cancelled.
      expect(await blob('pdf'), sha);
      await PdfImporter(s).discard(sha);
      expect(await s.blobs.has(sha), isTrue);
      expect(await s.blobGc.run(), isEmpty);
    });

    test('deleted forever: ink and blobs are kept while sync may undo it', () async {
      final pdf = await blob('pdf'), img = await blob('img'), audio = await blob('audio');
      final n = notebook();
      final page = pdfPage(n, pdf);
      image(page.id, img);
      recording(n, audio);
      s.strokes.save([bigStroke('ink', page.id, 3)]);
      s.notebooks.delete(n.id);
      String points() =>
          '${s.database.db.select("SELECT length(points) AS n FROM strokes").single['n']}';
      expect(points(), isNot('0'));

      await s.blobGc.run();
      clock.advance(TombstonePayloads.retention - const Duration(days: 1));
      expect(await s.blobGc.run(), isEmpty);
      expect(points(), isNot('0'));
      clock.advance(const Duration(days: 2));
      expect(await s.blobGc.run(), isEmpty); // Marked; the ink is gone.
      expect(points(), '0');
      expect(s.database.db.select("SELECT * FROM elements WHERE data <> '{}'"), isEmpty);
      clock.advance(const Duration(days: 7));
      expect((await s.blobGc.run()).toSet(), {pdf, img, audio});
    });

    test('old tombstones lose their payload in batches, all of them', () async {
      final page = pdfPage(notebook(), await blob('pdf'));
      final ids = [for (var i = 0; i < TombstonePayloads.batch * 2 + 1; i++) 'ink $i'];
      s.strokes.save([for (final id in ids) bigStroke(id, page.id, 2)]);
      s.strokes.delete(ids);
      clock.advance(TombstonePayloads.retention + const Duration(days: 1));
      await s.blobGc.run();
      expect(s.database.db.select('SELECT id FROM strokes WHERE length(points) > 0'), isEmpty);
    });

    test('a blob a pull references while collection deletes others survives', () async {
      s.dispose();
      final backend = _HookedBackend(dir.path);
      s = AppServices.create(AppDatabase.inMemory(), clock: clock, blobBackend: backend);
      final a = await blob('a'), b = await blob('b');
      final page = s.pages.pagesOf(notebook().id).single;
      await s.blobGc.run();
      clock.advance(const Duration(days: 8));
      // Deleting the first, a pull commits a record referencing the other.
      String? pulled;
      backend.onDelete = (sha) {
        backend.onDelete = null;
        image(page.id, pulled = sha == a ? b : a);
      };
      final deleted = await s.blobGc.run();
      expect(deleted, hasLength(1));
      expect(deleted, isNot(contains(pulled)));
      expect(await s.blobs.has(pulled!), isTrue);
      // Its grace period starts afresh once it is unreferenced again.
      expect(s.database.db.select('SELECT unreferenced_since FROM blobs').single.values, [null]);
    });

    test('the one-blob check agrees with the reference graph', () async {
      final pdf = await blob('pdf'), img = await blob('img'), audio = await blob('audio');
      final paper = await blob('paper'), mine = await blob('mine'), orphan = await blob('orphan');
      final n = notebook();
      final page = pdfPage(n, pdf);
      image(page.id, img);
      recording(n, audio);
      s.pages.setPaper([s.pages.pagesOf(n.id).first.id], paper: Paper.image(paper));
      s.templates.create(name: 'T', blob: mine, size: const Size(100, 100));
      final refs = BlobReferences(s.database);
      final now = clock.nowMs();
      for (final sha in [pdf, img, audio, paper, mine, orphan]) {
        expect(refs.keeps(sha, now), refs.kept(now).contains(sha), reason: sha);
      }
      s.notebooks.delete(n.id);
      clock.advance(TombstonePayloads.retention + const Duration(days: 1));
      final later = clock.nowMs();
      for (final sha in [pdf, img, audio, paper]) {
        expect(refs.keeps(sha, later), isFalse, reason: sha);
      }
      expect(refs.keeps(mine, later), isTrue);
    });

    test('runIfDue runs at most once a day', () async {
      final sha = await blob('orphan');
      await s.blobGc.runIfDue(); // Marks.
      clock.advance(const Duration(days: 8));
      expect(await s.blobGc.runIfDue(), [sha]);
      final again = await blob('orphan 2');
      expect(s.settings.blobGcLastRun, clock.now);
      clock.advance(const Duration(hours: 12));
      expect(await s.blobGc.runIfDue(), isEmpty); // Throttled: not even marked.
      clock.advance(const Duration(days: 8));
      expect(await s.blobGc.runIfDue(), isEmpty); // Marked now...
      clock.advance(const Duration(days: 8));
      expect(await s.blobGc.runIfDue(), [again]); // ...deleted a week later.
    });
  });
}

/// Files, telling [onDelete] before each deletion.
class _HookedBackend extends FileBlobBackend {
  _HookedBackend(super.directory);

  void Function(String sha)? onDelete;

  @override
  Future<void> delete(String sha) async {
    onDelete?.call(sha);
    await super.delete(sha);
  }
}
