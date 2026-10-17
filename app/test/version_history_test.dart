import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/data/versions/version_packs.dart';
import 'package:len/data/versions/version_policy.dart';
import 'package:len/data/versions/version_recorder.dart';
import 'package:len/data/versions/version_repository.dart';
import 'package:len/data/versions/versions.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/link_target.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/shapes/shape_builder.dart';

/// A clock tests move by hand; ids `v0`, `v1`, …
class _Clock extends Clock {
  int now = DateTime.utc(2026, 10, 1, 12).millisecondsSinceEpoch;
  int _ids = 0;

  void advance(Duration d) => now += d.inMilliseconds;

  @override
  int nowMs() => now;

  @override
  String newId() => 'v${_ids++}';
}

Stroke _ink(String id, String surface, {double x = 10, int createdAt = 0}) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF102030,
  width: 3,
  points: [StrokePoint(x, 10, 0.5), StrokePoint(x + 20, 30, 0.5)],
  createdAt: createdAt,
);

SurfaceElement _text(
  String id,
  String surface,
  String text, {
  Map<String, Object?> extra = const {},
}) => SurfaceElement(
  id: id,
  surfaceId: surface,
  type: 'text',
  rect: const Rect.fromLTWH(10, 10, 200, 40),
  z: 1,
  createdAt: 3,
  data: {
    ...TextData(text: text).toJson(),
    ...extra,
  },
);

