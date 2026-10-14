import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/archive/ranged_input.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';

import 'support/property.dart';

// Properties of Len files (docs/SYNC_PROTOCOL.md, "Len files"): a notebook
// exported and imported again is the same notebook under new ids, every
// import is an independent copy, and a file read in slices reads the same.

AppServices _services() {
  final s = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
  addTearDown(s.dispose);
  return s;
}

StrokeStyle _style(math.Random r) {
  final ends = StrokeEnds.values[r.nextInt(StrokeEnds.values.length)];
  final tapered = ends == StrokeEnds.tapered;
  return StrokeStyle(
    opacity: r.nextDouble(),
    thinning: r.nextDouble(),
    streamline: r.nextDouble(),
    unit: r.nextBool() ? 0 : r.nextDouble() * 10,
    ends: ends,
    taperStart: tapered ? r.nextDouble() * StrokeStyle.maxTaper : 0,
    taperEnd: tapered ? r.nextDouble() * StrokeStyle.maxTaper : 0,
    startPhase: r.nextBool() ? 0 : 1 - r.nextDouble(),
    cutEnd: r.nextBool(),
  );
}

Stroke _stroke(math.Random r, String surface) {
  final x = r.nextDouble() * 4000 - 2000, y = r.nextDouble() * 4000 - 2000;
  final tool = InkTool.values[r.nextInt(InkTool.values.length)];
  return Stroke(
    id: 'ignored-${r.nextInt(1 << 30)}',
    surfaceId: surface,
    tool: tool,
    color: 0xFF000000 | r.nextInt(0xFFFFFF),
    width: 0.5 + r.nextDouble() * 40,
    points: [
      for (var i = 1 + r.nextInt(40); i > 0; i--)
        StrokePoint(x + r.nextDouble() * 300, y + r.nextDouble() * 300, r.nextDouble()),
    ],
    createdAt: 1700000000000 + r.nextInt(1 << 30),
    style: tool.isHighlighter && r.nextBool() ? null : _style(r),
  );
}

String _text(math.Random r) => String.fromCharCodes([
  for (var i = r.nextInt(30); i > 0; i--)
    const [0x20, 0x41, 0x7A, 0xE9, 0x3B1, 0x4E2D, 0x1F600, 0x0A][r.nextInt(8)] + r.nextInt(3),
]);

SurfaceElement _element(math.Random r, String surface, String type, Map<String, Object?> data) =>
    SurfaceElement(
      id: 'e${r.nextInt(1 << 30)}',
      surfaceId: surface,
      type: type,
      rect: Rect.fromLTWH(
        r.nextDouble() * 1000,
        r.nextDouble() * 1000,
        10 + r.nextDouble() * 500,
        10 + r.nextDouble() * 200,
      ),
      rotation: r.nextDouble() * 6 - 3,
      z: r.nextInt(5) - 2,
      createdAt: r.nextInt(1 << 30),
      data: data,
    );

/// Fills [s] with a random notebook: pages (or a canvas) of ink, text,
/// images (blobs), links between pages and an outline.
Future<Notebook> _notebook(AppServices s, math.Random r) async {
  final canvas = r.nextDouble() < 0.25;
  final styles = [
    for (final p in PaperStyle.values)
      if (!p.needsParams) p,
  ];
  final n = s.notebooks.create(
    title: _text(r),
    kind: canvas ? NotebookKind.canvas : NotebookKind.paged,
    paper: styles[r.nextInt(styles.length)],
    coverColor: r.nextInt(1 << 32),
  );
  final surfaces = canvas ? [n.id] : [for (final p in s.pages.pagesOf(n.id)) p.id];
  if (!canvas) {
    for (var i = r.nextInt(4); i > 0; i--) {
      final pages = s.pages.pagesOf(n.id);
      final page = s.pages.addPage(
        n.id,
        paper: Paper(styles[r.nextInt(styles.length)]),
        after: r.nextBool() ? null : pages[r.nextInt(pages.length)],
      );
      surfaces.add(page.id);
      if (r.nextBool()) s.pages.setBookmarked(page.id, true);
    }
  }
  for (final surface in surfaces) {
    s.strokes.save([for (var i = r.nextInt(7); i > 0; i--) _stroke(r, surface)]);
    final elements = <SurfaceElement>[
      for (var i = r.nextInt(3); i > 0; i--)
        _element(r, surface, 'text', TextData(text: _text(r)).toJson()),
    ];
    if (r.nextDouble() < 0.4) {
      final bytes = Uint8List.fromList([for (var i = r.nextInt(3000); i > 0; i--) r.nextInt(256)]);
      final blob = await s.blobs.putBytes(bytes, mime: 'image/png');
      elements.add(
        _element(
          r,
          surface,
          'image',
          ImageData(blob: blob, width: 1 + r.nextInt(99), height: 1 + r.nextInt(99)).toJson(),
        ),
      );
    }
    if (!canvas && r.nextBool()) {
      final target = surfaces[r.nextInt(surfaces.length)];
      elements.add(
        _element(r, surface, 'link', {
          'target': {'notebook': n.id, 'page': target},
        }),
      );
    }
    s.elements.save(elements);
  }
  if (!canvas) {
    final entries = <String>[];
    for (var i = r.nextInt(4); i > 0; i--) {
      final entry = s.outline.add(
        notebookId: n.id,
        pageId: surfaces[r.nextInt(surfaces.length)],
        title: 'o$i ${_text(r)}',
        parentId: entries.isEmpty || r.nextBool() ? null : entries[r.nextInt(entries.length)],
      );
      entries.add(entry.id);
    }
  }
  return n;
}

