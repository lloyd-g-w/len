import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/deletion_conflicts.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/surface_element.dart';

import 'package:len/sync/remote_changes.dart';
import 'package:len/sync/revival_notice.dart';

import 'support/fake_server.dart';
import 'support/two_devices.dart';

// Deletions racing edits on another device (docs/SYNC_PROTOCOL.md,
// "Deletion conflicts"): nothing is silently lost.

Notebook _notebook(TestDevice d, {NotebookKind kind = NotebookKind.paged, String? folderId}) => d
    .s
    .notebooks
    .create(title: 'Notes', kind: kind, paper: PaperStyle.blank, coverColor: 0, folderId: folderId);

/// Writes stroke [id] on [surface] of [notebook], as the editor does.
void _write(TestDevice d, String notebook, String surface, String id) {
  d.s.strokes.save([bigStroke(id, surface, 3)]);
  d.s.notebooks.touch(notebook);
}

List<String> _ink(TestDevice d, String surface) =>
    [for (final s in SurfaceCopier(d.s.strokes).loadAll(surface)) s.id]..sort();

List<String> _pages(TestDevice d, String notebook) => [
  for (final p in d.s.pages.pagesOf(notebook)) p.id,
];

/// The handwriting [d] knows was recognised on [surface].
Map<String, String>? _read(TestDevice d, String surface) =>
    d.s.recognition.indexer.shared.read(surface)?.lines;

List<String> _trash(TestDevice d) => [for (final n in d.s.notebooks.trashed()) n.id];
List<String> _library(TestDevice d) => [for (final n in d.s.notebooks.list()) n.id];

/// Syncs until both devices have pushed and pulled everything.
Future<void> _settle(TestDevice a, TestDevice b) async {
  for (var i = 0; i < 2; i++) {
    await b.sync();
    await a.sync();
  }
  await b.sync();
  expect(a.dirty, isEmpty);
  expect(b.dirty, isEmpty);
}

