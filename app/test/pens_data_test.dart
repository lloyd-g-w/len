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

Stroke styled(String id, {InkTool tool = InkTool.ballpoint, double y = 0}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: tool,
  color: 0xFF112233,
  width: 4,
  points: [for (var x = 0.0; x <= 100; x += 5) StrokePoint(x, y, 0.6)],
  createdAt: 3,
  style: const StrokeStyle(opacity: 0.9, thinning: 0.7, streamline: 0.3, unit: 0.5),
);

void main() {
  late AppDatabase db;
  late StrokeRepository strokes;

  setUp(() {
    db = AppDatabase.inMemory();
    strokes = StrokeRepository(db, deviceId: 'dev', clock: FakeClock());
  });

  tearDown(() => db.close());

  test('styles round-trip through storage and sync records', () {
    strokes.save([styled('a')]);
    final loaded = strokes.loadChunks('s', [(x: 0, y: 0)]).single;
    expect(loaded.tool, InkTool.ballpoint);
    expect(loaded.style, styled('a').style);

    final record = strokes.dirtyRecords(10).single;
    expect(record.data!['tool'], 'ballpoint');
    final other = AppDatabase.inMemory();
    addTearDown(other.close);
    final remote = StrokeRepository(other, deviceId: 'dev-b');
    remote.writeRemote(SyncRecord.fromJson(jsonDecode(jsonEncode(record.toJson()))));
    expect(remote.loadChunks('s', [(x: 0, y: 0)]).single.style, styled('a').style);
  });

  test('rows and records without a style or with an unknown tool are malformed', () {
    final points = StrokeCodec.encode(const [StrokePoint(1, 1, 0.5), StrokePoint(9, 1, 0.5)]);
    for (final (id, tool, style) in [
      ('no-style', 'highlighter', null),
      ('odd-tool', 'fountain', '{"o":1,"th":0.5,"sl":0.4,"e":"round"}'),
    ]) {
      db.db.execute(
        'INSERT INTO strokes (id, surface_id, tool, color, width, points, created_at, '
        "updated_at, device_id, deleted, dirty, style) VALUES (?, 's', ?, 0, 18, ?, 1, 1, 'x', "
        '0, 0, ?)',
        [id, tool, points, style],
      );
      db.db.execute("INSERT INTO stroke_chunks (surface_id, cx, cy, stroke_id) VALUES ('s', 0, 0, ?)", [id]);
    }
    expect(strokes.loadChunks('s', [(x: 0, y: 0)]), isEmpty);

    SyncRecord record(String tool, Object? style) => SyncRecord(
      collection: 'strokes',
      id: 'r',
      updatedAt: 5,
      deviceId: 'other',
      deleted: false,
      data: {
        'surfaceId': 's',
        'tool': tool,
        'color': 0xFF000000,
        'width': 2,
        'points': base64Encode(StrokeCodec.encode(const [StrokePoint(0, 0, 0.5)])),
        'createdAt': 1,
        'style': style,
      },
    );
    final style = const StrokeStyle().toJson();
    expect(() => strokes.writeRemote(record('pen', style)), throwsFormatException);
    expect(() => strokes.writeRemote(record('ballpoint', 'garbage')), throwsFormatException);
    expect(() => strokes.writeRemote(record('ballpoint', null)), throwsFormatException);
    strokes.writeRemote(record('ballpoint', style));
    expect(strokes.loadChunks('s', [(x: 0, y: 0)]).single.id, 'r');
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