/// Everything notebook [id] of [s] holds, in page order, with the ids of
/// the notebook and its pages named by position (an import gives them new
/// ones) and other rows' ids left out.
Future<String> _content(AppServices s, String id) async {
  final pages = [for (final p in s.pages.pagesOf(id)) p.id];
  final names = {id: 'N', for (final (i, p) in pages.indexed) p: 'P$i'};
  final outline = s.outline.entriesOf(id);
  final titles = {for (final e in outline) e.id: e.title};
  String rename(Object? value) {
    var text = jsonEncode(value);
    names.forEach((from, to) => text = text.replaceAll(from, to));
    return text;
  }

  List<String> records(String collection, String where, List<Object?> args) {
    final store = s.lenFiles.stores.of(collection);
    return [
      for (final row in store.db.select(
        'SELECT * FROM ${store.table} WHERE deleted = 0 AND $where',
        args,
      ))
        rename(store.rowToRecord(row).data),
    ]..sort();
  }

  final blobs = <String>[];
  for (final row in s.database.db.select('SELECT sha256 FROM blobs ORDER BY sha256')) {
    final sha = row['sha256'] as String;
    blobs.add('$sha ${base64Encode((await s.blobs.read(sha))!)}');
  }
  return const JsonEncoder.withIndent(' ').convert({
    'notebook': records('notebooks', 'id = ?', [id]),
    'pages': [
      for (final p in [id, ...pages])
        {
          'page': records('pages', 'id = ?', [p]),
          'strokes': records('strokes', 'surface_id = ?', [p]),
          'elements': records('elements', 'surface_id = ?', [p]),
        },
    ],
    'outline': [
      for (final e in outline) rename([e.title, e.pageId, titles[e.parentId]]),
    ]..sort(),
    'blobs': blobs,
  });
}

/// Every row id of notebook [id] in [s] (itself, pages, content, outline).
Set<String> _ids(AppServices s, String id) {
  final db = s.database.db;
  final pages = [for (final p in s.pages.pagesOf(id)) p.id];
  final surfaces = [id, ...pages];
  final marks = List.filled(surfaces.length, '?').join(',');
  return {
    id,
    ...pages,
    for (final table in ['strokes', 'elements'])
      for (final row in db.select('SELECT id FROM $table WHERE surface_id IN ($marks)', surfaces))
        row['id'] as String,
    for (final e in s.outline.entriesOf(id)) e.id,
  };
}

Future<Uint8List> _export(AppServices s, String notebook) async {
  final out = OutputMemoryStream();
  await s.lenFiles.write(LenScope.notebook(notebook), out);
  return out.getBytes();
}

/// [bytes] as a file read in slices, as browsers read it; [reads] counts
/// the slices.
RangedInput _ranged(Uint8List bytes, [List<int>? reads]) => RangedInput(
  RangedFile(bytes.length, (start, end) async {
    reads?.add(end - start);
    await Future<void>.delayed(Duration.zero);
    return Uint8List.fromList(bytes.sublist(start, end));
  }),
);

Future<String> _import(AppServices s, Uint8List bytes, {required bool ranged}) async {
  final source = await s.lenFiles.open(ranged ? _ranged(bytes) : InputMemoryStream(bytes));
  final result = await s.lenFiles.import(source);
  expect(result.skipped, 0);
  expect(result.missingBlobs, 0);
  expect(result.problems, isEmpty);
  return result.notebooks.single;
}

