import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/raster_store.dart';
import 'package:len/data/storage_queries.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/storage/storage_overview.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:len/platform/storage_survey.dart';
import 'package:len/sync/sync_api.dart';

import 'support/fake_server.dart';

void main() {
  late Directory dir;
  late FakeServer server;
  late AppServices s;
  late MemoryRasterStore rasters;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_storage_test_');
    server = FakeServer();
    rasters = MemoryRasterStore();
    s = AppServices.create(
      AppDatabase.inMemory(),
      blobBackend: FileBlobBackend(dir.path),
      rasterStore: rasters,
      syncApiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
    );
  });
  tearDown(() {
    s.dispose();
    dir.deleteSync(recursive: true);
  });

  StorageQueries queries() => StorageQueries(s.database.db);

  /// Stores [size] bytes as [mime]; with [uploaded] the server has them.
  Future<String> blob(String tag, String mime, {int size = 1000, bool uploaded = true}) async {
    final bytes = Uint8List.fromList([...utf8.encode(tag), ...List.filled(size - tag.length, 0)]);
    final sha = await s.blobs.putBytes(bytes, mime: mime);
    if (uploaded) {
      s.blobs.markUploaded(sha);
      server.blobs[sha] = bytes;
    }
    return sha;
  }

  Notebook notebook(String title) => s.notebooks.create(
    title: title,
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

  NotebookPage page(Notebook n) => s.pages.insertPages(n.id, [
    (
      size: const Size(100, 140),
      paper: Paper(PaperStyle.blank),
      color: PaperColor.white,
      background: null,
    ),
  ]).single;

  void image(String surfaceId, String sha) => s.elements.save([
    SurfaceElement(
      id: s.clock.newId(),
      surfaceId: surfaceId,
      type: 'image',
      rect: const Rect.fromLTWH(0, 0, 10, 10),
      z: -1,
      createdAt: s.clock.nowMs(),
      data: ImageData(blob: sha, width: 10, height: 10).toJson(),
    ),
  ]);

  void recording(Notebook n, String sha) => s.recordings.save(
    notebookId: n.id,
    parts: [RecordingPart(sha, 1000)],
    mime: 'audio/mp4',
    title: 'R',
    segments: [RecordingSegment(s.clock.nowMs(), 1000)],
  );

  /// Marks PDF [sha]'s text as read by search.
  void textRead(String sha) => s.database.execute(
    'INSERT OR REPLACE INTO pdf_text_blobs (blob, pages, ok) VALUES (?, 1, 1)',
    [sha],
  );

  void configureSync() => s.sync.configure(url: 'http://sync.test', token: FakeServer.token);

  group('queries', () {
    test('sizes files by kind and lists the largest notebooks', () async {
      final pdf = await blob('pdf', 'application/pdf', size: 5000);
      final img = await blob('img', 'image/png', size: 2000);
      final audio = await blob('audio', 'audio/mp4', size: 9000);
      await blob('orphan', 'application/octet-stream', size: 100);
      final lecture = notebook('Lecture');
      final p = pdfPage(lecture, pdf);
      image(p.id, img);
      image(p.id, img); // Counted once.
      final talk = notebook('Talk');
      recording(talk, audio);
      notebook('Empty');

      expect(queries().fileBytes(), {
        FileKind.pdf: 5000,
        FileKind.image: 2000,
        FileKind.audio: 9000,
        FileKind.other: 100,
      });
      final largest = queries().largestNotebooks();
      expect([for (final n in largest) n.title], ['Talk', 'Lecture']);
      expect(largest.first.recordingBytes, 9000);
      expect(largest.first.recordings, 1);
      expect(largest.last.bytes, greaterThan(7000)); // Files + the elements' data.
      expect(largest.last.recordingBytes, 0);
      expect(queries().databaseBytes(), greaterThan(0));
    });

    test('free-up offers only uploaded files no open notebook needs', () async {
      final read = await blob('read pdf', 'application/pdf');
      final unread = await blob('unread pdf', 'application/pdf');
      final notUploaded = await blob('new image', 'image/png', uploaded: false);
      final tooLarge = await blob('huge', 'audio/mp4');
      s.blobs.markTooLarge(tooLarge, 10);
      final shown = await blob('shown image', 'image/png');
      final shared = await blob('shared image', 'image/png');
      final template = await blob('template', 'image/png');
      final unreferenced = await blob('unreferenced', 'image/png');
      textRead(read);

      final closed = notebook('Closed'), open = notebook('Open');
      pdfPage(closed, read);
      pdfPage(closed, unread);
      final p = page(closed);
      for (final sha in [notUploaded, shown, shared]) {
        image(p.id, sha);
      }
      recording(closed, tooLarge);
      image(page(open).id, shared);
      s.templates.create(name: 'T', blob: template, size: const Size(10, 10));
      expect(unreferenced, isNotEmpty);

      final ids = {
        for (final b in queries().freeable(keep: {open.id})) b.sha,
      };
      expect(ids, {read, shown});
      expect(queries().kept(keep: {open.id}), containsAll([shared, template, unread]));
    });
  });

  group('free up', () {
    test('removes copies the server holds; they download again when shown', () async {
      configureSync();
      final pdf = await blob('pdf', 'application/pdf', size: 4000);
      textRead(pdf);
      final img = await blob('img', 'image/png', size: 3000);
      final notUploaded = await blob('mine', 'image/png', uploaded: false);
      final lost = await blob('lost', 'image/png'); // Uploaded, but gone from the server.
      server.blobs.remove(lost);
      final n = notebook('N');
      pdfPage(n, pdf);
      final p = page(n);
      for (final sha in [img, notUploaded, lost]) {
        image(p.id, sha);
      }
      final overview = s.storage;
      await overview.refresh();
      expect(overview.survey!.freeable, 4000 + 3000 + 1000);
      expect(overview.canFreeUp, isTrue);

      final outcome = await overview.freeUp();
      expect(outcome, isA<FreedUp>().having((o) => o.bytes, 'bytes', 7000));
      expect(await s.blobs.has(pdf), isFalse);
      expect(await s.blobs.has(img), isFalse);
      expect(await s.blobs.has(notUploaded), isTrue);
      expect(await s.blobs.has(lost), isTrue);
      expect(File(s.blobs.localPath(pdf)!).existsSync(), isFalse);
      await overview.refresh();
      expect(overview.survey!.files[FileKind.pdf], 0);

      // Shown again: fetched from the server, and still counts as uploaded.
      expect(await s.sync.fetchBlob(pdf), isTrue);
      expect((await s.blobs.read(pdf))!.length, 4000);
      expect(s.blobs.pendingUploads(), isNot(contains(pdf)));
    });

    test('keeps the files of notebooks open in the editor', () async {
      configureSync();
      final img = await blob('img', 'image/png');
      final n = notebook('Open');
      image(page(n).id, img);
      s.openNotebooks.open(n);
      await s.storage.refresh();
      expect(s.storage.survey!.freeable, 0);
      expect(s.storage.canFreeUp, isFalse);
      expect(await s.storage.freeUp(), isA<FreedUp>().having((o) => o.count, 'count', 0));
      expect(await s.blobs.has(img), isTrue);
    });

    test('a notebook opened meanwhile keeps its files', () async {
      configureSync();
      final img = await blob('img', 'image/png');
      final n = notebook('N');
      image(page(n).id, img);
      final queries = StorageQueries(s.database.db);
      expect(queries.freeable(), hasLength(1));
      final kept = queries.kept(keep: {n.id});
      final removed = await s.blobs.removeLocalCopies([
        img,
      ], stillRemovable: (sha) => !kept.contains(sha));
      expect(removed.count, 0);
      expect(await s.blobs.has(img), isTrue);
    });

    test('nothing goes when the server cannot be reached', () async {
      final img = await blob('img', 'image/png');
      image(page(notebook('N')).id, img);
      s.sync.configure(url: 'http://sync.test', token: 'wrong-token-0000000');
      expect(await s.storage.freeUp(), isA<ServerUnreachable>());
      expect(await s.blobs.has(img), isTrue);
    });

    test('without sync nothing is offered', () async {
      final img = await blob('img', 'image/png');
      image(page(notebook('N')).id, img);
      await s.storage.refresh();
      expect(s.storage.survey!.freeable, 1000);
      expect(s.storage.canFreeUp, isFalse);
    });
  });

  test('clears cached previews', () async {
    await rasters.write('a', Uint8List(3000));
    await s.storage.refresh();
    expect(s.storage.previews, 3000);
    await s.storage.clearPreviews();
    expect(s.storage.previews, 0);
    expect(rasters.length, 0);
  });

  test('natively measures on a worker over the database file', () async {
    final path = '${dir.path}/len.db';
    final database = AppDatabase.open(path);
    addTearDown(database.close);
    final survey = await surveyStorage(database);
    expect(survey.database, greaterThanOrEqualTo(File(path).lengthSync()));
    expect(survey.largest, isEmpty);
  });
}