void main() {
  late _Clock clock;
  late AppServices s;
  Versions versions() => s.versions;

  setUp(() {
    clock = _Clock();
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
  });
  tearDown(() => s.dispose());

  Notebook paged({int pages = 2}) {
    final n = s.notebooks.create(
      title: 'Lab',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 1,
    );
    for (var i = 1; i < pages; i++) {
      s.pages.addPage(n.id);
    }
    return n;
  }

  List<String> pageIds(Notebook n) => [for (final p in s.pages.pagesOf(n.id)) p.id];
  Set<String> strokesOn(String surface) => {
    for (final row in s.database.db.select(
      'SELECT id FROM strokes WHERE surface_id = ? AND deleted = 0',
      [surface],
    ))
      row['id'] as String,
  };

  group('packs', () {
    test('cut where ids say, so an edit in the middle changes one or two packs', () {
      final items = [
        for (var i = 0; i < 300; i++) ('s$i', <String, Object?>{'n': i}),
      ];
      final before = VersionPacks.cut(items);
      expect(before.length, greaterThan(3));
      expect(before.expand((p) => p).length, 300);
      expect(before.every((p) => p.length <= VersionPacks.maxItems), isTrue);
      final after = VersionPacks.cut([...items]..removeAt(150));
      final encoded = {for (final p in before) base64Encode(VersionPacks.encode(p))};
      final changed = [
        for (final p in after)
          if (!encoded.contains(base64Encode(VersionPacks.encode(p)))) p,
      ];
      expect(changed.length, lessThanOrEqualTo(2));
      // Writing at the end changes only the last pack.
      final more = VersionPacks.cut([
        ...items,
        ('s300', <String, Object?>{'n': 300}),
      ]);
      expect(
        [for (final p in more.take(before.length - 1)) base64Encode(VersionPacks.encode(p))],
        [for (final p in before.take(before.length - 1)) base64Encode(VersionPacks.encode(p))],
      );
    });

    test('decode reads what encode wrote and refuses other formats', () {
      final items = [
        ('a', <String, Object?>{'x': 1}),
      ];
      final decoded = VersionPacks.decode(VersionPacks.encode(items))!;
      expect(decoded.single.$1, 'a');
      expect(decoded.single.$2, {'x': 1});
      expect(VersionPacks.decode(Uint8List.fromList(utf8.encode('{"v": 2, "items": []}'))), isNull);
      expect(VersionPacks.decode(Uint8List.fromList([0xff, 0x00])), isNull);
    });
  });

  group('snapshots', () {
    test('unchanged content is shared between versions; nothing new makes none', () async {
      final n = paged();
      final [first, second] = pageIds(n);
      s.strokes.save([for (var i = 0; i < 40; i++) _ink('a$i', first, createdAt: i)]);
      s.strokes.save([_ink('b0', second)]);
      final v1 = (await versions().record(n.id))!;
      expect(v1.pages, hasLength(2));
      expect(v1.summary.pagesAdded, 2);
      expect(v1.summary.strokes, 41);
      expect(v1.kind, VersionKind.auto);
      expect(v1.deviceId, s.strokes.deviceId);

      clock.advance(const Duration(minutes: 5));
      expect(await versions().record(n.id), isNull, reason: 'nothing changed');

      s.strokes.save([_ink('b1', second, createdAt: 9)]);
      final v2 = (await versions().record(n.id))!;
      expect(v2.pages[0].content, v1.pages[0].content, reason: 'the same packs');
      expect(v2.pages[1].content, isNot(v1.pages[1].content));
      expect(v2.summary.pagesEdited, 1);
      expect(v2.summary.strokesAdded, 1);
      expect(v2.summary.strokesRemoved, 0);
      expect(v2.summary.focus, second);
      expect(v2.size, lessThan(v1.size));
      expect(versions().of(n.id).map((v) => v.id), [v2.id, v1.id]);
    });

    test('a named version is saved even when nothing changed', () async {
      final n = paged(pages: 1);
      await versions().record(n.id);
      final named = (await versions().save(n.id, name: ' Before the exam '))!;
      expect(named.kind, VersionKind.named);
      expect(named.name, 'Before the exam');
      versions().rename(named.id, 'Exam');
      expect(s.versions.store.get(named.id)!.name, 'Exam');
    });

    test('a canvas is one surface', () async {
      final n = s.notebooks.create(
        title: 'Board',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 1,
      );
      s.strokes.save([_ink('c0', n.id), _ink('c1', n.id, x: 400)]);
      final v = (await versions().record(n.id))!;
      expect(v.pages, isEmpty);
      expect(v.canvas, isNotNull);
      expect(v.summary.strokesAdded, 2);
      final content = await versions().content.load(v.canvas!, n.id);
      expect({for (final st in content.strokes) st.id}, {'c0', 'c1'});
    });

    test('the record reads back as written', () async {
      final n = paged();
      s.elements.save([_text('t0', pageIds(n).first, 'hello')]);
      final v = (await versions().record(n.id))!;
      final record = s.versions.store.dirtyRecords(10).single;
      expect(record.collection, 'versions');
      final round = s.versions.store.get(v.id)!;
      expect(round.contentKey, v.contentKey);
      expect(jsonEncode(record.data), jsonEncode(v.toData()));
    });
  });

  group('thinning', () {
    VersionInfo info(String id, int at, [VersionKind kind = VersionKind.auto, int size = 1]) =>
        (id: id, createdAt: at, kind: kind, size: size);
    const hour = 3600 * 1000;
    const day = 24 * hour;

    test('all of the last day, hourly for a week, daily for a month, then weekly', () {
      final now = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
      // One every 20 minutes for 60 days.
      final all = [for (var t = now - 60 * day; t <= now; t += 20 * 60 * 1000) info('$t', t)];
      final remove = VersionPolicy.toRemove(all, now, maxVersions: 100000, maxBytes: 1 << 40);
      final kept = [
        for (final v in all)
          if (!remove.contains(v.id)) v.createdAt,
      ];
      int count(int from, int to) => kept.where((t) => now - t >= from && now - t < to).length;
      expect(count(0, day), 72, reason: 'every one of the last day');
      expect(count(day, 7 * day), inInclusiveRange(6 * 24 - 1, 6 * 24 + 1));
      expect(count(7 * day, 30 * day), inInclusiveRange(22, 24));
      expect(count(30 * day, 61 * day), inInclusiveRange(4, 6));
    });

    test('named versions stay; the budget drops the oldest automatic ones', () {
      final now = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
      final all = [
        info('named', now - 300 * day, VersionKind.named),
        for (var i = 0; i < 10; i++) info('a$i', now - i * hour, VersionKind.auto, 10),
      ];
      expect(VersionPolicy.toRemove(all, now), isEmpty);
      expect(VersionPolicy.toRemove(all, now, maxVersions: 4), {
        'a4',
        'a5',
        'a6',
        'a7',
        'a8',
        'a9',
      });
      expect(VersionPolicy.toRemove(all, now, maxBytes: 35), {
        'a3',
        'a4',
        'a5',
        'a6',
        'a7',
        'a8',
        'a9',
      });
    });

    test('a later clock keeps a subset of what an earlier one kept', () {
      final start = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
      final all = [for (var t = start; t < start + 50 * day; t += 37 * 60 * 1000) info('$t', t)];
      Set<String> keptAt(int now) {
        final remove = VersionPolicy.toRemove(all, now, maxVersions: 1 << 30, maxBytes: 1 << 40);
        return {
          for (final v in all)
            if (!remove.contains(v.id)) v.id,
        };
      }

      var previous = keptAt(start + 50 * day);
      for (var now = start + 50 * day; now < start + 120 * day; now += 7 * hour) {
        final kept = keptAt(now);
        expect(previous.containsAll(kept), isTrue, reason: 'at $now');
        previous = kept;
      }
    });

    test('recording thins the notebook it made a version of', () async {
      final n = paged(pages: 1);
      final page = pageIds(n).single;
      for (var i = 0; i < 6; i++) {
        s.strokes.save([_ink('s$i', page, createdAt: i)]);
        await versions().record(n.id);
        clock.advance(const Duration(minutes: 10));
      }
      expect(versions().of(n.id), hasLength(6));
      clock.advance(const Duration(days: 2));
      s.strokes.save([_ink('late', page, createdAt: 99)]);
      await versions().record(n.id);
      // The six fall into one hour: its newest stays, with the new one.
      expect(versions().of(n.id), hasLength(2));
    });
  });

  group('restoring', () {
    test('the whole notebook, and back with the version saved before it', () async {
      final n = paged();
      final [first, second] = pageIds(n);
      s.strokes.save([_ink('a0', first), _ink('a1', first, x: 50)]);
      s.elements.save([_text('t0', second, 'old words')]);
      final v1 = (await versions().record(n.id))!;

      // Edits: a stroke erased and one written, the text changed, a page
      // deleted and one added, the notebook renamed.
      s.strokes.delete(['a1']);
      s.strokes.save([_ink('a2', first, x: 90)]);
      s.elements.save([_text('t0', second, 'new words')]);
      s.notebooks.deletePage(second);
      final added = s.pages.addPage(n.id);
      s.strokes.save([_ink('x0', added.id)]);
      s.notebooks.update(s.notebooks.get(n.id)!.copyWith(title: 'Renamed'));
      clock.advance(const Duration(minutes: 3));

      final done = await versions().restore(v1);
      expect(done.before, isNotNull);
      expect(done.before!.kind, VersionKind.restore);
      expect(pageIds(n), [first, second]);
      expect(strokesOn(first), {'a0', 'a1'});
      expect(strokesOn(added.id), isEmpty);
      expect(TextData.fromJson(s.elements.allOn(second).single.data).text, 'old words');
      expect(s.notebooks.get(n.id)!.title, 'Lab');
      // Restored as local edits, to sync.
      expect(s.sync.engine.hasDirtyRows(), isTrue);

      clock.advance(const Duration(minutes: 1));
      await versions().restore(done.before!);
      expect(pageIds(n), [first, added.id]);
      expect(strokesOn(first), {'a0', 'a2'});
      expect(strokesOn(added.id), {'x0'});
      expect(s.notebooks.get(n.id)!.title, 'Renamed');
    });

    test('one page, back where it was', () async {
      final n = paged(pages: 3);
      final [p1, p2, p3] = pageIds(n);
      s.strokes.save([_ink('m0', p2)]);
      final v1 = (await versions().record(n.id))!;
      s.notebooks.deletePage(p2);
      s.strokes.save([_ink('o0', p1)]);
      clock.advance(const Duration(minutes: 1));

      final done = await versions().restorePage(v1, p2);
      expect(done.surfaces, {p2});
      expect(pageIds(n), [p1, p2, p3]);
      expect(strokesOn(p2), {'m0'});
      expect(strokesOn(p1), {'o0'}, reason: 'the other pages are left as they are');
    });

    test('as a copy: new ids, its own links and flows', () async {
      final n = paged();
      final [first, second] = pageIds(n);
      s.strokes.save([_ink('a0', first)]);
      s.elements.save([
        SurfaceElement(
          id: 'link',
          surfaceId: first,
          type: 'link',
          rect: const Rect.fromLTWH(0, 0, 10, 10),
          z: -1,
          createdAt: 1,
          data: {'target': PageLinkTarget(notebookId: n.id, pageId: second).toJson()},
        ),
      ]);
      final v1 = (await versions().record(n.id))!;
      final copy = (await versions().copy(v1, title: 'Lab (1 Oct)'))!;
      expect(copy.id, isNot(n.id));
      expect(copy.title, 'Lab (1 Oct)');
      final pages = s.pages.pagesOf(copy.id);
      expect(pages, hasLength(2));
      expect(pages.map((p) => p.id), isNot(contains(first)));
      expect(strokesOn(pages.first.id), hasLength(1));
      expect(strokesOn(pages.first.id), isNot(contains('a0')));
      final link = s.elements.allOn(pages.first.id).single;
      expect(
        LinkTarget.fromJson(link.data['target']),
        isA<PageLinkTarget>()
            .having((t) => t.notebookId, 'notebook', copy.id)
            .having((t) => t.pageId, 'page', pages[1].id),
      );
      // The original is untouched.
      expect(strokesOn(first), {'a0'});
    });

    test('a copy keeps its connectors attached to its own shapes', () async {
      final n = paged(pages: 1);
      final page = pageIds(n).single;
      final box = ShapeBuilder.dragged(
        ShapeKind.rectangle,
        const Offset(300, 200),
        const Offset(400, 300),
      ).withOrigin('box');
      Stroke shape(String id, ShapeGeometry g) => Stroke(
        id: id,
        surfaceId: page,
        tool: InkTool.ballpoint,
        color: 0xFF1C7ED6,
        width: 2,
        points: ShapeBuilder.pointsOf(g),
        createdAt: 1,
        style: ShapeBuilder.styleFor(const StrokeStyle(unit: 1)),
        shape: g,
      );
      s.strokes.save([
        shape('box2', box),
        shape(
          'arrow',
          ShapeGeometry(ShapeKind.arrow, const [
            Offset(150, 250),
            Offset(300, 250),
          ], tip: const ShapeAttachment('box', 0.875)),
        ),
      ]);
      final v = (await versions().record(n.id))!;
      final copy = (await versions().copy(v, title: 'Copy'))!;
      final copied = SurfaceCopier(s.strokes).loadAll(s.pages.pagesOf(copy.id).single.id);
      final arrow = copied.firstWhere((x) => x.shape!.kind == ShapeKind.arrow);
      final rect = copied.firstWhere((x) => x.shape!.kind == ShapeKind.rectangle);
      expect(rect.shapeId, isNot('box'), reason: 'a shape of its own');
      expect(arrow.shape!.tip!.id, rect.shapeId);
    });

    test('a version whose packs are not here (offline) changes nothing', () async {
      final n = paged(pages: 1);
      final page = pageIds(n).single;
      s.strokes.save([_ink('a0', page)]);
      final v1 = (await versions().record(n.id))!;
      s.strokes.save([_ink('a1', page)]);
      for (final sha in v1.packs) {
        s.database.db.execute('DELETE FROM blobs WHERE sha256 = ?', [sha]);
        await s.blobs.backend.delete(sha);
      }
      await expectLater(versions().restore(v1), throwsA(isA<VersionUnavailable>()));
      expect(strokesOn(page), {'a0', 'a1'});
      expect(versions().of(n.id), hasLength(1), reason: 'no version made before');
    });
  });

  group('garbage collection', () {
    test('keeps what live versions reference, packs and images, until deleted', () async {
      final n = paged(pages: 1);
      final page = pageIds(n).single;
      final image = await s.blobs.putBytes(Uint8List.fromList([1, 2, 3]), mime: 'image/png');
      s.elements.save([
        SurfaceElement(
          id: 'img',
          surfaceId: page,
          type: 'image',
          rect: const Rect.fromLTWH(0, 0, 10, 10),
          z: -1,
          createdAt: 1,
          data: ImageData(blob: image, width: 1, height: 1).toJson(),
        ),
      ]);
      s.strokes.save([_ink('a0', page)]);
      final v = (await versions().record(n.id))!;
      expect(v.blobs, [image]);
      // The image and the ink go from the page; only the version keeps them.
      s.elements.delete(['img']);
      s.strokes.delete(['a0']);
      for (var i = 0; i < 2; i++) {
        clock.advance(const Duration(days: 40));
        await s.blobGc.run();
      }
      // The notebook's one version: thinning keeps it, so it still counts.
      for (final sha in [...v.packs, image]) {
        expect(await s.blobs.has(sha), isTrue, reason: sha);
      }
      versions().delete([v.id]);
      for (var i = 0; i < 2; i++) {
        clock.advance(const Duration(days: 8));
        await s.blobGc.run();
      }
      for (final sha in [...v.packs, image]) {
        expect(await s.blobs.has(sha), isFalse, reason: sha);
      }
    });

    test('versions of a notebook deleted forever go after the retention', () async {
      final n = paged(pages: 1);
      await versions().record(n.id);
      s.notebooks.delete(n.id);
      versions().maintain();
      expect(s.versions.store.countOf(n.id), 1);
      clock.advance(const Duration(days: 31));
      versions().maintain();
      expect(s.versions.store.countOf(n.id), 0);
    });
  });

  group('recorder', () {
    test('a version after editing goes quiet, and at most every ten minutes', () {
      fakeAsync((async) {
        final made = <String>[];
        final recorder = VersionRecorder((id) async => made.add(id), clock: clock)..enabled = true;
        void wait(Duration d) {
          clock.advance(d);
          async.elapse(d);
        }

        recorder.noteEdit('n');
        wait(const Duration(minutes: 1));
        expect(made, isEmpty);
        recorder.noteEdit('n');
        wait(const Duration(minutes: 1, seconds: 59));
        expect(made, isEmpty, reason: 'two minutes from the last edit');
        wait(const Duration(seconds: 2));
        expect(made, ['n']);

        // Writing on without a pause: one at the latest ten minutes in.
        for (var i = 0; i < 12; i++) {
          recorder.noteEdit('n');
          wait(const Duration(minutes: 1));
        }
        expect(made, ['n', 'n']);
        expect(recorder.isPending('n'), isTrue);
        recorder.noteEdit('other');
        unawaited(recorder.flush('n'));
        async.flushMicrotasks();
        expect(made, ['n', 'n', 'n'], reason: 'flushed');
        expect(recorder.isPending('n'), isFalse);
        expect(recorder.isPending('other'), isTrue);
        recorder.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('off until enabled', () {
      fakeAsync((async) {
        final made = <String>[];
        VersionRecorder((id) async => made.add(id), clock: clock).noteEdit('n');
        async.elapse(const Duration(hours: 1));
        expect(made, isEmpty);
      });
    });
  });
}
