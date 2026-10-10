import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_codec.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/pen/eraser_config.dart';
import 'package:len/ink/surface_model.dart';

import 'data_test.dart' show FakeClock;

Stroke styled(String id, {InkTool tool = InkTool.fountain, double y = 0}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: tool,
  color: 0xFF112233,
  width: 4,
  points: [for (var x = 0.0; x <= 100; x += 5) StrokePoint(x, y, 0.6)],
  createdAt: 3,
  style: const StrokeStyle(opacity: 0.9, thinning: 0.7, streamline: 0.3, taperStart: 10),
);

void main() {
  late AppDatabase db;
  late StrokeRepository strokes;

  setUp(() {
    db = AppDatabase.inMemory();
    strokes = StrokeRepository(db, deviceId: 'dev', clock: FakeClock());
  });

  tearDown(() => db.close());

  test('a migration adds a nullable style column', () {
    final columns = db.db.select('PRAGMA table_info(strokes)');
    final style = columns.singleWhere((r) => r['name'] == 'style');
    expect(style['notnull'], 0);
  });

  test('styles round-trip through storage and sync records', () {
    strokes.save([styled('a')]);
    final loaded = strokes.loadChunks('s', [(x: 0, y: 0)]).single;
    expect(loaded.tool, InkTool.fountain);
    expect(loaded.style, styled('a').style);

    final record = strokes.dirtyRecords(10).single;
    expect(record.data!['tool'], 'fountain');
    final other = AppDatabase.inMemory();
    addTearDown(other.close);
    final remote = StrokeRepository(other, deviceId: 'dev-b');
    remote.writeRemote(SyncRecord.fromJson(jsonDecode(jsonEncode(record.toJson()))));
    expect(remote.loadChunks('s', [(x: 0, y: 0)]).single.style, styled('a').style);
  });

  test('old rows and records without a style get the legacy defaults', () {
    db.db.execute(
      'INSERT INTO strokes (id, surface_id, tool, color, width, points, created_at, updated_at, '
      "device_id, deleted, dirty) VALUES ('old', 's', 'highlighter', 0, 18, ?, 1, 1, 'x', 0, 0)",
      [
        StrokeCodec.encode(const [StrokePoint(1, 1, 0.5), StrokePoint(9, 1, 0.5)]),
      ],
    );
    db.db.execute("INSERT INTO stroke_chunks VALUES ('s', 0, 0, 'old')");
    final old = strokes.loadChunks('s', [(x: 0, y: 0)]).single;
    expect(old.style, StrokeStyle.defaultsFor(InkTool.highlighter));

    strokes.writeRemote(
      SyncRecord(
        collection: 'strokes',
        id: 'v1',
        updatedAt: 5,
        deviceId: 'old-client',
        deleted: false,
        data: {
          'surfaceId': 's',
          'tool': 'pen',
          'color': 0xFF000000,
          'width': 2,
          'points': base64Encode(StrokeCodec.encode(const [StrokePoint(0, 0, 0.5)])),
          'createdAt': 1,
          'style': 'garbage', // tolerated
        },
      ),
    );
    final v1 = strokes.loadChunks('s', [(x: 0, y: 0)]).firstWhere((s) => s.id == 'v1');
    expect(v1.style, StrokeStyle.defaultsFor(InkTool.pen));
  });

  group('SurfaceModel pixel eraser', () {
    test('splits strokes; one undo restores the original exactly', () {
      final model = SurfaceModel(surfaceId: 's', repository: strokes, clock: FakeClock());
      addTearDown(model.dispose);
      model.addStroke(styled('a'));
      // One drag in two moves, the second cutting a fragment from the first.
      model.eraseAlong(
        const Offset(50, -20),
        const Offset(50, 20),
        3,
        continueEdit: false,
        mode: EraserMode.pixel,
      );
      model.eraseAlong(
        const Offset(80, -20),
        const Offset(80, 20),
        3,
        continueEdit: true,
        mode: EraserMode.pixel,
      );
      final live = strokes.loadChunks('s', [(x: 0, y: 0)]);
      expect(live, hasLength(3));
      expect(live.every((s) => s.id != 'a' && s.style.thinning == 0.7), isTrue);

      model.undo();
      final restored = strokes.loadChunks('s', [(x: 0, y: 0)]);
      expect(restored.map((s) => s.id), ['a']);
      expect(model.history.canUndo, isTrue); // only the draw is left
      model.redo();
      expect(strokes.loadChunks('s', [(x: 0, y: 0)]), hasLength(3));
    });

    test('"highlighter only" leaves pen ink alone', () {
      final model = SurfaceModel(surfaceId: 's', repository: strokes);
      addTearDown(model.dispose);
      model
        ..addStroke(styled('pen'))
        ..addStroke(styled('hl', tool: InkTool.highlighter, y: 2));
      final erased = model.eraseAlong(
        const Offset(50, -20),
        const Offset(50, 20),
        3,
        continueEdit: false,
        highlighterOnly: true,
      );
      expect(erased, isTrue);
      expect(model.strokeById('pen'), isNotNull);
      expect(model.strokeById('hl'), isNull);
    });
  });
}
