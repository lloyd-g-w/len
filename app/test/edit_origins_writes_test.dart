import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/cancellation.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';

// Write paths around the origin and base of rows edited in place
// (`EditOrigins`; docs/SYNC_PROTOCOL.md, "Deletion conflicts"): what a
// tombstone says its deletion knew must stay what that deletion knew.

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

/// The origin and base columns of row [id] of [table], with its version.
Map<String, Object?> _bookkeeping(AppServices s, String table, String id) => {
  ...s.database.db.select(
    'SELECT updated_at, device_id, deleted, base_at, base_device, origin_at, '
    'origin_device, origin_for FROM $table WHERE id = ?',
    [id],
  ).single,
};

void main() {
  test('a cancelled restore leaves the tombstones of a notebook deleted here knowing what the '
      'deletion knew, not the restore', () async {
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
    s.notebooks.delete(nb.id); // Deleted forever since the backup.
    final before = [_bookkeeping(s, 'elements', 'box'), _bookkeeping(s, 'outline', entry.id)];
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
    final after = [_bookkeeping(s, 'elements', 'box'), _bookkeeping(s, 'outline', entry.id)];
    for (final (i, row) in after.indexed) {
      expect(row['deleted'], 1);
      expect(
        (row['updated_at'], row['device_id']),
        (before[i]['updated_at'], before[i]['device_id']),
      );
      // What the deletion knew, or nothing (unknown); never the restore's own
      // version, later than every edit it never saw.
      if (row['base_at'] != null) {
        expect(
          (row['base_at'], row['base_device']),
          (before[i]['base_at'], before[i]['base_device']),
        );
      }
    }
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
}
