import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/stroke_codec.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/spatial_index.dart';
import 'package:len/ink/stroke_hit_test.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

Stroke stroke(String id, List<Offset> pts, {double width = 2, int createdAt = 0}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.pen,
  color: 0xFF000000,
  width: width,
  points: [for (final p in pts) StrokePoint(p.dx, p.dy, 0.5)],
  createdAt: createdAt,
);

void main() {
  test('drawOrder puts highlighter ink under pen ink, else paint order', () {
    Stroke s(String id, InkTool tool, int at) => Stroke(
      id: id,
      surfaceId: 's',
      tool: tool,
      color: 0,
      width: 2,
      points: const [StrokePoint(0, 0, 0.5)],
      createdAt: at,
    );
    final strokes = [
      s('pen1', InkTool.ballpoint, 1),
      s('hl2', InkTool.highlighter, 2),
      s('pen3', InkTool.ballpoint, 3),
      s('hl0', InkTool.highlighter, 0),
    ]..sort(Stroke.drawOrder);
    expect(strokes.map((s) => s.id), ['hl0', 'hl2', 'pen1', 'pen3']);
  });

  group('ChunkGrid', () {
    test('keys floor towards negative infinity', () {
      expect(ChunkGrid.keyAt(0, 0), (x: 0, y: 0));
      expect(ChunkGrid.keyAt(511.9, 512), (x: 0, y: 1));
      expect(ChunkGrid.keyAt(-0.1, -512), (x: -1, y: -1));
      expect(ChunkGrid.keyAt(-512.1, 0), (x: -2, y: 0));
    });

    test('rangeFor covers every overlapped chunk', () {
      final range = ChunkGrid.rangeFor(const Rect.fromLTRB(-10, -10, 600, 10));
      expect(range, const ChunkRange(-1, -1, 1, 0));
      expect(range.count, 6);
      expect(range.keys.length, 6);
    });
  });

  group('SpatialIndex', () {
    test('stores ids only in populated chunks and removes cleanly', () {
      final index = SpatialIndex();
      final far = stroke('far', [const Offset(1e6, -1e6), const Offset(1e6 + 5, -1e6)]);
      final near = stroke('near', [const Offset(10, 10), const Offset(700, 10)]);
      index
        ..insert(far.id, far.bounds)
        ..insert(near.id, near.bounds);
      expect(index.query(const Rect.fromLTWH(0, 0, 100, 100)), {'near'});
      expect(index.query(Rect.fromCenter(center: const Offset(1e6, -1e6), width: 10, height: 10)), {
        'far',
      });

      index.remove(near.id, near.bounds);
      expect(index.query(const Rect.fromLTWH(0, 0, 1000, 100)), isEmpty);
      expect(index.chunkCount, greaterThan(0)); // 'far' remains
      index.remove(far.id, far.bounds);
      expect(index.chunkCount, 0);
    });

    test('populatedIn handles huge ranges by scanning populated chunks', () {
      final index = SpatialIndex()..insert('a', const Rect.fromLTWH(5, 5, 1, 1));
      final huge = ChunkGrid.rangeFor(const Rect.fromLTRB(-1e9, -1e9, 1e9, 1e9));
      expect(index.populatedIn(huge), [(x: 0, y: 0)]);
    });
  });

  group('StrokeCodec', () {
    test('round-trips points at float32 precision', () {
      const points = [StrokePoint(1.5, -2.25, 0.5), StrokePoint(1e5, 3, 1)];
      expect(StrokeCodec.decode(StrokeCodec.encode(points)), points);
    });

    test('rejects truncated data', () {
      final bytes = StrokeCodec.encode(const [StrokePoint(1, 2, 0.5)]);
      expect(() => StrokeCodec.decode(bytes.sublist(0, 11)), throwsFormatException);
    });
  });

  group('StrokeHitTest', () {
    final s = stroke('s', [const Offset(0, 0), const Offset(100, 0)], width: 4);

    test('hits when the sweep passes within radius + half width', () {
      expect(StrokeHitTest.sweepHits(s, const Offset(50, 5), const Offset(50, 5), 3.5), isTrue);
      expect(StrokeHitTest.sweepHits(s, const Offset(50, 6), const Offset(50, 6), 3.5), isFalse);
    });

    test('detects a sweep crossing the stroke between samples', () {
      expect(StrokeHitTest.sweepHits(s, const Offset(50, -50), const Offset(50, 50), 1), isTrue);
    });
  });

  group('ViewportController', () {
    test('zoomAt keeps the focal point fixed', () {
      final v = ViewportController()..setSize(const Size(800, 600));
      const focal = Offset(200, 150);
      final before = v.toWorld(focal);
      v.zoomAt(focal, 2.5);
      expect(v.scale, 2.5);
      expect(v.toWorld(focal).dx, closeTo(before.dx, 1e-9));
      expect(v.toWorld(focal).dy, closeTo(before.dy, 1e-9));
    });

    test('clamps scale', () {
      final v = ViewportController(minScale: 0.5, maxScale: 2)..setSize(const Size(100, 100));
      v.zoomAt(Offset.zero, 100);
      expect(v.scale, 2);
      v.zoomAt(Offset.zero, 0.001);
      expect(v.scale, 0.5);
    });

    test('ignores non-finite or non-positive zoom factors', () {
      final v = ViewportController()..setSize(const Size(100, 100));
      for (final f in [double.nan, double.infinity, 0.0, -1.0]) {
        v.zoomAt(const Offset(50, 50), f);
      }
      expect(v.scale, 1);
      expect(v.offset, Offset.zero);
    });

    test('bounded content cannot be panned away', () {
      final v = ViewportController(contentBounds: const Rect.fromLTWH(0, 0, 794, 1123))
        ..setSize(const Size(400, 600))
        ..fitWidth();
      v.panBy(const Offset(-100000, -100000));
      final visible = v.visibleWorld;
      expect(visible.overlaps(v.contentBounds!), isTrue);
    });
  });

  group('UndoHistory', () {
    test('merges continued edits and clears redo on new edit', () {
      final a = stroke('a', [Offset.zero]);
      final b = stroke('b', [Offset.zero]);
      final h = UndoHistory()
        ..record(InkEdit(removed: [a]))
        ..record(InkEdit(removed: [b]), merge: true);
      final undone = h.takeUndo()!;
      expect(undone.removed.map((s) => s.id), ['a', 'b']);
      expect(h.canRedo, isTrue);
      h.record(InkEdit(added: [a]));
      expect(h.canRedo, isFalse);
    });
  });
}
