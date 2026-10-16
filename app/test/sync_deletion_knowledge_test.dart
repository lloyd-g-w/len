import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/sync/pull_applier.dart';

import 'support/fake_server.dart';
import 'support/two_devices.dart';

// Which edit a row's content comes from and what a deletion knew decide the
// races of rows edited in place (docs/SYNC_PROTOCOL.md, "Deletion
// conflicts"): copies brought back carry the origin of their content,
// tombstones what they replaced. So an edit no deletion knew survives a page
// brought back elsewhere first, a page comes back with the newest content
// any device kept, and a deletion that knew an edit is not undone by it
// however often the edit is pulled or pushed again.

typedef _Page = ({String notebook, String page});

/// A notebook made on [d] whose page holds text box `box` and stroke `ink`.
_Page _pageWithBox(TestDevice d) {
  final nb = d.s.notebooks.create(
    title: 'Notes',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
  );
  final page = d.s.pages.pagesOf(nb.id).single.id;
  d.s.elements.save([_text(page, 'words')]);
  _write(d, (notebook: nb.id, page: page), 'ink');
  return (notebook: nb.id, page: page);
}

void _write(TestDevice d, _Page at, String id) {
  d.s.strokes.save([bigStroke(id, at.page, 3)]);
  d.s.notebooks.touch(at.notebook);
}

void _editBox(TestDevice d, _Page at, String text) => d.s.elements.save([_text(at.page, text)]);

SurfaceElement _text(String surface, String text) => SurfaceElement(
  id: 'box',
  surfaceId: surface,
  type: 'text',
  rect: const Rect.fromLTWH(0, 0, 50, 20),
  z: 1,
  createdAt: 1,
  data: TextData(text: text).toJson(),
);

List<String> _pages(TestDevice d, _Page at) => [
  for (final p in d.s.pages.pagesOf(at.notebook)) p.id,
];

List<String> _ink(TestDevice d, _Page at) =>
    [for (final s in SurfaceCopier(d.s.strokes).loadAll(at.page)) s.id]..sort();

/// The text of the live box on the page, or null.
String? _box(TestDevice d, _Page at) {
  final boxes = SurfaceCopier(d.s.strokes, elements: d.s.elements).loadAllElements(at.page);
  return boxes.isEmpty ? null : boxes.single.data['text'] as String;
}

/// Syncs every device in turn until they agree, with nothing left to push.
Future<void> _settle(List<TestDevice> devices) async {
  for (var round = 0; round < 3; round++) {
    for (final d in devices) {
      await d.sync();
    }
  }
  for (final d in devices) {
    expect(d.dirty, isEmpty, reason: d.clock.prefix);
  }
}

