import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/syncable.dart';
import 'package:len/data/tagging_repository.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/tag.dart';

import 'support/two_devices.dart';

void main() {
  late AppServices s;
  setUp(() {
    s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
  });

  Notebook paged(String title) => s.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
  );

  group('TagRepository', () {
    test('creates, finds by name, renames, lists by name', () {
      final work = s.tags.create(name: ' Work ', color: 1);
      final again = s.tags.create(name: 'work', color: 2);
      expect(again.id, work.id, reason: 'names are unique, ignoring case');
      expect(work.name, 'Work');
      s.tags.create(name: 'archive', color: 3);
      expect(s.tags.list().map((t) => t.name), ['archive', 'Work']);
      s.tags.update(work.copyWith(name: 'Job', color: 9));
      expect(s.tags.get(work.id)!.color, 9);
      expect(s.tags.byName('JOB')!.id, work.id);
    });

    test('tagging a notebook and its pages, setTags replaces', () {
      final a = s.tags.create(name: 'a', color: 1);
      final b = s.tags.create(name: 'b', color: 2);
      final n = paged('N');
      final g = s.tags.taggings;
      g.setTags(n.id, TagTarget.notebook, {a.id, b.id});
      expect(g.tagsOf(n.id), {a.id, b.id});
      g.setTags(n.id, TagTarget.notebook, {b.id});
      expect(g.tagsOf(n.id), {b.id});
      final page = s.pages.pagesOf(n.id).first;
      g.set(a.id, page.id, TagTarget.page, on: true);
      expect(g.all(TagTarget.page), {
        page.id: {a.id},
      });
      expect(g.all(TagTarget.notebook), {
        n.id: {b.id},
      });
    });

    test('deleting a tag takes it off everything', () {
      final a = s.tags.create(name: 'a', color: 1);
      final n = paged('N');
      s.tags.taggings.set(a.id, n.id, TagTarget.notebook, on: true);
      s.tags.delete(a.id);
      expect(s.tags.list(), isEmpty);
      expect(s.tags.taggings.tagsOf(n.id), isEmpty);
      final rows = s.database.db.select('SELECT deleted FROM taggings');
      expect(rows.single['deleted'], 1);
    });

    test('deleting a notebook forever removes its tags; duplicating copies them', () {
      final a = s.tags.create(name: 'a', color: 1);
      final n = paged('N');
      final page = s.pages.pagesOf(n.id).first;
      s.tags.taggings.set(a.id, n.id, TagTarget.notebook, on: true);
      s.tags.taggings.set(a.id, page.id, TagTarget.page, on: true);
      final copy = s.notebooks.duplicate(n.id)!;
      expect(s.tags.taggings.tagsOf(copy.id), {a.id});
      final copyPage = s.pages.pagesOf(copy.id).first;
      expect(s.tags.taggings.tagsOf(copyPage.id), {a.id});
      s.notebooks.delete(n.id);
      expect(s.tags.taggings.tagsOf(n.id), isEmpty);
      expect(s.tags.taggings.tagsOf(page.id), isEmpty);
      expect(s.tags.taggings.tagsOf(copy.id), {a.id});
    });

    test('tagging ids are deterministic per tag and target', () {
      expect(TaggingRepository.idOf('t', 'n'), TaggingRepository.idOf('t', 'n'));
      expect(TaggingRepository.idOf('t', 'n'), isNot(TaggingRepository.idOf('t', 'm')));
      expect(TaggingRepository.idOf('t', 'n').length, lessThanOrEqualTo(64));
    });
  });

  group('tags sync', () {
    test('tags and taggings round-trip between devices', () async {
      final (a, b) = twoDevices();
      final tag = a.s.tags.create(name: 'Work', color: 0xFF3B5BDB);
      final n = a.s.notebooks.create(
        title: 'N',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      a.s.tags.taggings.set(tag.id, n.id, TagTarget.notebook, on: true);
      await a.sync();
      final changes = await b.sync();
      expect(changes.tags, isTrue);
      expect(b.s.tags.list(), [tag]);
      expect(b.s.tags.taggings.tagsOf(n.id), {tag.id});
      expect(a.dirty, isEmpty);

      // Untag on b, rename on a: both survive.
      b.s.tags.taggings.set(tag.id, n.id, TagTarget.notebook, on: false);
      a.s.tags.update(tag.copyWith(name: 'Job'));
      await send(b, a);
      await send(a, b);
      for (final d in [a, b]) {
        expect(d.s.tags.get(tag.id)!.name, 'Job');
        expect(d.s.tags.taggings.tagsOf(n.id), isEmpty);
      }
    });

    test('the same tag added on two devices converges on one record', () async {
      final (a, b) = twoDevices();
      final tag = a.s.tags.create(name: 'x', color: 1);
      await send(a, b);
      a.s.tags.taggings.set(tag.id, 'n1', TagTarget.notebook, on: true);
      b.s.tags.taggings.set(tag.id, 'n1', TagTarget.notebook, on: true);
      await send(a, b);
      await a.sync();
      for (final d in [a, b]) {
        expect(d.db.select('SELECT * FROM taggings').length, 1);
        expect(d.s.tags.taggings.tagsOf('n1'), {tag.id});
      }
    });

    test('malformed records are skipped', () {
      SyncRecord record(String collection, String id, Map<String, Object?> data) => SyncRecord(
        collection: collection,
        id: id,
        updatedAt: 5,
        deviceId: 'x',
        deleted: false,
        data: data,
      );
      expect(
        () => s.tags.applyRemote(record('tags', 't', {'name': '', 'color': 1, 'createdAt': 1})),
        throwsFormatException,
      );
      expect(
        () => s.tags.applyRemote(record('tags', 't', {'name': 'x', 'createdAt': 1})),
        throwsFormatException,
      );
      expect(
        () => s.tags.taggings.applyRemote(
          record('taggings', 'wrong-id', {'tagId': 't', 'targetId': 'n', 'kind': 'notebook'}),
        ),
        throwsFormatException,
      );
      final id = TaggingRepository.idOf('t', 'n');
      expect(
        () => s.tags.taggings.applyRemote(
          record('taggings', id, {'tagId': 't', 'targetId': 'n', 'kind': 'folder'}),
        ),
        throwsFormatException,
      );
      expect(
        s.tags.taggings.applyRemote(
          record('taggings', id, {'tagId': 't', 'targetId': 'n', 'kind': 'page'}),
        ),
        isTrue,
      );
    });
  });
}