void main() {
  test('a notebook exported and imported is the same notebook under new ids', () async {
    await forAll(Gens.intIn(0, 1 << 30), (seed) async {
      final r = math.Random(seed);
      final source = _services(), target = _services();
      final n = await _notebook(source, r);
      final original = await _content(source, n.id);
      final bytes = await _export(source, n.id);

      final copy = await _import(target, bytes, ranged: r.nextBool());
      expect(await _content(target, copy), original);
      expect(_ids(target, copy).intersection(_ids(source, n.id)), isEmpty);

      // Imported twice beside the original: two more copies, independent
      // of each other and of it.
      final a = await _import(source, bytes, ranged: r.nextBool());
      final b = await _import(source, bytes, ranged: r.nextBool());
      final (idsN, idsA, idsB) = (_ids(source, n.id), _ids(source, a), _ids(source, b));
      expect(idsA.intersection(idsN), isEmpty);
      expect(idsB.intersection(idsN), isEmpty);
      expect(idsA.intersection(idsB), isEmpty);
      source.notebooks.delete(a);
      expect(await _content(source, b), original);
      expect(await _content(source, n.id), original);
    }, runs: 40);
  });

  test('a library backed up and restored into an empty one keeps its notebooks and ids', () async {
    await forAll(
      Gens.intIn(0, 1 << 30),
      (seed) async {
        final r = math.Random(seed);
        final source = _services(), target = _services();
        final notebooks = [for (var i = 1 + r.nextInt(3); i > 0; i--) await _notebook(source, r)];
        final out = OutputMemoryStream();
        await source.lenFiles.write(const LenScope.library(), out);
        final bytes = out.getBytes();
        final opened = await target.lenFiles.open(
          r.nextBool() ? _ranged(bytes) : InputMemoryStream(bytes),
        );
        expect(opened.contents.notebooks.keys.toSet(), {for (final n in notebooks) n.id});
        final result = await target.lenFiles.import(opened, keepIds: true);
        expect(result.problems, isEmpty);
        expect(result.notebooks.toSet(), {for (final n in notebooks) n.id});
        for (final n in notebooks) {
          expect(_ids(target, n.id), _ids(source, n.id));
          expect(await _content(target, n.id), await _content(source, n.id));
        }
      },
      runs: 150,
      seed: 777,
    );
  });

  test('a file read in slices reads as the whole file, whatever the slices', () async {
    await forAll(Gens.intIn(0, 1 << 30), (seed) async {
      final r = math.Random(seed);
      final bytes = Uint8List.fromList([
        for (var i = 1 + r.nextInt(5000); i > 0; i--) r.nextInt(256),
      ]);
      final file = RangedFile(
        bytes.length,
        (start, end) async => Uint8List.fromList(bytes.sublist(start, end)),
      );
      final kept = <(int, int)>[];
      var content = (0, 0);
      bool loaded(int at) => [...kept, content].any((k) => at >= k.$1 && at < k.$2);
      for (var step = 0; step < 12; step++) {
        final start = r.nextInt(bytes.length), end = start + r.nextInt(bytes.length - start + 1);
        switch (r.nextInt(3)) {
          case 0:
            await file.load(start, end);
            content = (start, end);
          case 1:
            await file.load(start, end, keep: true);
            if (end > start) kept.add((start, end));
          default:
            final ranges = [for (var i = r.nextInt(4); i > 0; i--) (r.nextInt(bytes.length), 0)]
                .map((p) => (p.$1, p.$1 + r.nextInt(bytes.length - p.$1 + 1)))
                .toList();
            await file.keepAll(ranges, gap: r.nextInt(64));
            kept.addAll(ranges);
        }
        // Every byte loaded reads as it is in the file.
        for (var i = 0; i < 40; i++) {
          final at = r.nextInt(bytes.length);
          if (loaded(at)) expect(file.byteAt(at), bytes[at], reason: 'byte $at');
        }
        final from = r.nextInt(bytes.length), to = from + r.nextInt(bytes.length - from + 1);
        if (List.generate(to - from, (i) => from + i).every(loaded)) {
          expect(file.bytes(from, to), bytes.sublist(from, to));
          final input = RangedInput(file, start: from, length: to - from);
          final at = r.nextInt(to - from + 1);
          input.position = at;
          expect(input.toUint8List(), bytes.sublist(from + at, to));
          expect(input.subset(position: at).toUint8List(), bytes.sublist(from + at, to));
        }
      }
    }, runs: 300);
  });

  test('entries read from slices in pieces of any size are whole', () async {
    final s = _services();
    final r = math.Random(7);
    final n = await _notebook(s, r);
    final surface = s.pages.pagesOf(n.id).firstOrNull?.id ?? n.id;
    for (var i = 0; i < 3; i++) {
      final bytes = Uint8List.fromList([for (var j = 20000 * i; j > 0; j--) r.nextInt(256)]);
      final blob = await s.blobs.putBytes(bytes, mime: 'application/pdf');
      final image = ImageData(blob: blob, width: 1, height: 1).toJson();
      s.elements.save([_element(r, surface, 'image', image)]);
    }
    final file = await _export(s, n.id);
    final whole = ZipDecoder().decodeBytes(file);
    await forAll(Gens.intIn(1, 30000), (piece) async {
      final reads = <int>[];
      final source = await LenSource.open(_ranged(file, reads));
      for (final entry in source.archive.files.where((f) => f.isFile)) {
        final parts = await LenSource.chunks(entry, piece: piece).toList();
        expect(parts.every((p) => p.length <= piece), isTrue);
        expect(
          Uint8List.fromList(parts.expand((p) => p).toList()),
          whole.find(entry.name)!.content,
          reason: entry.name,
        );
      }
      await source.close();
    }, runs: 40);
  });
}
