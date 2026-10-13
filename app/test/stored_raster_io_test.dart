import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/raster_store.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/ink/render/stored_raster_io.dart';

import 'support/canvas_fixtures.dart';

/// Reads wait until released; counts what was asked for.
class _HeldStore implements RasterStore {
  final List<String> asked = [];
  final List<Completer<Uint8List?>> held = [];
  int writes = 0;

  @override
  Future<Uint8List?> read(String name) {
    asked.add(name);
    final completer = Completer<Uint8List?>();
    held.add(completer);
    return completer.future;
  }

  @override
  Future<void> write(String name, Uint8List bytes) async => writes++;

  void releaseAll() {
    for (final c in held) {
      if (!c.isCompleted) c.complete(null);
    }
  }
}

String _name(ChunkKey k) => 's_${k.x}_${k.y}_64_x.png';

Future<ui.Image> _image() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF336699), ui.BlendMode.src);
  return recorder.endRecording().toImage(8, 8);
}

void main() {
  testWidgets('reads go a few at a time, nearest the middle first; those panned away are dropped', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = _HeldStore();
      final io = StoredRasterIo(store, maxReads: 4)..view = const ChunkRange(0, 0, 9, 9);
      final done = <ChunkKey>[];
      // Asked for in reading order, as a painter does.
      for (final key in const ChunkRange(0, 0, 9, 9).keys) {
        io.read(_name(key), key, (_) => done.add(key));
      }
      await Future<void>.delayed(Duration.zero);
      expect(store.asked, hasLength(4));
      for (final name in store.asked) {
        final [_, x, y, ...] = name.split('_');
        expect((int.parse(x) - 4.5).abs(), lessThanOrEqualTo(1), reason: name);
        expect((int.parse(y) - 4.5).abs(), lessThanOrEqualTo(1), reason: name);
      }

      // The view moves to the right half: the left half is not read.
      io.view = const ChunkRange(6, 0, 15, 9);
      await settle(() {
        store.releaseAll();
        return !io.reading;
      });
      final read = store.asked.skip(4).map((n) => int.parse(n.split('_')[1]));
      expect(read, everyElement(greaterThanOrEqualTo(5))); // The view, one chunk around.
      expect(store.asked.length, lessThan(60));
      expect(done.length, store.asked.length);
      io.dispose();
    });
  });

  testWidgets('writes wait until the view is idle, and go when it closes', (tester) async {
    await tester.runAsync(() async {
      final store = MemoryRasterStore();
      // Long enough that a busy machine never stalls a 10 ms wait past it.
      final io = StoredRasterIo(store, idleDelay: const Duration(seconds: 1));
      io.write('a.png', await _image());
      expect(io.saving, isTrue);
      // Frames keep coming (a pinch): nothing is written.
      for (var i = 0; i < 15; i++) {
        io.noteActivity();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.writes, 0);
      await settle(() => !io.saving);
      expect(store.names, ['a.png']);
      // Known to be stored: not written again.
      io.write('a.png', await _image());
      expect(io.saving, isFalse);

      io
        ..write('b.png', await _image())
        ..noteActivity()
        ..dispose(); // The canvas closes.
      // At once, not after [idleDelay] (generous for a busy machine).
      await settle(() => !io.saving, limit: const Duration(milliseconds: 500));
      expect(store.names, ['a.png', 'b.png']);
    });
  });
}
