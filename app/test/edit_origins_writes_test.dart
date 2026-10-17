import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/cancellation.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/sync/pull_applier.dart';
import 'package:len/sync/pull_page.dart';
import 'package:len/sync/remote_changes.dart';

// Write paths around the origin and base of rows edited in place
// (`EditOrigins`; docs/SYNC_PROTOCOL.md, "Deletion conflicts"): what a
// tombstone says its deletion knew must stay what that deletion knew, and
// copies and imports are edits of their own (stamped by the app's clock).

AppServices _services({Clock clock = const Clock()}) =>
    AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend(), clock: clock);

/// A clock standing still (every write in the same millisecond), with
/// counted ids.
class _StillClock extends Clock {
  _StillClock(this.now);

  int now;
  var _ids = 0;

  @override
  int nowMs() => now;

  @override
  String newId() => 'id${_ids++}';
}

SurfaceElement _text(String id, String surface) => SurfaceElement(
  id: id,
  surfaceId: surface,
  type: 'text',
  rect: const Rect.fromLTWH(0, 0, 50, 20),
  z: 1,
  createdAt: 1,
  data: TextData(text: 'words').toJson(),
);

/// Every column of row [id] of [table].
Map<String, Object?> _row(AppServices s, String table, String id) => {
  ...s.database.db.select('SELECT * FROM $table WHERE id = ?', [id]).single,
};

