import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/sync/sync_api.dart';

import 'support/big_library.dart';

/// A serving-only sync server: every record of a library, in feed order.
class _Feed {
  _Feed(this.records);

  final List<Map<String, Object?>> records;
  final _encoded = <List<int>>[];

  /// Encodes the records not yet served, so serving a page costs (the
  /// client's thread, which this mock shares) only a copy.
  void encodeAhead() {
    for (var i = _encoded.length; i < records.length; i++) {
      _encoded.add(utf8.encode(jsonEncode(records[i])));
    }
  }

  /// Resident memory at each pull request.
  final rss = <int>[];
  int pulls = 0;

  late final client = MockClient((request) async {
    switch (request.url.path) {
      case '/v1/health':
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'protocol': 1,
            'maxBlobBytes': 1 << 30,
            'blobsCollectedAt': 0,
            'serverId': 'bench',
          }),
          200,
        );
      case '/v1/push':
        return http.Response(jsonEncode({'applied': 0, 'ignored': 0, 'serverSeq': 0}), 200);
      case '/v1/pull':
        rss.add(ProcessInfo.currentRss);
        pulls++;
        final since = int.parse(request.url.queryParameters['since']!);
        final limit = int.parse(request.url.queryParameters['limit']!);
        encodeAhead();
        final end = math.min(since + limit, records.length);
        final body = BytesBuilder(copy: false)..add(utf8.encode('{"records":['));
        for (var i = since; i < end; i++) {
          if (i > since) body.addByte(0x2c);
          body.add(_encoded[i]);
        }
        body.add(utf8.encode('],"nextSince":$end,"hasMore":${end < records.length}}'));
        return http.Response.bytes(
          body.takeBytes(),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    }
    return http.Response('', 404);
  });

  SyncApi get api => SyncApi(baseUrl: 'http://sync.test', token: 't', client: client);
}

/// Every syncable row of [s] as wire records, parents first (as a push
/// would leave them in the server's feed).
List<Map<String, Object?>> _recordsOf(AppServices s) {
  final out = <Map<String, Object?>>[];
  for (final store in s.sync.engine.stores) {
    String? after;
    while (true) {
      final page = store.dirtyRecords(2000, after: after);
      if (page.isEmpty) break;
      for (final r in page) {
        out.add(r.toJson());
      }
      after = page.last.id;
    }
  }
  return out;
}

void main() {
  test('first full pull of a large library, then an incremental sync', () async {
    final clock = BenchClock();
    final source = AppServices.create(AppDatabase.inMemory(), clock: clock);
    // 300 notebooks × 10 pages, each first page a page of handwriting:
    // ≈ 70,000 strokes (a 2M-stroke library is ~30× this, page by page
    // the same work).
    BigLibrary.build(
      source,
      clock,
      folderCount: 20,
      notebookCount: 300,
      trashCount: 20,
      coverLines: 25,
    );
    final records = _recordsOf(source);
    source.dispose();
    final strokes = records.where((r) => r['collection'] == 'strokes').length;

    final files = BenchFiles();
    addTearDown(files.dispose);
    final device = AppServices.create(AppDatabase.open(files.dbPath), clock: BenchClock(9));
    addTearDown(device.dispose);
    final feed = _Feed(records)..encodeAhead();
    final rssBefore = ProcessInfo.currentRss;
    final watch = Stopwatch()..start();
    var done = false;
    final syncing = device.sync.engine.sync(feed.api).whenComplete(() => done = true);
    final turns = (await turnsUntil(() => done))..sort();
    final changes = await syncing;
    final full = watch.elapsedMilliseconds;
    expect(changes.notebooks, isTrue);
    expect(device.database.db.select('SELECT COUNT(*) AS n FROM strokes').first['n'], strokes);
    final peak = feed.rss.fold(0, math.max);
    report(
      'first pull: ${records.length} records ($strokes strokes) in ${feed.pulls} pages, '
      '${full}ms (${(full * 1000 / records.length).round()}µs a record); UI thread blocked: '
      'p50 ${turns[turns.length ~/ 2]}ms, p99 ${turns[turns.length * 99 ~/ 100]}ms, '
      'max ${turns.last}ms; RSS +${(peak - rssBefore) >> 20} MB; '
      'db ${files.dbBytes >> 20} MB',
    );

    // A few changes from another device: one renamed notebook, three strokes.
    final tail = records.length;
    final notebook = records.firstWhere((r) => r['collection'] == 'notebooks');
    final stroke = records.lastWhere((r) => r['collection'] == 'strokes');
    feed.records.addAll([
      {...notebook, 'updatedAt': (notebook['updatedAt']! as int) + 1},
      for (var i = 0; i < 3; i++)
        {...stroke, 'id': 'new-stroke-$i', 'updatedAt': (stroke['updatedAt']! as int) + 1},
    ]);
    watch.reset();
    await device.sync.engine.sync(feed.api);
    final incrementalMs = watch.elapsedMilliseconds;
    expect(feed.records.length - tail, 4);
    // Nothing more to pull or push: the cost of an idle sync.
    watch.reset();
    await device.sync.engine.sync(feed.api);
    final idleMs = watch.elapsedMilliseconds;
    report('incremental sync (4 records): ${incrementalMs}ms; idle sync: ${idleMs}ms');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
