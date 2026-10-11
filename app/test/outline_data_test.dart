import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/outline/outline_entry.dart';
import 'package:len/domain/outline/outline_tree.dart';
import 'package:len/domain/paper.dart';

import 'support/two_devices.dart';

OutlineEntry _e(String id, String page, {String? parent, int at = 0}) =>
    OutlineEntry(id: id, notebookId: 'n', pageId: page, parentId: parent, title: id, createdAt: at);

void main() {
  group('OutlineTree', () {
    test('siblings follow page order, children nest, deleted pages last', () {
      final tree = OutlineTree(
        [
          _e('c', 'p3'),
          _e('a', 'p1'),
          _e('gone', 'px'),
          _e('a2', 'p2', parent: 'a'),
          _e('a1', 'p1', parent: 'a', at: 5),
        ],
        {'p1': 0, 'p2': 1, 'p3': 2},
      );
      expect(tree.rows().map((r) => '${'  ' * r.depth}${r.entry.id}:${r.page}').toList(), [
        'a:0',
        '  a1:0',
        '  a2:1',
        'c:2',
        'gone:null',
      ]);
      expect(tree.rows(collapsed: {'a'}).map((r) => r.entry.id), ['a', 'c', 'gone']);
      expect(tree.rows().first.hasChildren, isTrue);
    });

    test('orphans and cycles show at the top level', () {
      final tree = OutlineTree(
        [_e('x', 'p1', parent: 'y'), _e('y', 'p2', parent: 'x'), _e('o', 'p3', parent: 'missing')],
        {'p1': 0, 'p2': 1, 'p3': 2},
      );
      expect(tree.rows().map((r) => r.depth), [0, 0, 0]);
    });

    test('indent under the previous sibling, outdent to the grandparent', () {
      final entries = [_e('a', 'p1'), _e('b', 'p2'), _e('b1', 'p3', parent: 'b')];
      final tree = OutlineTree(entries, {'p1': 0, 'p2': 1, 'p3': 2});
      expect(tree.indentTarget(entries[0]), isNull);
      expect(tree.indentTarget(entries[1]), 'a');
      expect(tree.isNested(entries[2]), isTrue);
      expect(tree.outdentTarget(entries[2]), isNull);
      expect(tree.isNested(entries[1]), isFalse);
    });
  });

  group('OutlineRepository', () {
    late AppServices s;
    late Notebook n;
    setUp(() {
      s = AppServices.create(AppDatabase.inMemory());
      addTearDown(s.dispose);
      n = s.notebooks.create(
        title: 'N',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
    });

    test('add, rename, delete moves children up', () {
      final page = s.pages.pagesOf(n.id).first;
      final a = s.outline.add(notebookId: n.id, pageId: page.id, title: 'Chapter');
      final b = s.outline.add(notebookId: n.id, pageId: page.id, title: 'Part', parentId: a.id);
      s.outline.update(a.copyWith(title: 'Chapter 1'));
      expect(s.outline.get(a.id)!.title, 'Chapter 1');
      s.outline.delete(a.id);
      expect(s.outline.entriesOf(n.id), [b.copyWith(parentId: null)]);
    });

    test('duplicating a notebook copies its outline onto the copied pages', () {
      final page = s.pages.pagesOf(n.id).first;
      final a = s.outline.add(notebookId: n.id, pageId: page.id, title: 'A');
      s.outline.add(notebookId: n.id, pageId: page.id, title: 'B', parentId: a.id);
      final copy = s.notebooks.duplicate(n.id)!;
      final copyPage = s.pages.pagesOf(copy.id).first;
      final copied = s.outline.entriesOf(copy.id);
      expect(copied.map((e) => e.pageId).toSet(), {copyPage.id});
      final copiedA = copied.firstWhere((e) => e.title == 'A');
      expect(copied.firstWhere((e) => e.title == 'B').parentId, copiedA.id);
      s.notebooks.delete(n.id);
      expect(s.outline.entriesOf(n.id), isEmpty);
      expect(s.outline.entriesOf(copy.id), hasLength(2));
    });

    test('malformed records are skipped', () {
      SyncRecord record(Map<String, Object?> data) => SyncRecord(
        collection: 'outline',
        id: 'o',
        updatedAt: 5,
        deviceId: 'x',
        deleted: false,
        data: data,
      );
      final good = {
        'notebookId': 'n',
        'pageId': 'p',
        'parentId': null,
        'title': 't',
        'createdAt': 1,
      };
      expect(
        () => s.outline.applyRemote(record({...good}..remove('parentId'))),
        throwsFormatException,
      );
      expect(() => s.outline.applyRemote(record({...good, 'pageId': ''})), throwsFormatException);
      expect(s.outline.applyRemote(record(good)), isTrue);
    });
  });

  test('outline entries round-trip between devices', () async {
    final (a, b) = twoDevices();
    final n = a.s.notebooks.create(
      title: 'N',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = a.s.pages.pagesOf(n.id).first;
    final entry = a.s.outline.add(notebookId: n.id, pageId: page.id, title: 'Intro');
    await a.sync();
    final changes = await b.sync();
    expect(changes.outlineOfNotebooks, {n.id});
    expect(b.s.outline.entriesOf(n.id), [entry]);
    b.s.outline.delete(entry.id);
    await send(b, a);
    expect(a.s.outline.entriesOf(n.id), isEmpty);
  });
}
