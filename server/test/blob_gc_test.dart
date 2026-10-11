import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late RecordStore records;
  late BlobStore blobs;
  late BlobGc gc;
  var version = 0;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_blob_gc_test_');
    records = RecordStore.open('${dir.path}/len.db');
    blobs = BlobStore.open('${dir.path}/blobs');
    gc = BlobGc(records, blobs, grace: const Duration(days: 30));
  });
  tearDown(() {
    records.close();
    dir.deleteSync(recursive: true);
  });

  final t0 = DateTime.now();
  DateTime day(int n) => t0.add(Duration(days: n));

  /// Stores a blob whose file looks [age] old.
  Future<String> blob(String content, {Duration age = const Duration(days: 365)}) async {
    final bytes = utf8.encode(content);
    final sha = sha256.convert(bytes).toString();
    await blobs.put(sha, Stream.value(bytes), maxBytes: 1 << 20);
    File(blobs.pathFor(sha)).setLastModifiedSync(t0.subtract(age));
    return sha;
  }

  void put(String collection, String id, Map<String, Object?>? data) => records.push([
    SyncRecord(
      collection: collection,
      id: id,
      updatedAt: ++version,
      deviceId: 'd',
      deleted: data == null,
      data: data,
    ),
  ]);

  test('references are found anywhere in live record data', () async {
    final pdf = await blob('pdf');
    final image = await blob('image');
    final audio = await blob('audio');
    final inLongerHex = await blob('embedded');
    final orphan = await blob('orphan');
    put('pages', 'p', {
      'background': {'type': 'pdf', 'blob': pdf, 'page': 0},
    });
    put('elements', 'e', {
      'type': 'image',
      'data': {'blob': image},
    });
    put('recordings', 'r', {'blob': audio, 'title': 'x'});
    put('future', 'f', {'note': 'ab${inLongerHex}cd'});
    expect(gc.referencedAmong(blobs.list().toSet()), {pdf, image, audio, inLongerHex});
    expect(gc.referencedAmong({orphan}), isEmpty);
  });

  test('tombstoned records do not keep blobs; trashed (live) ones do', () async {
    final deleted = await blob('deleted');
    final trashed = await blob('trashed');
    put('pages', 'p1', {
      'background': {'blob': deleted},
    });
    put('pages', 'p1', null);
    put('pages', 'p2', {
      'background': {'blob': trashed},
    });
    put('notebooks', 'n', {'title': 'x', 'trashedAt': 1});
    expect(gc.referencedAmong({deleted, trashed}), {trashed});
  });

  test('an unreferenced blob is marked first and deleted after the grace period', () async {
    final keep = await blob('keep');
    final orphan = await blob('orphan');
    put('recordings', 'r', {'blob': keep});

    var result = gc.run(now: day(0));
    expect(result.stored, 2);
    expect(result.referenced, 1);
    expect(result.waiting.keys, [orphan]);
    expect(result.deleted, isEmpty);
    expect(records.blobsCollectedAt, 0);

    result = gc.run(now: day(29));
    expect(result.deleted, isEmpty);
    expect(blobs.has(orphan), isTrue);

    final dry = gc.run(now: day(31), dryRun: true);
    expect(dry.deleted, [orphan]);
    expect(blobs.has(orphan), isTrue);

    result = gc.run(now: day(31));
    expect(result.deleted, [orphan]);
    expect(result.deletedBytes, 'orphan'.length);
    expect(blobs.has(orphan), isFalse);
    expect(blobs.has(keep), isTrue);
    expect(records.blobsCollectedAt, day(31).millisecondsSinceEpoch);
    expect(records.unreferencedBlobs(), isEmpty);
  });

  test('a blob referenced again during the grace period is unmarked', () async {
    final sha = await blob('comes back');
    gc.run(now: day(0));
    put('elements', 'e', {
      'data': {'blob': sha},
    });
    gc.run(now: day(10));
    expect(records.unreferencedBlobs(), isEmpty);
    put('elements', 'e', null);
    gc.run(now: day(20)); // Marked anew: the clock restarts.
    expect(gc.run(now: day(45)).deleted, isEmpty);
    expect(gc.run(now: day(51)).deleted, [sha]);
  });

  test('a blob referenced just before deletion is kept and loses its mark', () async {
    final sha = await blob('rescued');
    gc.run(now: day(0));
    // A client pushes a reference between the two scans of a run.
    final racing = _RacingGc(
      records,
      blobs,
      onSecondScan: () {
        put('elements', 'e', {
          'data': {'blob': sha},
        });
      },
    );
    expect(racing.run(now: day(31)).deleted, isEmpty);
    expect(blobs.has(sha), isTrue);
    expect(records.unreferencedBlobs(), isEmpty, reason: 'a later tombstone starts a new grace');
    put('elements', 'e', null);
    expect(gc.run(now: day(32)).deleted, isEmpty);
  });

  test('recently stored or re-uploaded blobs are kept', () async {
    final sha = await blob('fresh', age: Duration.zero);
    gc.run(now: day(-40)); // Marked long ago...
    expect(gc.run(now: t0.add(const Duration(days: 29))).deleted, isEmpty);
    expect(blobs.has(sha), isTrue);
  });

  test('a dry run changes no marks', () async {
    await blob('orphan');
    gc.run(now: day(0), dryRun: true);
    expect(records.unreferencedBlobs(), isEmpty);
  });

  test('health reports blobsCollectedAt', () async {
    await blob('orphan');
    gc.run(now: day(0));
    gc.run(now: day(31));
    final handler = buildHandler(store: records, blobs: blobs, token: 'x' * 16);
    final r = await handler(Request('GET', Uri.parse('http://localhost/v1/health')));
    final json = jsonDecode(await r.readAsString()) as Map<String, Object?>;
    expect(json['blobsCollectedAt'], day(31).millisecondsSinceEpoch);
  });

  group('gc command', () {
    int run(List<String> args, StringBuffer out, [StringBuffer? err]) => runGcCommand(
      args,
      {'LEN_DB_PATH': '${dir.path}/len.db'},
      out: out,
      err: err ?? StringBuffer(),
    );

    test('marks, then deletes after the grace period; --dry-run changes nothing', () async {
      final sha = await blob('orphan');
      // An earlier run marked it 31 days ago.
      records.setUnreferencedBlobs({sha: day(-31).millisecondsSinceEpoch});

      var out = StringBuffer();
      expect(run(['--dry-run'], out), 0);
      expect(out.toString(), contains('would delete 1'));
      expect(blobs.has(sha), isTrue);

      out = StringBuffer();
      expect(run([], out), 0);
      expect(out.toString(), contains('deleted 1'));
      expect(out.toString(), contains(sha));
      expect(blobs.has(sha), isFalse);
    });

    test('--grace-days and bad arguments', () async {
      final sha = await blob('orphan');
      records.setUnreferencedBlobs({sha: day(-3).millisecondsSinceEpoch});
      expect(run(['--grace-days', '7'], StringBuffer()), 0);
      expect(blobs.has(sha), isTrue);
      expect(run(['--grace-days', '2'], StringBuffer()), 0);
      expect(blobs.has(sha), isFalse);

      final err = StringBuffer();
      expect(run(['--grace-days', '0'], StringBuffer(), err), 64);
      expect(run(['--bogus'], StringBuffer(), err), 64);
      expect(err.toString(), contains('Usage'));
    });
  });
}

/// Runs [onSecondScan] right before the re-check of blobs due for deletion.
class _RacingGc extends BlobGc {
  _RacingGc(super.records, super.blobs, {required this.onSecondScan});

  final void Function() onSecondScan;
  var _scans = 0;

  @override
  Set<String> referencedAmong(Set<String> candidates) {
    if (++_scans == 2) onSecondScan();
    return super.referencedAmong(candidates);
  }
}
