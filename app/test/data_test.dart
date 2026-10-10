import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/notebook_repository.dart';
import 'package:len/data/page_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/surface_model.dart';

/// A clock whose time only moves when told to.
class FakeClock extends Clock {
  int now = 1000;
  int _ids = 0;

  @override
  int nowMs() => now;

  @override
  String newId() => 'id${_ids++}';
}

Stroke stroke(String id, Offset at, {String surface = 's'}) => Stroke(
      id: id,
      surfaceId: surface,
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 2,
      points: [StrokePoint(at.dx, at.dy, 0.5), StrokePoint(at.dx + 10, at.dy, 0.5)],
      createdAt: 1,
    );

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late StrokeRepository strokes;
  late PageRepository pages;
  late NotebookRepository notebooks;

  setUp(() {
    db = AppDatabase.inMemory();
    clock = FakeClock();
    strokes = StrokeRepository(db, deviceId: 'dev-a', clock: clock);
    pages = PageRepository(db, deviceId: 'dev-a', clock: clock);
    notebooks = NotebookRepository(db, deviceId: 'dev-a', pages: pages, strokes: strokes, clock: clock);
  });

  tearDown(() => db.close());

  group('AppDatabase migrations', () {
    test('re-applying the page/blob migration is harmless and restores a skipped stroke style', () {
      final dir = Directory.systemTemp.createTempSync('len_migrate_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/len.db';
      final fresh = AppDatabase.open(path);
      final latest = fresh.db.select('PRAGMA user_version').first.columnAt(0) as int;
      // A database from before the documents/library merge recorded the
      // page/blob migration early and never got the stroke style column.
      fresh.db.execute('ALTER TABLE strokes DROP COLUMN style');
      // Index of _addPageDetailsAndBlobs in AppDatabase._migrations.
      fresh.db.execute('PRAGMA user_version = 4');
      fresh.close();

      final upgraded = AppDatabase.open(path);
      addTearDown(upgraded.close);
      List<Object?> columns(String table) =>
          upgraded.db.select('PRAGMA table_info($table)').map((r) => r['name']).toList();
      expect(columns('strokes'), contains('style'));
      expect(columns('pages'), containsAll(['paper_color', 'bookmarked', 'background']));
      expect(upgraded.db.select('PRAGMA user_version').first.columnAt(0), latest);
    });
  });

  group('StrokeRepository', () {
    test('loads only strokes in the requested chunks', () {
      strokes.save([stroke('near', const Offset(10, 10)), stroke('far', const Offset(5e5, 5e5))]);
      final range = ChunkGrid.rangeFor(const Rect.fromLTWH(0, 0, 100, 100));
      final keys = strokes.populatedChunks('s', range);
      expect(keys, [(x: 0, y: 0)]);
      expect(strokes.loadChunks('s', keys).map((s) => s.id), ['near']);
    });

    test('tombstoned strokes disappear from loading and are pushed', () {
      strokes.save([stroke('a', Offset.zero)]);
      strokes.markClean([(id: 'a', updatedAt: clock.now)]);
      clock.now++;
      strokes.delete(['a']);
      expect(strokes.loadChunks('s', [(x: 0, y: 0)]), isEmpty);
      final dirty = strokes.dirtyRecords(10);
      expect(dirty.single.deleted, isTrue);
      expect(dirty.single.data, isNull);
    });

    test('markClean keeps rows that changed after being read', () {
      strokes.save([stroke('a', Offset.zero)]);
      final pushed = strokes.dirtyRecords(10).single;
      clock.now++;
      strokes.delete(['a']); // edited while the push was in flight
      strokes.markClean([(id: pushed.id, updatedAt: pushed.updatedAt)]);
      expect(strokes.dirtyRecords(10), hasLength(1));
    });

    test('an edit in the same millisecond as a push stays dirty', () {
      strokes.save([stroke('a', Offset.zero)]);
      final pushed = strokes.dirtyRecords(10).single;
      strokes.delete(['a']); // clock did not move
      strokes.markClean([(id: pushed.id, updatedAt: pushed.updatedAt)]);
      expect(strokes.dirtyRecords(10).single.deleted, isTrue);
    });

    test('local edits beat the version they replace despite clock skew', () {
      strokes.save([stroke('a', Offset.zero)]);
      final data = strokes.dirtyRecords(1).single.data;
      // Another device with a clock far ahead wrote the stroke.
      strokes.applyRemote(SyncRecord(
        collection: 'strokes',
        id: 'a',
        updatedAt: 9000,
        deviceId: 'dev-z',
        deleted: false,
        data: data,
      ));
      strokes.delete(['a']);
      final tombstone = strokes.dirtyRecords(10).single;
      expect(tombstone.updatedAt, 9001);
      expect(
        tombstone.supersedes(updatedAt: 9000, deviceId: 'dev-z'),
        isTrue,
      );
    });

    test('dirty records page by id', () {
      strokes.save([for (final id in ['c', 'a', 'b']) stroke(id, Offset.zero)]);
      expect(strokes.dirtyRecords(2).map((r) => r.id), ['a', 'b']);
      expect(strokes.dirtyRecords(2, after: 'b').map((r) => r.id), ['c']);
    });

    test('live remote records without data are rejected', () {
      expect(
        () => strokes.applyRemote(const SyncRecord(
          collection: 'strokes',
          id: 'a',
          updatedAt: 1,
          deviceId: 'dev-b',
          deleted: false,
          data: null,
        )),
        throwsFormatException,
      );
    });

    test('remote strokes with absurd widths are rejected', () {
      strokes.save([stroke('a', Offset.zero)]);
      final data = {...strokes.dirtyRecords(1).single.data!, 'width': 1e7};
      expect(
        () => strokes.applyRemote(SyncRecord(
          collection: 'strokes',
          id: 'wide',
          updatedAt: 1,
          deviceId: 'dev-b',
          deleted: false,
          data: data,
        )),
        throwsFormatException,
      );
    });

    test('remote records follow last-write-wins', () {
      strokes.save([stroke('a', Offset.zero)]); // updatedAt 1000 by dev-a
      final record = strokes.dirtyRecords(1).single;

      SyncRecord remote(int at, String device, {bool deleted = false}) => SyncRecord(
            collection: 'strokes',
            id: 'a',
            updatedAt: at,
            deviceId: device,
            deleted: deleted,
            data: deleted ? null : record.data,
          );

      expect(strokes.applyRemote(remote(999, 'dev-z', deleted: true)), isFalse);
      expect(strokes.applyRemote(remote(1000, 'dev-0', deleted: true)), isFalse);
      expect(strokes.applyRemote(remote(1000, 'dev-b', deleted: true)), isTrue);
      expect(strokes.loadChunks('s', [(x: 0, y: 0)]), isEmpty);
      // A newer live version resurrects it.
      expect(strokes.applyRemote(remote(2000, 'dev-b')), isTrue);
      expect(strokes.loadChunks('s', [(x: 0, y: 0)]).single.id, 'a');
      expect(strokes.dirtyRecords(10), isEmpty);
    });

    test('a tombstone for an unknown stroke blocks older live versions', () {
      final data = (StrokeRepository(AppDatabase.inMemory(), deviceId: 'x')
            ..save([stroke('a', Offset.zero)]))
          .dirtyRecords(1)
          .single
          .data;
      strokes.applyRemote(const SyncRecord(
        collection: 'strokes',
        id: 'a',
        updatedAt: 5000,
        deviceId: 'dev-b',
        deleted: true,
        data: null,
      ));
      final applied = strokes.applyRemote(SyncRecord(
        collection: 'strokes',
        id: 'a',
        updatedAt: 4000,
        deviceId: 'dev-b',
        deleted: false,
        data: data,
      ));
      expect(applied, isFalse);
    });
  });

  test('migrations index dirty strokes for keyset pagination', () {
    final plan = db.db
        .select('EXPLAIN QUERY PLAN SELECT * FROM strokes WHERE dirty = 1 AND id > ? ORDER BY id LIMIT ?', ['', 10])
        .map((r) => r['detail'] as String)
        .join('\n');
    expect(plan, contains('strokes_dirty'));
    expect(plan, isNot(contains('TEMP B-TREE')));
  });

  group('NotebookRepository', () {
    test('paged notebooks start with one page; delete cascades', () {
      final nb = notebooks.create(
        title: 'Physics',
        kind: NotebookKind.paged,
        paper: PaperStyle.lined,
        coverColor: 0xFF0000FF,
      );
      final page = pages.pagesOf(nb.id).single;
      strokes.save([stroke('a', Offset.zero, surface: page.id)]);

      notebooks.delete(nb.id);
      expect(notebooks.list(), isEmpty);
      expect(pages.pagesOf(nb.id), isEmpty);
      expect(strokes.loadChunks(page.id, [(x: 0, y: 0)]), isEmpty);
    });

    test('pages inserted after a middle page get an intermediate sort key', () {
      final nb = notebooks.create(
        title: 'N',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final first = pages.pagesOf(nb.id).single;
      final last = pages.addPage(nb.id, paper: PaperStyle.blank);
      final middle = pages.addPage(nb.id, paper: PaperStyle.blank, after: first);
      expect(pages.pagesOf(nb.id).map((p) => p.id), [first.id, middle.id, last.id]);
    });
  });

  group('SurfaceModel', () {
    test('erase + undo + redo round-trips through storage', () {
      final model = SurfaceModel(surfaceId: 's', repository: strokes);
      model.addStroke(stroke('a', const Offset(0, 0)));
      expect(model.eraseAlong(const Offset(5, -20), const Offset(5, 20), 2, continueEdit: false), isTrue);
      expect(strokes.loadChunks('s', [(x: 0, y: 0)]), isEmpty);

      model.undo(); // restores 'a'
      expect(model.strokeById('a'), isNotNull);
      expect(strokes.loadChunks('s', [(x: 0, y: 0)]).single.id, 'a');

      model.redo(); // erases again
      expect(model.strokeById('a'), isNull);
      model.dispose();
    });

    test('loads lazily around the viewport and evicts far chunks', () {
      strokes.save([
        for (var i = 0; i < 50; i++) stroke('s$i', Offset(i * 5000.0, 0)),
      ]);
      final model = SurfaceModel(surfaceId: 's', repository: strokes, maxLoadedChunks: 4);
      model.ensureLoaded(const Rect.fromLTWH(0, 0, 100, 100));
      expect(model.strokeById('s0'), isNotNull);
      expect(model.strokeById('s1'), isNull);

      model.ensureLoaded(const Rect.fromLTWH(5000, 0, 100, 100));
      expect(model.strokeById('s1'), isNotNull);
      for (var i = 2; i < 10; i++) {
        model.ensureLoaded(Rect.fromLTWH(i * 5000.0, 0, 100, 100));
      }
      expect(model.loadedStrokeCount, lessThan(10));
      expect(model.strokeById('s0'), isNull); // evicted
      model.dispose();
    });
  });
}