void main() {
  test('a cancelled restore puts back the tombstones of a notebook deleted here as they were: '
      'what the deletion knew and the content it kept, not the restore', () async {
    final s = _services();
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Diary',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = s.pages.pagesOf(nb.id).single.id;
    s.elements.save([_text('box', page)]);
    final entry = s.outline.add(notebookId: nb.id, pageId: page, title: 'Start');
    final out = OutputMemoryStream();
    await s.lenFiles.write(const LenScope.library(), out);
    final bytes = out.getBytes();
    // Edited, then deleted forever since the backup: the tombstones keep
    // content the backup does not hold.
    s.elements.save([_text('box', page).copyWith(data: TextData(text: 'later words').toJson())]);
    s.notebooks.delete(nb.id);
    final before = [_row(s, 'elements', 'box'), _row(s, 'outline', entry.id)];
    expect(before.first['base_at'], isNotNull);

    final from = await s.lenFiles.open(InputMemoryStream(bytes));
    final cancel = CancellationToken();
    await expectLater(
      s.lenFiles.import(
        from,
        keepIds: true,
        cancel: cancel,
        onProgress: (done) {
          if (done == 1) cancel.cancel(); // Everything written, not yet added.
        },
      ),
      throwsA(isA<Cancelled>()),
    );
    // Never the restore's own version as what the deletion knew (later
    // than every edit it never saw), nor unknown: another device holding
    // this very version of the tombstone must hold the same.
    expect([_row(s, 'elements', 'box'), _row(s, 'outline', entry.id)], before);
  });

  test('a cancelled restore leaves no tombstone of a row edited in place that was not here: '
      'its deletion may know what this device cannot tell', () async {
    final s = _services();
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Diary',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = s.pages.pagesOf(nb.id).single.id;
    s.elements.save([_text('box', page)]);
    final out = OutputMemoryStream();
    await s.lenFiles.write(const LenScope.library(), out);
    final bytes = out.getBytes();
    s.notebooks.delete(nb.id);
    // As on a device that pulled the notebook's deletion but not yet the
    // text box's tombstone (another page of the feed).
    s.database.db.execute("DELETE FROM elements WHERE id = 'box'");

    final from = await s.lenFiles.open(InputMemoryStream(bytes));
    final cancel = CancellationToken();
    await expectLater(
      s.lenFiles.import(
        from,
        keepIds: true,
        cancel: cancel,
        onProgress: (done) {
          if (done == 1) cancel.cancel();
        },
      ),
      throwsA(isA<Cancelled>()),
    );
    expect(s.database.db.select("SELECT * FROM elements WHERE id = 'box'"), isEmpty);
  });

  test('copies of rows holding an older edit are edits of their own: duplicated notebooks, '
      'copied pages and page copies push no base', () {
    final clock = _StillClock(1000);
    final s = _services(clock: clock);
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Diary',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = s.pages.pagesOf(nb.id).single.id;
    s.elements.save([_text('box', page)]);
    final entry = s.outline.add(notebookId: nb.id, pageId: page, title: 'Start');
    // Kept over a deletion elsewhere (see `PullApplier`): now an edit at
    // 1001 holding the content of the one at 1000.
    clock.now = 1001;
    s.elements.keepAsEdit('box', over: 900);
    s.outline.keepAsEdit(entry.id, over: 900);
    expect(s.elements.dirtyRecords(10).single.base?.updatedAt, 1000);

    // Copies made in that same millisecond.
    final other = s.notebooks.create(
      title: 'Other',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    s.notebooks.duplicate(nb.id);
    s.notebooks.copyPages(nb.id, [page], other.id);
    final copy = s.pages.insertPages(nb.id, [
      (
        size: const Size(100, 100),
        paper: Paper(PaperStyle.blank),
        color: PaperColor.white,
        background: null,
      ),
    ]).single;
    SurfaceCopier(s.strokes, elements: s.elements).copy(from: page, to: copy.id);
    for (final store in [s.elements, s.outline]) {
      final copies = [
        for (final r in store.dirtyRecords(100))
          if (r.id != 'box' && r.id != entry.id) r,
      ];
      expect(copies, isNotEmpty);
      for (final r in copies) {
        expect(r.base, isNull, reason: '${r.collection}/${r.id}');
      }
    }
  });

  test('a tombstone known only as such, kept over an edit its deletion knew, keeps no content '
      'origin: a copy brought back later revives no empty row', () async {
    final s = _services();
    addTearDown(s.dispose);
    final engine = s.sync.engine;
    final applier = PullApplier(
      database: s.database,
      settings: s.settings,
      repositories: engine.repositories,
      stores: {for (final store in engine.stores) store.collection: store},
    );
    var seq = 0;
    Future<void> pull(SyncRecord record) => applier.applyPage(
      PullPage(records: [record], nextSince: ++seq, hasMore: true, lastSeq: seq + 1),
      RemoteChanges(),
      hadChanges: false,
      budgetUs: 1 << 30,
      pause: () async => true,
    );
    SyncRecord entry(int at, String device, {bool deleted = false, RecordVersion? base}) =>
        SyncRecord(
          collection: 'outline',
          id: 'o1',
          updatedAt: at,
          deviceId: device,
          deleted: deleted,
          data: deleted
              ? null
              : {
                  'notebookId': 'nb',
                  'pageId': 'p',
                  'parentId': null,
                  'title': 'Start',
                  'createdAt': 1,
                },
          base: base,
        );
    // A deletion on device x that knew the edit at 100 (never seen live here).
    await pull(entry(200, 'x', deleted: true, base: (updatedAt: 100, deviceId: 'b')));
    // That very edit, pushed again late: the deletion stays, kept here as
    // a newer tombstone.
    await pull(entry(300, 'b', base: (updatedAt: 100, deviceId: 'b')));
    final local = s.outline.origins!.of('o1')!;
    expect(local.deleted, isTrue);
    expect(local.origin, isNull, reason: 'it keeps no content');
    // Elsewhere that tombstone met the content and brought it back (its
    // version + 1): here nothing comes back but that copy.
    await pull(entry(local.version.updatedAt + 1, 'c', base: (updatedAt: 100, deviceId: 'b')));
    final row = s.database.db.select('SELECT * FROM outline WHERE id = ?', ['o1']).single;
    expect((row['deleted'], row['notebook_id'], row['device_id']), (0, 'nb', 'c'));
  });

  test('imports are stamped by the app\'s clock', () async {
    final clock = _StillClock(5000);
    final s = _services(clock: clock);
    addTearDown(s.dispose);
    s.notebooks.create(
      title: 'Diary',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final out = OutputMemoryStream();
    await s.lenFiles.write(const LenScope.library(), out);
    clock.now = 6000;
    final result = await s.lenFiles.import(
      await s.lenFiles.open(InputMemoryStream(out.getBytes())),
    );
    expect(s.notebooks.get(result.notebooks.single)!.updatedAt, 6000);
  });
}
