import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/syncable.dart';
import 'package:len/data/versions/versions.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/sync/sync_engine.dart';

import 'support/fake_server.dart';

Stroke _ink(String id, String surface, {double x = 10}) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 2,
  points: [StrokePoint(x, 0, 0.5), StrokePoint(x + 5, 9, 0.5)],
  createdAt: 1,
);

void main() {
  late FakeServer server;
  late AppServices a, b;

  setUp(() {
    server = FakeServer();
    SyncApi api(String url, String token) =>
        SyncApi(baseUrl: url, token: token, client: server.client);
    a = AppServices.create(AppDatabase.inMemory(), syncApiFactory: api);
    b = AppServices.create(AppDatabase.inMemory(), syncApiFactory: api);
    for (final s in [a, b]) {
      s.sync.configure(url: 'http://sync.test', token: FakeServer.token);
    }
  });
  tearDown(() {
    a.dispose();
    b.dispose();
  });

  Set<String> strokesOn(AppServices s, String surface) => {
    for (final row in s.database.db.select(
      'SELECT id FROM strokes WHERE surface_id = ? AND deleted = 0',
      [surface],
    ))
      row['id'] as String,
  };

  Future<void> sync(AppServices s) async {
    await s.sync.syncNow();
    expect(s.sync.lastError, isNull);
  }

  test('versions sync with their packs: the other device lists, previews and restores', () async {
    final n = a.notebooks.create(
      title: 'Shared',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = a.pages.pagesOf(n.id).single;
    a.strokes.save([_ink('one', page.id)]);
    final v1 = (await a.versions.record(n.id))!;
    a.strokes.save([_ink('two', page.id, x: 50)]);
    final named = (await a.versions.save(n.id, name: 'Draft'))!;
    await sync(a);
    // Packs and table blobs went up before the records that name them.
    for (final sha in [...(await a.versions.content.body(v1)).packs, ...v1.table]) {
      expect(server.blobs.containsKey(sha), isTrue);
    }

    final changes = <RemoteChanges>[];
    final listening = b.sync.remoteChanges.listen(changes.add);
    addTearDown(listening.cancel);
    await sync(b);
    await pumpEventQueue();
    expect(changes.any((c) => c.versionsOfNotebooks.contains(n.id)), isTrue);
    final seen = b.versions.of(n.id);
    expect(seen.map((v) => v.id), [named.id, v1.id]);
    expect(seen.first.name, 'Draft');
    expect(seen.first.kind, VersionKind.named);
    expect(seen.last.deviceId, a.strokes.deviceId, reason: 'who made it');
    expect(seen.last.deviceId, isNot(b.strokes.deviceId));

    // The table blobs and packs are fetched when needed.
    final body = await b.versions.content.body(seen.last);
    expect(b.versions.content.isHere([body.pages.single.content]), isFalse);
    final preview = await b.versions.content.load(body.pages.single.content, page.id);
    expect(preview.strokes.map((s) => s.id), ['one']);

    // Restored on b, the restore reaches a.
    await b.versions.restore(seen.last);
    expect(strokesOn(b, page.id), {'one'});
    await sync(b);
    await sync(a);
    expect(strokesOn(a, page.id), {'one'});
    // a has the version b saved before restoring, too.
    final before = a.versions.of(n.id).firstWhere((v) => v.kind == VersionKind.restore);
    expect(before.deviceId, b.strokes.deviceId);

    // Deleting a version deletes it everywhere.
    a.versions.delete([v1.id]);
    await sync(a);
    await sync(b);
    expect(b.versions.of(n.id).map((v) => v.id), isNot(contains(v1.id)));
  });

  test('a malformed version is skipped; other records still apply', () async {
    final n = a.notebooks.create(
      title: 'N',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await sync(a);
    await apiFor(server).push(since: 0, [
      const SyncRecord(
        collection: 'versions',
        id: 'bad',
        updatedAt: 5,
        deviceId: 'x',
        deleted: false,
        data: {'notebookId': 'n', 'kind': 'nonsense'},
      ),
    ]);
    await sync(b);
    expect(b.notebooks.get(n.id), isNotNull);
    expect(b.versions.store.get('bad'), isNull);
  });

  test('versions of a page with a background name its blob', () async {
    final n = a.notebooks.create(
      title: 'PDF',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
      empty: true,
    );
    const sha = 'ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12';
    a.pages.insertPages(n.id, [
      (
        size: const Size(100, 140),
        paper: Paper.blank,
        color: PaperColor.white,
        background: PageBackground.pdf(blob: sha, pageIndex: 0),
      ),
    ]);
    final v = (await a.versions.record(n.id))!;
    // Through its table blob: the record names that alone.
    expect(a.sync.engine.blobReferences.all(), contains(sha));
    expect(v.toData().toString(), isNot(contains(sha)));
    expect(a.sync.engine.blobReferences.keeps(sha, 0), isTrue);
  });
}
