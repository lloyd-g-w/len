import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text_data.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';

import 'data_test.dart' show FakeClock, stroke;
import 'sync_test.dart' show FakeServer, apiFor, device;

SurfaceElement textBox(
  String id,
  Offset at, {
  String text = 'hello',
  String surface = 's',
  double width = 120,
}) => SurfaceElement(
  id: id,
  surfaceId: surface,
  type: 'text',
  rect: Rect.fromLTWH(at.dx, at.dy, width, 30),
  z: 1,
  createdAt: 1,
  data: TextData(text: text).toJson(),
);

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late ElementRepository elements;
  late StrokeRepository strokes;

  setUp(() {
    db = AppDatabase.inMemory();
    clock = FakeClock();
    elements = ElementRepository(db, deviceId: 'dev-a', clock: clock);
    strokes = StrokeRepository(db, deviceId: 'dev-a', clock: clock);
  });

  tearDown(() => db.close());

  group('SurfaceElement', () {
    test('rotated bounds and containment', () {
      final e = textBox('a', Offset.zero).copyWith(rotation: 1.5707963267948966);
      // 120×30 box rotated 90° about its centre (60, 15).
      expect(e.bounds.width, closeTo(30, 1e-9));
      expect(e.bounds.height, closeTo(120, 1e-9));
      expect(e.contains(const Offset(60, -40)), isTrue);
      expect(e.contains(const Offset(110, 15)), isFalse);
    });

    test('TextData tolerates junk and keeps unknown keys on edit', () {
      final data = TextData.fromJson({'text': 3, 'size': 'big', 'align': 'diagonal', 'x': 1});
      expect(data, const TextData());
      expect(const TextData(text: 'a').toJson({'future': true, 'text': 'old'}), {
        'future': true,
        ...const TextData(text: 'a').toJson(),
      });
    });
  });

  group('ElementRepository', () {
    test('loads only elements in the requested chunks', () {
      elements.save([textBox('near', const Offset(10, 10)), textBox('far', const Offset(9e5, 0))]);
      final range = ChunkGrid.rangeFor(const Rect.fromLTWH(0, 0, 100, 100));
      expect(elements.populatedChunks('s', range), [(x: 0, y: 0)]);
      final loaded = elements.loadChunks('s', [(x: 0, y: 0)]);
      expect(loaded.single.id, 'near');
      expect(TextData.fromJson(loaded.single.data).text, 'hello');
    });

    test('an update moves the element in the chunk index', () {
      elements.save([textBox('a', const Offset(10, 10))]);
      elements.save([textBox('a', const Offset(2000, 10))]);
      expect(elements.loadChunks('s', [(x: 0, y: 0)]), isEmpty);
      expect(elements.loadChunks('s', [(x: 3, y: 0)]).single.rect.left, 2000);
    });

    test('delete tombstones and drops the index', () {
      elements.save([textBox('a', const Offset(10, 10))]);
      elements.delete(['a']);
      expect(elements.loadChunks('s', [(x: 0, y: 0)]), isEmpty);
      final record = elements.dirtyRecords(10).single;
      expect(record.deleted, isTrue);
    });

    test('unknown types and fields round-trip through sync records', () {
      final remote = SyncRecord(
        collection: 'elements',
        id: 'img',
        updatedAt: 5,
        deviceId: 'dev-b',
        deleted: false,
        data: {
          'surfaceId': 's',
          'type': 'sticker',
          'x': 1,
          'y': 2,
          'w': 3,
          'h': 4,
          'createdAt': 9,
          'data': {'blob': 'abc'},
          'extra': 'ignored',
        },
      );
      expect(elements.applyRemote(remote), isTrue);
      final loaded = elements.loadChunks('s', [(x: 0, y: 0)]).single;
      expect(loaded.type, 'sticker');
      expect(loaded.knownType, isNull);
      expect(loaded.data, {'blob': 'abc'});
      expect(loaded.z, 9); // missing z defaults to createdAt
      elements.markAllDirty();
      expect(elements.dirtyRecords(10).single.data!['data'], {'blob': 'abc'});
    });

    test('malformed payloads are rejected before writing', () {
      final bad = SyncRecord(
        collection: 'elements',
        id: 'x',
        updatedAt: 5,
        deviceId: 'b',
        deleted: false,
        data: {'surfaceId': 's', 'type': 'text', 'x': 'nope'},
      );
      expect(() => elements.applyRemote(bad), throwsFormatException);
      expect(elements.dirtyRecords(10), isEmpty);
    });

    test('the migration is idempotent when re-run', () {
      final dir = Directory.systemTemp.createTempSync('len_migrate');
      final path = '${dir.path}/db.sqlite';
      final first = AppDatabase.open(path);
      final version = first.db.select('PRAGMA user_version').first.columnAt(0) as int;
      // Pretend a parallel branch's migration ran ours already, out of order.
      first.db.execute('PRAGMA user_version = ${version - 1}');
      first.close();
      final second = AppDatabase.open(path);
      expect(second.db.select('PRAGMA user_version').first.columnAt(0), version);
      second.close();
      dir.deleteSync(recursive: true);
    });
  });

  group('SurfaceModel with elements', () {
    late SurfaceModel model;

    setUp(() {
      model = SurfaceModel(
        surfaceId: 's',
        repository: strokes,
        elementRepository: elements,
        clock: clock,
      );
    });

    tearDown(() => model.dispose());

    test('elements load lazily with the chunks around the viewport', () {
      elements.save([textBox('near', const Offset(10, 10)), textBox('far', const Offset(9e5, 0))]);
      model.ensureLoaded(const Rect.fromLTWH(0, 0, 800, 600));
      expect(model.elementById('near'), isNotNull);
      expect(model.elementById('far'), isNull);
      expect(model.chunksIn(ChunkGrid.rangeFor(const Rect.fromLTWH(0, 0, 100, 100))), [
        (x: 0, y: 0),
      ]);
    });

    test('create, edit and delete are undoable and persisted', () {
      final v1 = textBox('t', const Offset(10, 10), text: 'one');
      final v2 = textBox('t', const Offset(10, 10), text: 'two');
      model.commit(InkEdit(addedElements: [v1]));
      model.commit(InkEdit(removedElements: [v1], addedElements: [v2]));
      model.commit(InkEdit(removedElements: [v2]));
      expect(model.elementById('t'), isNull);

      model.undo();
      expect(TextData.fromJson(model.elementById('t')!.data).text, 'two');
      model.undo();
      expect(TextData.fromJson(model.elementById('t')!.data).text, 'one');
      expect(TextData.fromJson(elements.loadChunks('s', [(x: 0, y: 0)]).single.data).text, 'one');
      model.undo();
      expect(model.elementById('t'), isNull);
      expect(elements.loadChunks('s', [(x: 0, y: 0)]), isEmpty);
      model.redo();
      model.redo();
      expect(TextData.fromJson(model.elementById('t')!.data).text, 'two');
    });

    test('merged edits collapse intermediate element versions', () {
      final v1 = textBox('t', Offset.zero, text: 'a');
      final v2 = textBox('t', Offset.zero, text: 'ab');
      model.commit(InkEdit(addedElements: [v1]));
      model.commit(InkEdit(removedElements: [v1], addedElements: [v2]), merge: true);
      model.undo();
      expect(model.elementById('t'), isNull);
      expect(model.history.canUndo, isFalse);
    });

    test('one edit can move strokes and elements together', () {
      final s = stroke('a', const Offset(10, 10));
      final e = textBox('t', const Offset(10, 40));
      model.commit(InkEdit(added: [s], addedElements: [e]));
      final moved = s.withPoints([for (final p in s.points) p], id: 'b');
      model.commit(
        InkEdit(
          added: [moved],
          removed: [s],
          addedElements: [e.copyWith(rect: e.rect.shift(const Offset(5, 5)))],
          removedElements: [e],
        ),
      );
      model.undo();
      expect(model.strokeById('a'), isNotNull);
      expect(model.strokeById('b'), isNull);
      expect(model.elementById('t')!.rect.left, 10);
    });

    test('hidden items are reported and invalidate their chunks', () {
      model.commit(InkEdit(added: [stroke('a', const Offset(10, 10))]));
      final invalidated = <Set<dynamic>?>[];
      final sub = model.invalidations.listen(invalidated.add);
      model.setHidden({'a'});
      expect(model.isHidden('a'), isTrue);
      expect(invalidated.single, {(x: 0, y: 0)});
      model.setHidden({'a'}); // unchanged → no-op
      expect(invalidated, hasLength(1));
      sub.cancel();
    });
  });

  test('elements sync between devices and die with their notebook', () async {
    final server = FakeServer();
    final a = device(server);
    final b = device(server);
    final nb = a.notebooks.create(
      title: 'T',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    a.elements.save([textBox('t', const Offset(5, 5), surface: nb.id, text: 'synced')]);
    await a.sync.engine.sync(apiFor(server));
    final changes = await b.sync.engine.sync(apiFor(server));
    expect(changes.strokeSurfaces, {nb.id});
    final got = b.elements.loadChunks(nb.id, [(x: 0, y: 0)]).single;
    expect(TextData.fromJson(got.data).text, 'synced');

    b.notebooks.delete(nb.id);
    expect(b.elements.loadChunks(nb.id, [(x: 0, y: 0)]), isEmpty);
    await b.sync.engine.sync(apiFor(server));
    final removal = await a.sync.engine.sync(apiFor(server));
    expect(removal.strokeSurfaces, {nb.id});
    expect(a.elements.loadChunks(nb.id, [(x: 0, y: 0)]), isEmpty);
  });
}
