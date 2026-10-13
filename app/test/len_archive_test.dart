import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/cancellation.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';

AppServices _services() =>
    AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());

Stroke _stroke(String surface, int i) => Stroke(
  id: 'stroke-$surface-$i',
  surfaceId: surface,
  tool: i.isEven ? InkTool.ballpoint : InkTool.highlighter,
  color: 0xFF000000 + i,
  width: 2 + i % 3,
  points: [StrokePoint(i * 3.0, 4, 0.5), StrokePoint(i * 3.0 + 20, 9, 0.75)],
  createdAt: 1000 + i,
);

SurfaceElement _element(String id, String surface, String type, Map<String, Object?> data) =>
    SurfaceElement(
      id: id,
      surfaceId: surface,
      type: type,
      rect: const Rect.fromLTWH(10, 20, 300, 40),
      rotation: 0.25,
      z: type == 'text' ? 1 : -1,
      createdAt: 5,
      data: data,
    );

/// A notebook holding every kind of content: ink on two pages, a text
/// box, an image, a link to its second page, a PDF page, an image
/// template, a bookmark, an outline and a recording with a waveform.
Future<Notebook> _richNotebook(AppServices s, {String title = 'Lecture'}) async {
  Future<String> blob(String text, String mime) =>
      s.blobs.putBytes(Uint8List.fromList(utf8.encode(text)), mime: mime);
  final pdf = await blob('%PDF pretend', 'application/pdf');
  final image = await blob('png pretend', 'image/png');
  final paper = await blob('paper pretend', 'image/png');
  final audio = await blob('audio pretend', 'audio/mp4');
  final waveform = await blob('LW wave', 'application/x-len-waveform');
  final n = s.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: 0xFF3B5BDB,
  );
  final first = s.pages.pagesOf(n.id).single;
  final pdfPage = s.pages.insertPages(n.id, [
    (
      size: const Size(612, 792),
      paper: Paper(PaperStyle.blank),
      color: PaperColor.cream,
      background: PageBackground.pdf(blob: pdf, pageIndex: 3),
    ),
  ]).single;
  s.pages.setPaper([first.id], paper: Paper.image(paper));
  s.pages.setBookmarked(pdfPage.id, true);
  s.strokes.save([for (var i = 0; i < 5; i++) _stroke(first.id, i)]);
  s.strokes.save([for (var i = 0; i < 3; i++) _stroke(pdfPage.id, i)]);
  s.elements.save([
    _element('text', first.id, 'text', const TextData(text: 'Photosynthesis').toJson()),
    _element('image', first.id, 'image', ImageData(blob: image, width: 10, height: 20).toJson()),
    _element('link', first.id, 'link', {
      'target': {'notebook': n.id, 'page': pdfPage.id},
    }),
    _element('web', pdfPage.id, 'link', {
      'target': {'url': 'https://example.com'},
    }),
  ]);
  final chapter = s.outline.add(notebookId: n.id, pageId: first.id, title: 'Chapter');
  s.outline.add(notebookId: n.id, pageId: pdfPage.id, title: 'Part', parentId: chapter.id);
  s.recordings.save(
    notebookId: n.id,
    parts: [RecordingPart(audio, 4000)],
    mime: 'audio/mp4',
    title: 'Talk',
    segments: const [RecordingSegment(1000, 4000)],
    waveform: waveform,
  );
  return n;
}

Future<Uint8List> _export(AppServices s, LenScope scope) async {
  final out = OutputMemoryStream();
  await s.lenFiles.write(scope, out);
  return out.getBytes();
}

Future<LenImportResult> _import(
  AppServices s,
  Uint8List bytes, {
  String? folderName,
  bool keepIds = false,
  Set<String> skip = const {},
}) async => s.lenFiles.import(
  await s.lenFiles.open(InputMemoryStream(bytes)),
  folderName: folderName,
  keepIds: keepIds,
  skip: skip,
);

List<Map<String, Object?>> _records(
  AppServices s,
  String collection,
  String where,
  List<Object?> a,
) {
  final store = s.lenFiles.stores.of(collection);
  return [
    for (final row in store.db.select(
      'SELECT * FROM ${store.table} WHERE deleted = 0 AND $where ORDER BY rowid',
      a,
    ))
      store.rowToRecord(row).data!,
  ];
}