void main() {
  for (final editLast in [false, true]) {
    final order = editLast ? 'after' : 'before';
    group('an edit made $order the deletion', () {
      test('a notebook deleted forever while another device wrote in it comes back into '
          'the trash with everything', () async {
        final (a, b) = twoDevices();
        final nb = _notebook(a);
        final p1 = a.s.pages.pagesOf(nb.id).single;
        final p2 = a.s.pages.addPage(nb.id, after: p1);
        _write(a, nb.id, p1.id, 'old1');
        _write(a, nb.id, p2.id, 'old2');
        a.s.elements.save([_text('words', p2.id)]);
        final entry = a.s.outline.add(notebookId: nb.id, pageId: p2.id, title: 'Two');
        await send(a, b);

        Future<void> deleteOnA() async {
          a.time.tick();
          a.s.notebooks.trash(nb.id);
          a.s.notebooks.delete(nb.id);
        }

        if (!editLast) _write(b, nb.id, p1.id, 'new'); // B is offline.
        await deleteOnA();
        if (editLast) {
          a.time.tick();
          _write(b, nb.id, p1.id, 'new');
        }
        await a.sync();
        await _settle(a, b);

        for (final d in [a, b]) {
          expect(_trash(d), [nb.id], reason: d.clock.prefix);
          expect(_library(d), isEmpty);
          expect(_pages(d, nb.id), [p1.id, p2.id]);
          expect(_ink(d, p1.id), ['new', 'old1']);
          expect(_ink(d, p2.id), ['old2']);
          expect(SurfaceCopier(d.s.strokes, elements: d.s.elements).loadAllElements(p2.id), [
            isA<SurfaceElement>().having((e) => e.id, 'id', 'words'),
          ]);
          expect(d.s.outline.entriesOf(nb.id).map((e) => e.id), [entry.id]);
        }
        expect(a.server.stored('notebooks', nb.id)!['deleted'], isFalse);

        // It can be deleted forever again, for good.
        a.s.notebooks.delete(nb.id);
        await _settle(a, b);
        expect(_trash(b), isEmpty);
        expect(_ink(b, p1.id), isEmpty);
      });

      test('a canvas deleted forever while another device wrote on it', () async {
        final (a, b) = twoDevices();
        final nb = _notebook(a, kind: NotebookKind.canvas);
        _write(a, nb.id, nb.id, 'old');
        await send(a, b);

        if (!editLast) _write(b, nb.id, nb.id, 'new');
        a.time.tick();
        a.s.notebooks.trash(nb.id);
        a.s.notebooks.delete(nb.id);
        if (editLast) {
          a.time.tick();
          _write(b, nb.id, nb.id, 'new');
        }
        await a.sync();
        await _settle(a, b);

        for (final d in [a, b]) {
          expect(_trash(d), [nb.id]);
          expect(_ink(d, nb.id), ['new', 'old']);
        }
      });
    });
  }

  test('a deleted page another device wrote on comes back into its notebook', () async {
    final (a, b) = twoDevices();
    final nb = _notebook(a);
    final p1 = a.s.pages.pagesOf(nb.id).single;
    final p2 = a.s.pages.addPage(nb.id, after: p1);
    final p3 = a.s.pages.addPage(nb.id, after: p2);
    _write(a, nb.id, p2.id, 'old2');
    _write(a, nb.id, p3.id, 'old3');
    for (final page in [p2, p3]) {
      a.s.recognition.indexer.shared.write(page.id, 'en-US', {'line': 'words'});
    }
    await send(a, b);

    _write(b, nb.id, p2.id, 'new2'); // Offline.
    a.time.tick();
    a.s.notebooks.deletePage(p2.id);
    a.s.notebooks.deletePage(p3.id); // Nobody wrote here: stays deleted.
    await a.sync();
    await _settle(a, b);

    for (final d in [a, b]) {
      expect(_library(d), [nb.id], reason: 'the notebook stays where it is');
      expect(_pages(d, nb.id), [p1.id, p2.id]);
      expect(_ink(d, p2.id), ['new2', 'old2']);
      expect(_ink(d, p3.id), isEmpty);
      expect(_read(d, p2.id), {'line': 'words'});
      expect(_read(d, p3.id), isNull);
    }
  });

  test('the device that deleted is told what came back, the other says nothing (R16-6)', () async {
    final (a, b) = twoDevices();
    final nb = _notebook(a);
    final gone = a.s.notebooks.create(
      title: 'Lab book',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final p1 = a.s.pages.pagesOf(nb.id).single;
    final p2 = a.s.pages.addPage(nb.id, after: p1);
    final p3 = a.s.pages.addPage(nb.id, after: p2);
    _write(a, gone.id, a.s.pages.pagesOf(gone.id).single.id, 'lab');
    await send(a, b);

    _write(b, nb.id, p2.id, 'new2'); // Offline.
    _write(b, nb.id, p3.id, 'new3');
    _write(b, gone.id, b.s.pages.pagesOf(gone.id).single.id, 'lab2');
    a.time.tick();
    a.s.notebooks.deletePage(p2.id);
    a.s.notebooks.deletePage(p3.id);
    a.s.notebooks.trash(gone.id);
    a.s.notebooks.delete(gone.id);
    final onA = RemoteChanges(), onB = RemoteChanges();
    onA.addAll(await a.sync());
    for (var i = 0; i < 2; i++) {
      onB.addAll(await b.sync());
      onA.addAll(await a.sync());
    }
    String? title(TestDevice d, String id) => d.s.notebooks.get(id)?.title;
    expect(revivalNotices(onA, (id) => title(a, id)), [
      '“Lab book” is back in the trash: another device wrote in it after you deleted it',
      '2 pages you deleted in “Notes” are back: another device wrote on them',
    ]);
    expect(revivalNotices(onB, (id) => title(b, id)), isEmpty);
  });

  test('a revival is told once a pull failing after it is retried (R9b-9)', () async {
    final (a, b) = twoDevices();
    final gone = _notebook(a);
    final page = a.s.pages.pagesOf(gone.id).single.id;
    final other = _notebook(a);
    await send(a, b);
    a.time.tick();
    a.s.notebooks.trash(gone.id);
    a.s.notebooks.delete(gone.id);
    await a.sync();

    // B, offline since, writes in the notebook after it was deleted.
    _write(b, gone.id, page, 'first');
    await b.s.sync.engine.sync(apiFor(b.server));
    b.s.strokes.save([
      for (var i = 0; i < 100; i++) bigStroke('s$i', page, 4),
      bigStroke('late', other.id, 4),
    ]);
    await b.s.sync.engine.sync(apiFor(b.server));

    // A's pull revives the notebook in an early slice, then fails.
    a.db
      ..execute('''
        CREATE TRIGGER test_slow AFTER INSERT ON strokes BEGIN
          SELECT COUNT(*) FROM (WITH RECURSIVE c(x) AS
            (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 20000) SELECT x FROM c);
        END''')
      ..execute('''
        CREATE TRIGGER test_fail BEFORE INSERT ON strokes WHEN NEW.id = 'late' BEGIN
          SELECT RAISE(ABORT, 'disk on fire');
        END''');
    await expectLater(a.s.sync.engine.sync(apiFor(a.server)), throwsA(isA<Exception>()));
    expect(_trash(a), [gone.id], reason: 'the revival was committed');
    a.db
      ..execute('DROP TRIGGER test_slow')
      ..execute('DROP TRIGGER test_fail');

    final changes = await a.sync();
    expect(revivalNotices(changes, (id) => a.s.notebooks.get(id)?.title), [
      '“Notes” is back in the trash: another device wrote in it after you deleted it',
    ]);
  });

  test('revival notices count each page once, however often it is reported', () {
    final revival = Revival()
      ..notebooks.add('n1')
      ..undonePages['n1'] = {'p1', 'p2'};
    final changes = RemoteChanges()
      ..addRevival(revival)
      ..addRevival(revival); // A slice applied again after a database retry.
    final again = RemoteChanges()..addRevival(revival);
    changes.addAll(again); // A pull announced again after a failure.
    expect(revivalNotices(changes, (_) => 'Notes'), [
      '2 pages you deleted in “Notes” are back: another device wrote on them',
    ]);
  });

  test('revival notices count pages across notebooks and several notebooks', () {
    final changes = RemoteChanges()
      ..undoneNotebooks.addAll(['n1', 'n2'])
      ..undonePages.addAll({
        'n1': {'a', 'b'},
        'n3': {'c'},
        'n4': {'d'},
      });
    expect(revivalNotices(changes, (_) => 'X'), [
      '2 notebooks you deleted are back in the trash: another device wrote in them',
      '2 pages you deleted are back: another device wrote on them',
    ]);
    final one = RemoteChanges()..undonePages['n1'] = {'a'};
    expect(revivalNotices(one, (_) => null), [
      'A page you deleted is back: another device wrote on it',
    ]);
  });

  test('deletions without edits elsewhere stay deleted', () async {
    final (a, b) = twoDevices();
    final kept = _notebook(a), gone = _notebook(a);
    final p1 = a.s.pages.pagesOf(kept.id).single;
    final p2 = a.s.pages.addPage(kept.id, after: p1);
    _write(a, kept.id, p2.id, 'ink');
    final gonePage = a.s.pages.pagesOf(gone.id).single.id;
    _write(a, gone.id, gonePage, 'ink2');
    for (final page in [p2.id, gonePage]) {
      a.s.recognition.indexer.shared.write(page, 'en-US', {'line': 'words'});
    }
    await send(a, b);
    _write(b, kept.id, p1.id, 'elsewhere'); // Not in anything deleted.

    a.time.tick();
    a.s.notebooks.deletePage(p2.id);
    a.s.notebooks.delete(gone.id);
    await a.sync();
    final changes = await b.sync();

    expect(changes.revived, isFalse);
    expect(b.dirty, isEmpty);
    await _settle(a, b);
    for (final d in [a, b]) {
      expect(_library(d), [kept.id]);
      expect(_trash(d), isEmpty);
      expect(_pages(d, kept.id), [p1.id]);
      expect(_read(d, p2.id), isNull);
      expect(_read(d, gonePage), isNull);
    }
  });

  test('a notebook of a deleted folder comes back into the trash, restored to the root', () async {
    final (a, b) = twoDevices();
    final folder = a.s.folders.create(name: 'Old', color: 0);
    final nb = _notebook(a, folderId: folder.id);
    final page = a.s.pages.pagesOf(nb.id).single;
    await send(a, b);

    a.time.tick();
    a.s.notebooks.trashAllIn(a.s.folders.delete(folder.id));
    a.s.notebooks.emptyTrash();
    _write(b, nb.id, page.id, 'new'); // Offline, still in the folder there.
    await a.sync();
    await _settle(a, b);
    expect(_trash(a), [nb.id]);
    expect(_trash(b), [nb.id]);

    b.s.notebooks.restore(nb.id);
    await _settle(a, b);
    for (final d in [a, b]) {
      expect(d.s.folders.list(), isEmpty);
      expect(d.s.notebooks.get(nb.id)!.folderId, isNull);
      expect(_library(d), [nb.id]);
      expect(_ink(d, page.id), ['new']);
    }
  });

  test('revived images and recordings still have their blobs', () async {
    final (a, b) = twoDevices();
    final nb = _notebook(a);
    final page = a.s.pages.pagesOf(nb.id).single;
    final img = await a.s.blobs.putBytes(Uint8List.fromList([1, 2, 3]), mime: 'image/png');
    final audio = await a.s.blobs.putBytes(Uint8List.fromList([4, 5, 6]), mime: 'audio/mp4');
    a.s.elements.save([_image('photo', page.id, img)]);
    final rec = a.s.recordings.save(
      notebookId: nb.id,
      parts: [RecordingPart(audio, 1000)],
      mime: 'audio/mp4',
      title: 'R',
      segments: [const RecordingSegment(1, 1000)],
    );
    await send(a, b);

    a.s.notebooks.delete(nb.id);
    await a.sync();
    // A week later A collects unreferenced blobs; B has been offline.
    for (var day = 0; day < 9; day++) {
      a.time.tick(const Duration(days: 1).inMilliseconds);
      await a.s.blobGc.run();
    }
    _write(b, nb.id, page.id, 'new');
    await _settle(a, b);

    for (final d in [a, b]) {
      expect(_trash(d), [nb.id]);
      expect(d.s.recordings.listOf(nb.id).map((r) => r.id), [rec.id]);
      expect(SurfaceCopier(d.s.strokes, elements: d.s.elements).loadAllElements(page.id), [
        isA<SurfaceElement>().having((e) => e.id, 'id', 'photo'),
      ]);
    }
    // A's garbage collection kept them (B fetches them lazily).
    expect(await a.s.blobs.has(img), isTrue);
    expect(await a.s.blobs.has(audio), isTrue);
    expect(a.server.blobs.keys, containsAll([img, audio]));
  });

  test('a notebook in the trash that receives edits stays in the trash', () async {
    final (a, b) = twoDevices();
    final nb = _notebook(a);
    final page = a.s.pages.pagesOf(nb.id).single;
    await send(a, b);
    a.s.notebooks.delete(nb.id);
    _write(b, nb.id, page.id, 'one');
    await a.sync();
    await _settle(a, b);
    expect(_trash(a), [nb.id]);

    _write(b, nb.id, page.id, 'two');
    await _settle(a, b);
    expect(_trash(a), [nb.id]);
    expect(_ink(a, page.id), ['one', 'two']);
  });

  test('a deletion reaches the server content first, so no partial push looks like a race', () {
    final (a, _) = twoDevices();
    final nb = _notebook(a);
    final page = a.s.pages.pagesOf(nb.id).single;
    _write(a, nb.id, page.id, 'ink');
    return a.sync().then((_) async {
      a.s.notebooks.delete(nb.id);
      await a.sync();
      int seq(String collection, String id) => a.server.stored(collection, id)!['seq']! as int;
      expect(seq('strokes', 'ink'), lessThan(seq('pages', page.id)));
      expect(seq('pages', page.id), lessThan(seq('notebooks', nb.id)));
    });
  });
}

SurfaceElement _text(String id, String surface) => SurfaceElement(
  id: id,
  surfaceId: surface,
  type: 'text',
  rect: const Rect.fromLTWH(0, 0, 50, 20),
  z: 1,
  createdAt: 1,
  data: const {'text': 'words'},
);

SurfaceElement _image(String id, String surface, String sha) => SurfaceElement(
  id: id,
  surfaceId: surface,
  type: 'image',
  rect: const Rect.fromLTWH(0, 0, 10, 10),
  z: -1,
  createdAt: 1,
  data: ImageData(blob: sha, width: 1, height: 1).toJson(),
);
