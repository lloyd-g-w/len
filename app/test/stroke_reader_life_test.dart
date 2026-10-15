import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/background_stroke_reader.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';

/// The stroke reader's isolate dying, or outliving the app's: reads fall
/// back instead of waiting forever, and the reader never lives on orphaned.
void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len-reader-life-');
    path = '${dir.path}/len.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('reads fall back to this isolate once the reader died', () async {
    final db = AppDatabase.open(path);
    addTearDown(db.close);
    final strokes = StrokeRepository(db, deviceId: 'd')..save([_stroke('a')]);
    final reader = BackgroundStrokeReader(path, fallback: strokes);
    addTearDown(reader.close);
    final isolate = (await reader.isolate)!;
    final exited = ReceivePort();
    isolate.addOnExitListener(exited.sendPort);
    isolate.kill(priority: Isolate.immediate);
    await exited.first;
    exited.close();
    final range = ChunkGrid.rangeFor(const Rect.fromLTWH(0, 0, 1000, 1000));
    final load = await reader.read('s', range).timeout(const Duration(seconds: 20));
    expect(load.strokes.map((s) => s.id), ['a']);
  });

  test('answered reads leave nothing waiting on the reader (no answer kept alive)', () async {
    final db = AppDatabase.open(path);
    addTearDown(db.close);
    final strokes = StrokeRepository(db, deviceId: 'd')..save([_stroke('a')]);
    final reader = BackgroundStrokeReader(path, fallback: strokes);
    addTearDown(reader.close);
    final range = ChunkGrid.rangeFor(const Rect.fromLTWH(0, 0, 1000, 1000));
    for (var i = 0; i < 5; i++) {
      expect((await reader.read('s', range)).strokes, hasLength(1));
    }
    // Each wait for an answer once also waited on the worker's exit, which
    // never comes: every answer stayed reachable for the app's lifetime.
    expect(reader.waiting, 0);
  });

  test("the reader exits with the app's isolate", () async {
    AppDatabase.open(path).close();
    final exited = ReceivePort();
    // An isolate standing in for the app's: it starts a reader and exits
    // (as the engine's does when Android destroys it) without closing it.
    await Isolate.spawn(_startReaderAndExit, (path, exited.sendPort));
    await exited.first.timeout(const Duration(seconds: 20));
    exited.close();
  });
}

Future<void> _startReaderAndExit((String, SendPort) args) async {
  final (path, exited) = args;
  final db = AppDatabase.open(path);
  final reader = BackgroundStrokeReader(path, fallback: StrokeRepository(db, deviceId: 'd'));
  // Added while the reader surely lives: it waits for its owner's exit.
  (await reader.isolate)!.addOnExitListener(exited);
  db.close();
  Isolate.exit();
}

Stroke _stroke(String id) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 2,
  points: const [StrokePoint(10, 10, 0.5), StrokePoint(20, 10, 0.5)],
  createdAt: 1,
);