/// [data] without the fields that hold ids.
Map<String, Object?> _sansIds(Map<String, Object?> data) => {...data}
  ..removeWhere(
    (k, _) => const {'surfaceId', 'notebookId', 'pageId', 'parentId', 'folderId'}.contains(k),
  );

/// [records] without ids, comparable whatever their order.
List<String> _canonical(Iterable<Map<String, Object?>> records) =>
    [for (final r in records) jsonEncode(_sansIds(r))]..sort();

void main() {
  late AppServices source, target;
  setUp(() {
    source = _services();
    target = _services();
  });
  tearDown(() {
    source.dispose();
    target.dispose();
  });

  test('a notebook comes back losslessly in a fresh library, under new ids', () async {
    final n = await _richNotebook(source);
    final bytes = await _export(source, LenScope.notebook(n.id));
    final result = await _import(target, bytes);
    expect(result.manifest.kind, LenArchiveKind.notebook);
    expect(result.manifest.title, 'Lecture');
    expect(result.skipped, 0);
    expect(result.missingBlobs, 0);

    final copy = target.notebooks.get(result.notebooks.single)!;
    expect(copy.id, isNot(n.id));
    expect(
      _sansIds(_records(target, 'notebooks', 'id = ?', [copy.id]).single),
      _sansIds(_records(source, 'notebooks', 'id = ?', [n.id]).single),
    );
    final pages = source.pages.pagesOf(n.id), copied = target.pages.pagesOf(copy.id);
    expect(copied, hasLength(2));
    for (final (i, page) in pages.indexed) {
      final c = copied[i];
      expect(c.id, isNot(page.id));
      expect(
        _sansIds(_records(target, 'pages', 'id = ?', [c.id]).single),
        _sansIds(_records(source, 'pages', 'id = ?', [page.id]).single),
      );
      for (final collection in ['strokes', 'elements']) {
        final mine = _records(source, collection, 'surface_id = ?', [page.id]);
        final theirs = _records(target, collection, 'surface_id = ?', [c.id]);
        expect(theirs.length, mine.length);
        if (collection == 'strokes') expect(_canonical(theirs), _canonical(mine));
      }
    }
    // Text, image and web link elements are equal; the page link leads to the copy.
    final elements = SurfaceCopier(
      target.strokes,
      elements: target.elements,
    ).loadAllElements(copied.first.id);
    expect(
      elements.firstWhere((e) => e.type == 'text').data,
      const TextData(text: 'Photosynthesis').toJson(),
    );
    expect(ImageData.fromJson(elements.firstWhere((e) => e.type == 'image').data).width, 10);
    expect(elements.firstWhere((e) => e.type == 'link').data['target'], {
      'notebook': copy.id,
      'page': copied.last.id,
    });
    // Outline nesting and pages.
    final outline = target.outline.entriesOf(copy.id);
    final chapter = outline.firstWhere((e) => e.title == 'Chapter');
    final part = outline.firstWhere((e) => e.title == 'Part');
    expect(chapter.pageId, copied.first.id);
    expect((part.parentId, part.pageId), (chapter.id, copied.last.id));
    // Recording and every blob, byte for byte.
    expect(
      _records(target, 'recordings', 'notebook_id = ?', [copy.id]).map(_sansIds),
      _records(source, 'recordings', 'notebook_id = ?', [n.id]).map(_sansIds),
    );
    final blobs = source.database.db.select('SELECT sha256, mime FROM blobs');
    expect(blobs, hasLength(5));
    for (final row in blobs) {
      final sha = row['sha256'] as String;
      expect(await target.blobs.read(sha), await source.blobs.read(sha));
      expect(target.blobs.mimeOf(sha), row['mime']);
    }
    // Everything is marked for sync, stamped by this device.
    for (final collection in LenFormat.collections) {
      final store = target.lenFiles.stores.of(collection);
      for (final r in store.dirtyRecords(1000)) {
        expect(r.deviceId, target.strokes.deviceId);
      }
    }
    expect(target.strokes.dirtyRecords(1000), hasLength(8));
    expect(target.notebooks.dirtyRecords(10).single.id, copy.id);
  });

  test('importing twice gives two copies; an import is searchable', () async {
    final n = await _richNotebook(source);
    final bytes = await _export(source, LenScope.notebook(n.id));
    final a = await _import(source, bytes), b = await _import(source, bytes);
    expect({n.id, a.notebooks.single, b.notebooks.single}, hasLength(3));
    expect(source.notebooks.list(), hasLength(3));
    final hits = source.search.search('Photosynthesis');
    expect(hits.map((h) => h.notebookId).toSet(), hasLength(3));
  });

  test('a folder keeps its tree; the library restores into a dated folder', () async {
    final top = source.folders.create(name: 'Biology', color: 1);
    final inner = source.folders.create(name: 'Cells', parentId: top.id, color: 2);
    final outside = source.folders.create(name: 'Other', color: 3);
    final a = await _richNotebook(source, title: 'A');
    final b = await _richNotebook(source, title: 'B');
    final c = await _richNotebook(source, title: 'C');
    final trashed = await _richNotebook(source, title: 'Old');
    source.notebooks.moveTo(a.id, top.id);
    source.notebooks.moveTo(b.id, inner.id);
    source.notebooks.moveTo(c.id, outside.id);
    source.notebooks.moveTo(trashed.id, top.id);
    source.notebooks.trash(trashed.id);
    final template = await source.blobs.putBytes(Uint8List(8), mime: 'image/png');
    source.templates.create(name: 'Mine', blob: template, size: const Size(100, 100));

    final folder = await _import(target, await _export(source, LenScope.folder(top.id)));
    expect(folder.manifest.title, 'Biology');
    expect(folder.notebooks, hasLength(2)); // Not the trash.
    final copiedTop = target.folders.get(folder.folder!)!;
    expect((copiedTop.name, copiedTop.parentId), ('Biology', null));
    final cells = target.folders.childrenOf(copiedTop.id).single;
    expect(cells.name, 'Cells');
    expect(
      {
        for (final id in folder.notebooks)
          target.notebooks.get(id)!.title: target.notebooks.get(id)!.folderId,
      },
      {'A': copiedTop.id, 'B': cells.id},
    );
    expect(target.templates.list(), isEmpty);

    final backup = await _import(
      target,
      await _export(source, const LenScope.library()),
      folderName: 'Backup 13 Oct 2026',
    );
    expect(backup.manifest.kind, LenArchiveKind.library);
    final restored = target.folders.get(backup.folder!)!;
    expect((restored.name, restored.parentId), ('Backup 13 Oct 2026', null));
    expect(target.folders.childrenOf(restored.id).map((f) => f.name).toSet(), {'Biology', 'Other'});
    expect(backup.notebooks, hasLength(3));
    expect(target.notebooks.trashed(), isEmpty); // The Trash isn't backed up (R8-23).
    expect(target.templates.list().single.name, 'Mine');
    // Restoring again adds copies but not a second template.
    await _import(target, await _export(source, const LenScope.library()), folderName: 'Again');
    expect(target.templates.list(), hasLength(1));
  });

  test('a canvas keeps its ink on its own surface', () async {
    final canvas = source.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.dotted,
      coverColor: 0,
    );
    source.strokes.save([for (var i = 0; i < 4; i++) _stroke(canvas.id, i)]);
    final result = await _import(target, await _export(source, LenScope.notebook(canvas.id)));
    final copy = result.notebooks.single;
    expect(target.notebooks.get(copy)!.kind, NotebookKind.canvas);
    expect(SurfaceCopier(target.strokes).loadAll(copy), hasLength(4));
  });

  group('files that aren’t Len files fail without leaving anything behind', () {
    Future<void> expectRefused(Uint8List bytes, Matcher message) async {
      await expectLater(
        _import(target, bytes),
        throwsA(isA<LenArchiveException>().having((e) => e.message, 'message', message)),
      );
      expect(target.notebooks.list(), isEmpty);
      for (final table in ['pages', 'strokes', 'elements', 'outline', 'recordings', 'folders']) {
        expect(target.database.db.select('SELECT 1 FROM $table'), isEmpty, reason: table);
      }
      expect(target.database.db.select('SELECT 1 FROM blobs'), isEmpty);
    }

    test('not a zip, or a zip without a manifest', () async {
      await expectRefused(Uint8List.fromList(utf8.encode('hello')), contains('isn’t a Len file'));
      final other = ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.string('a.txt', 'hi')));
      await expectRefused(other, contains('isn’t a Len file'));
    });

    test('a newer version', () async {
      final zip = ZipEncoder().encodeBytes(
        Archive()
          ..add(ArchiveFile.string('manifest.json', jsonEncode({'format': 'len', 'version': 99}))),
      );
      await expectRefused(zip, contains('newer Len'));
    });

    test('a truncated file', () async {
      final n = await _richNotebook(source);
      final bytes = await _export(source, LenScope.notebook(n.id));
      await expectRefused(bytes.sublist(0, bytes.length ~/ 2), contains('Len file'));
    });

    test('cancelling removes what was imported so far', () async {
      final n = await _richNotebook(source);
      final bytes = await _export(source, LenScope.notebook(n.id));
      final token = CancellationToken();
      await expectLater(
        target.lenFiles.import(
          await target.lenFiles.open(InputMemoryStream(bytes)),
          cancel: token,
          onProgress: (done) {
            if (done > 0.9) token.cancel();
          },
        ),
        throwsA(isA<Cancelled>()),
      );
      expect(target.database.db.select('SELECT 1 FROM strokes'), isEmpty);
      expect(target.database.db.select('SELECT 1 FROM blobs'), isEmpty);
    });
  });

  group('damaged parts are left out, the rest imported (R8-14)', () {
    test('a blob whose bytes do not match its name', () async {
      final n = await _richNotebook(source);
      final bytes = await _export(source, LenScope.notebook(n.id));
      // Flip one byte inside the stored audio blob.
      final at = _find(bytes, utf8.encode('audio pretend'));
      bytes[at] ^= 0xFF;
      final result = await _import(target, bytes);
      expect(result.missingBlobs, 1);
      expect(result.complete, isFalse);
      expect(result.problems.single, startsWith('Damaged file'));
      expect(target.pages.pagesOf(result.notebooks.single), hasLength(2));
      expect(target.database.db.select('SELECT 1 FROM blobs'), hasLength(4));
    });

    test('lines that are not JSON', () async {
      final n = await _richNotebook(source);
      final archive = ZipDecoder().decodeBytes(await _export(source, LenScope.notebook(n.id)));
      final broken = Archive();
      for (final f in archive.files) {
        broken.add(
          f.name.startsWith('records/')
              ? ArchiveFile.string(f.name, '${utf8.decode(f.content)}{not json\n[1, 2')
              : ArchiveFile.bytes(f.name, f.content),
        );
      }
      final result = await _import(target, ZipEncoder().encodeBytes(broken));
      expect(result.skipped, 2);
      expect(target.strokes.dirtyRecords(100), hasLength(8));
    });

    test('a records part that can’t be read at all, and a damaged blob index', () async {
      final n = await _richNotebook(source);
      final archive = ZipDecoder().decodeBytes(await _export(source, LenScope.notebook(n.id)));
      final broken = Archive();
      for (final f in archive.files) {
        broken.add(switch (f.name) {
          'blobs.json' => ArchiveFile.string(f.name, '{"broken'),
          _ => ArchiveFile.bytes(f.name, f.content),
        });
      }
      // A second part of invalid UTF-8.
      broken.add(ArchiveFile.bytes('records/000002.jsonl', Uint8List.fromList([0xFF, 0xFE, 0x80])));
      final result = await _import(target, ZipEncoder().encodeBytes(broken));
      expect(result.lostParts, 1);
      expect(result.missingBlobs, 0); // Found without the index.
      expect(result.problems, hasLength(2));
      expect(target.notebooks.list(), hasLength(1));
      expect(target.database.db.select('SELECT 1 FROM blobs'), hasLength(5));
    });
  });

  test('malformed records are skipped, the rest imported', () async {
    final n = await _richNotebook(source);
    final archive = ZipDecoder().decodeBytes(await _export(source, LenScope.notebook(n.id)));
    final odd = Archive();
    for (final f in archive.files) {
      if (!f.name.startsWith('records/')) {
        odd.add(ArchiveFile.bytes(f.name, f.content));
        continue;
      }
      final lines = const LineSplitter().convert(utf8.decode(f.content));
      final bad = [
        for (final line in lines)
          if ((jsonDecode(line) as Map)['collection'] == 'strokes' &&
              !line.contains('"color":4278190080'))
            line
          else if ((jsonDecode(line) as Map)['collection'] == 'strokes')
            line.replaceFirst('"tool":"ballpoint"', '"tool":"crayon"')
          else
            line,
        '{"collection": "strokes"}',
      ];
      odd.add(ArchiveFile.string(f.name, bad.join('\n')));
    }
    final result = await _import(target, ZipEncoder().encodeBytes(odd));
    expect(result.skipped, 3); // Two strokes with an unknown tool, one non-record.
    expect(target.strokes.dirtyRecords(100), hasLength(6));
  });

  test('large notebooks stream: records in parts, blobs one at a time', () async {
    final backend = _CountingBackend();
    final big = AppServices.create(AppDatabase.inMemory(), blobBackend: backend);
    addTearDown(big.dispose);
    final n = big.notebooks.create(
      title: 'Big',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = big.pages.pagesOf(n.id).single;
    // About 6 MB of records: more than one part.
    big.strokes.save([
      for (var i = 0; i < 2000; i++)
        Stroke(
          id: 's$i',
          surfaceId: page.id,
          tool: InkTool.ballpoint,
          color: 0xFF000000,
          width: 2,
          points: [for (var j = 0; j < 200; j++) StrokePoint(j.toDouble(), i.toDouble(), 0.5)],
          createdAt: i,
        ),
    ]);
    const blobSize = 256 * 1024;
    for (var i = 0; i < 12; i++) {
      final sha = await big.blobs.putBytes(
        Uint8List(blobSize)..fillRange(0, 8, i + 1),
        mime: 'image/png',
      );
      big.elements.save([
        _element('img$i', page.id, 'image', ImageData(blob: sha, width: 1, height: 1).toJson()),
      ]);
    }
    final out = _CountingOutput();
    backend.output = out;
    final report = await big.lenFiles.write(LenScope.notebook(n.id), out);
    expect(report.blobs, 12);
    // Each blob was read only once the one before it was written out.
    for (var i = 1; i < backend.readsAt.length; i++) {
      expect(backend.readsAt[i] - backend.readsAt[i - 1], greaterThanOrEqualTo(blobSize));
    }
    expect(out.length, greaterThan(12 * blobSize));

    final bytes = await _export(big, LenScope.notebook(n.id));
    final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name);
    expect(names.where((name) => name.startsWith('records/')).length, greaterThan(1));
    final result = await _import(target, bytes);
    expect(
      SurfaceCopier(target.strokes)
          .loadAll(target.pages.pagesOf(result.notebooks.single).single.id),
      hasLength(2000),
    );
  });
}

int _find(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  throw StateError('not found');
}

/// Notes how much had been written when each blob was read.
class _CountingBackend extends MemoryBlobBackend {
  _CountingOutput? output;
  final List<int> readsAt = [];

  @override
  Future<Uint8List?> read(String sha) {
    if (output case final out?) readsAt.add(out.length);
    return super.read(sha);
  }
}

/// An output that only counts.
class _CountingOutput extends OutputStream {
  _CountingOutput() : super(byteOrder: ByteOrder.littleEndian);

  @override
  int length = 0;

  @override
  void clear() => length = 0;

  @override
  void flush() {}

  @override
  void writeByte(int value) => length++;

  @override
  void writeBytes(List<int> bytes, {int? length}) => this.length += length ?? bytes.length;

  @override
  void writeStream(InputStream stream) => length += stream.length;

  @override
  Uint8List getBytes() => Uint8List(0);

  @override
  Uint8List subset(int start, [int? end]) => Uint8List(0);
}