void main() {
  test('an edit made before a deletion survives a third device bringing the page back '
      'first', () async {
    final (a, b) = twoDevices();
    final c = TestDevice(a.server, a.time, 'c');
    final at = _pageWithBox(a);
    for (final d in [a, b, c]) {
      await d.sync();
    }

    // A edits the box offline; then B deletes the page, unaware of it.
    a.time.tick();
    _editBox(a, at, 'edited');
    a.time.tick();
    b.s.notebooks.deletePage(at.page);
    await b.sync();
    // C wrote on the page meanwhile, so it brings it back (with the box as
    // it knew it) before A syncs.
    _write(c, at, 'more');
    await c.sync();
    expect(_box(c, at), 'words');
    await a.sync();
    await _settle([a, b, c]);

    for (final d in [a, b, c]) {
      expect(_pages(d, at), [at.page], reason: d.clock.prefix);
      expect(_ink(d, at), ['ink', 'more']);
      expect(_box(d, at), 'edited', reason: d.clock.prefix);
    }
  });

  test('a page brought back holds the newest content a device kept of it', () async {
    final (a, b) = twoDevices();
    final c = TestDevice(a.server, a.time, 'c');
    final at = _pageWithBox(a);
    for (final d in [a, b, c]) {
      await d.sync();
    }

    // B edits the box and deletes the page before syncing: nobody else
    // ever sees the edit. C, which wrote on the page, brings it back with
    // the box as it knew it.
    b.time.tick();
    _editBox(b, at, 'newer');
    b.time.tick();
    b.s.notebooks.deletePage(at.page);
    _write(c, at, 'more');
    await b.sync();
    await c.sync();
    expect(_box(c, at), 'words');
    await _settle([a, b, c]);

    for (final d in [a, b, c]) {
      expect(_pages(d, at), [at.page], reason: d.clock.prefix);
      expect(_box(d, at), 'newer', reason: d.clock.prefix);
    }
  });

  test('a deletion that knew an edit whose push was never confirmed stays', () async {
    final (a, b) = twoDevices();
    final at = _pageWithBox(a);
    await send(a, b);

    // A's push of the edit reaches the server, but A never hears so (the
    // answer is lost, or A is killed): the edit stays unpushed there.
    a.time.tick();
    _editBox(a, at, 'edited');
    a.server.losePushAnswers = 1;
    await expectLater(a.sync(), throwsA(anything));
    expect(a.dirty.map((r) => r.id), ['box']);
    // B sees the edit, then deletes the page.
    await b.sync();
    expect(_box(b, at), 'edited');
    a.time.tick();
    b.s.notebooks.deletePage(at.page);
    await b.sync();
    await _settle([a, b]);

    for (final d in [a, b]) {
      expect(_pages(d, at), isEmpty, reason: d.clock.prefix);
      expect(_box(d, at), isNull, reason: d.clock.prefix);
    }
  });

  test('a deletion made between two pulls of the same page stays', () async {
    final (a, b) = twoDevices();
    final at = _pageWithBox(a);
    final other = a.s.pages.addPage(at.notebook, after: a.s.pages.get(at.page)!).id;
    await send(a, b);

    // B edits the box, then writes on another page: one page of the feed.
    b.time.tick();
    _editBox(b, at, 'edited');
    await b.sync();
    for (var i = 0; i < 5; i++) {
      b.s.strokes.save([bigStroke('elsewhere$i', other, 3)]);
    }
    await b.sync();
    // A's pull stops once it holds the edit, before the page is complete:
    // the page will be pulled again.
    PullApplier.debugSliceRecords = 1;
    addTearDown(() => PullApplier.debugSliceRecords = null);
    final start = a.s.settings.syncLastSeq;
    await a.s.sync.engine.sync(apiFor(a.server), isCancelled: () => _box(a, at) == 'edited');
    expect(a.s.settings.syncLastSeq, start);
    PullApplier.debugSliceRecords = null;
    // Knowing the edit, A deletes the page; its next pull brings the edit
    // again.
    a.time.tick();
    a.s.notebooks.deletePage(at.page);
    await a.sync();
    await _settle([a, b]);

    for (final d in [a, b]) {
      expect(_pages(d, at), [other], reason: d.clock.prefix);
      expect(_box(d, at), isNull, reason: d.clock.prefix);
    }
  });

  test('a copy brought back but never pushed is no edit: deleting the page again '
      'holds', () async {
    final (a, b) = twoDevices();
    final c = TestDevice(a.server, a.time, 'c');
    final at = _pageWithBox(a);
    for (final d in [a, b, c]) {
      await d.sync();
    }

    // B deletes the page; C, which wrote on it offline, brings it back but
    // is killed before pushing what it brought back.
    _write(c, at, 'more');
    a.time.tick();
    b.s.notebooks.deletePage(at.page);
    await b.sync();
    bool revived() => c.db.select(
      "SELECT 1 FROM elements WHERE id = 'box' AND deleted = 0 AND device_id = ?",
      [c.s.elements.deviceId],
    ).isNotEmpty;
    await c.s.sync.engine.sync(apiFor(c.server), isCancelled: revived);
    expect(c.dirty.map((r) => r.id), contains('box'));
    // B brings the page back too (C's ink), and deletes it again, now
    // knowing all of it.
    await b.sync();
    expect(_box(b, at), 'words');
    a.time.tick();
    b.s.notebooks.deletePage(at.page);
    await b.sync();
    await _settle([a, b, c]);

    for (final d in [a, b, c]) {
      expect(_pages(d, at), isEmpty, reason: d.clock.prefix);
      expect(_box(d, at), isNull, reason: d.clock.prefix);
      expect(_ink(d, at), isEmpty, reason: d.clock.prefix);
    }
  });

  test('tombstones carry what they replaced; copies brought back the origin of their '
      'content', () async {
    final (a, b) = twoDevices();
    final at = _pageWithBox(a);
    await send(a, b);
    final edited = a.server.stored('elements', 'box')!;

    a.time.tick();
    a.s.notebooks.deletePage(at.page);
    await a.sync();
    final tombstone = a.server.stored('elements', 'box')!;
    expect(tombstone['deleted'], isTrue);
    expect(tombstone['base'], {'updatedAt': edited['updatedAt'], 'deviceId': edited['deviceId']});

    _write(b, at, 'more'); // Without knowing the deletion: brings the page back.
    await b.sync();
    final revived = a.server.stored('elements', 'box')!;
    expect(revived['deleted'], isFalse);
    expect(revived['updatedAt'], (tombstone['updatedAt']! as int) + 1);
    expect(revived['base'], tombstone['base']);

    // Edited again, it is an ordinary edit.
    b.time.tick();
    _editBox(b, at, 'again');
    await b.sync();
    expect(a.server.stored('elements', 'box')!.containsKey('base'), isFalse);
  });
}
