import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/stroke_row.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/geometry/affine.dart';
import 'package:len/ink/geometry/stroke_splitter.dart';
import 'package:len/ink/selection/transform_items.dart';
import 'package:len/ink/shapes/polyline.dart';
import 'package:len/ink/shapes/shape_builder.dart';

Stroke shapeStroke(ShapeGeometry shape, {String id = 'a', int? fill}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xFF1C7ED6,
  width: 2,
  points: ShapeBuilder.pointsOf(shape),
  createdAt: 1,
  style: ShapeBuilder.styleFor(const StrokeStyle(unit: 1)).withFill(fill),
  shape: shape,
);

void main() {
  final every = [
    for (final kind in ShapeKind.drawable)
      ShapeBuilder.dragged(kind, const Offset(10, 20), const Offset(130, 100)),
    ShapeGeometry(ShapeKind.polygon, const [
      Offset(0, 0),
      Offset(50, 0),
      Offset(60, 40),
      Offset(5, 30),
      Offset(-10, 15),
    ]),
    ShapeBuilder.dragged(ShapeKind.ellipse, const Offset(10, 20), const Offset(90, 100)),
    ShapeGeometry(ShapeKind.line, const [Offset(0, 0), Offset(100, 0), Offset(40, 30)]),
    ShapeGeometry(ShapeKind.arrow, const [Offset(0, 0), Offset(100, 0), Offset(40, -30)]),
    ShapeBuilder.dragged(ShapeKind.star, Offset.zero, const Offset(90, 90)).withStar(tips: 7),
    ShapeGeometry(ShapeKind.curve, const [
      Offset(0, 0),
      Offset(30, -20),
      Offset(70, -20),
      Offset(100, 0),
      Offset(130, 20),
      Offset(-30, 20),
    ]),
  ];

  group('ShapeGeometry', () {
    test('round-trips through JSON and is parsed strictly', () {
      for (final g in every) {
        expect(ShapeGeometry.fromJson(jsonDecode(jsonEncode(g.toJson()))), g, reason: '$g');
      }
      final star = every.firstWhere((g) => g.kind == ShapeKind.star).toJson();
      final line = every.first.toJson();
      for (final bad in <Object?>[
        null,
        'line',
        {...line, 'k': 'blob'},
        {
          ...line,
          'p': [0, 0, 1],
        },
        {
          ...line,
          'p': [0, 0, 1, 1, 2, 2, 3, 3],
        },
        {
          ...line,
          'p': [0, 0, 'x', 1],
        },
        {
          ...line,
          'p': [0, 0, double.nan, 1],
        },
        {...line, 'i': 0.4},
        {...star}..remove('i'),
        {...star, 'i': 1.5},
        {...star}..remove('n'),
        {...star, 'n': 2},
        {...star, 'n': 13},
        {...star, 'n': 5.5},
        {...line, 'n': 5},
        {
          'k': 'curve',
          'p': [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
        },
        {
          'k': 'circle',
          'p': [0, 0, 1, 1, 2, 2],
        },
        {
          'k': 'polygon',
          'p': [0, 0, 1, 1],
        },
      ]) {
        expect(() => ShapeGeometry.fromJson(bad), throwsFormatException, reason: '$bad');
      }
    });

    test('an ellipse keeps perpendicular radii; a circle turned stays one', () {
      final skewed = ShapeGeometry.fromJson({
        'k': 'ellipse',
        'p': [0, 0, 50, 0, 20, 30],
      });
      final [c, a, b] = skewed.points;
      expect((a - c).dx * (b - c).dx + (a - c).dy * (b - c).dy, closeTo(0, 1e-9));
      // The same ellipse: its outline passes through the conjugate ends.
      final outline = ShapeBuilder.outline(skewed);
      for (final p in const [Offset(50, 0), Offset(20, 30), Offset(-50, 0)]) {
        var near = double.infinity;
        for (var i = 1; i < outline.length; i++) {
          near = math.min(near, Polyline.distanceToSegment(p, outline[i - 1], outline[i]));
        }
        expect(near, lessThan(0.5));
      }
      final circle = ShapeGeometry(ShapeKind.circle, const [Offset(10, 10), Offset(60, 10)]);
      final turned = circle.map(
        Affine.rotation(0.6, pivot: Offset.zero).then(Affine.scaling(2, 2)).apply,
      );
      expect(turned.kind, ShapeKind.circle);
      expect((turned.points[1] - turned.points[0]).distance, closeTo(100, 1e-9));
      expect(circle.isClosed, isTrue);
      expect(every.last.isClosed, isTrue);
      expect(every.last.anchorCount, 2);
    });

    test('an affine map maps its outline exactly', () {
      final t = Affine.rotation(0.7, pivot: const Offset(50, 50)).then(Affine.scaling(1.5, 0.8));
      for (final g in every) {
        final mapped = ShapeBuilder.outline(g.map(t.apply));
        final expected = [for (final p in ShapeBuilder.outline(g)) t.apply(p)];
        if (g.kind == ShapeKind.curve || g.isBent) {
          // Flattened anew; its control points map exactly.
          expect(g.map(t.apply).points, [for (final p in g.points) t.apply(p)]);
          continue;
        }
        // Arrow heads are rebuilt for the new shaft; the rest maps exactly.
        if (g.kind == ShapeKind.arrow) {
          expect(mapped.take(2), expected.take(2));
          continue;
        }
        if (g.kind == ShapeKind.ellipse || g.kind == ShapeKind.circle) {
          // Sampled anew, on the mapped ellipse (unit circle in its frame):
          // squashed, a circle is one.
          final m = g.map(t.apply);
          expect(m.kind, ShapeKind.ellipse);
          final [c, a, b] = m.points;
          expect((a - c).dx * (b - c).dx + (a - c).dy * (b - c).dy, closeTo(0, 1e-6));
          final u = a - c, v = b - c, det = u.dx * v.dy - u.dy * v.dx;
          for (final p in mapped) {
            final d = p - c;
            final w = Offset((d.dx * v.dy - d.dy * v.dx) / det, (u.dx * d.dy - u.dy * d.dx) / det);
            expect(w.distance, closeTo(1, 1e-9));
          }
          continue;
        }
        expect(mapped.length, expected.length, reason: g.kind.name);
        for (var i = 0; i < mapped.length; i++) {
          expect((mapped[i] - expected[i]).distance, lessThan(1e-6), reason: g.kind.name);
        }
      }
    });
  });

  group('shape strokes', () {
    test('keep their geometry through storage and sync, fill included', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final repo = StrokeRepository(db, deviceId: 'd');
      final strokes = [
        for (var i = 0; i < every.length; i++) shapeStroke(every[i], id: 's$i', fill: 0x401C7ED6),
      ];
      repo.save(strokes);
      final loaded = {
        for (final s in repo.loadChunks('s', [(x: 0, y: 0)])) s.id: s,
      };
      for (final s in strokes) {
        expect(loaded[s.id]!.shape, s.shape);
        expect(loaded[s.id]!.style, s.style);
      }
      // Pushed and pulled (another device).
      final records = repo.dirtyRecords(100);
      final other = AppDatabase.inMemory();
      addTearDown(other.close);
      final remote = StrokeRepository(other, deviceId: 'e');
      for (final r in records) {
        expect((r.data!['style'] as Map)['sh'], isNotNull);
        remote.applyRemote(r);
      }
      final pulled = {
        for (final s in remote.loadChunks('s', [(x: 0, y: 0)])) s.id: s,
      };
      for (final s in strokes) {
        expect(pulled[s.id]!.shape, s.shape);
      }
      // A malformed shape makes the record malformed.
      final bad = records.first;
      final data = {
        ...bad.data!,
        'style': {
          ...bad.data!['style'] as Map,
          'sh': {
            'k': 'line',
            'p': [0],
          },
        },
      };
      expect(() => StrokeRow.fromRecord(bad.id, data), throwsFormatException);
      expect(
        () => remote.applyRemote(
          SyncRecord(
            collection: bad.collection,
            id: 'x',
            updatedAt: bad.updatedAt,
            deviceId: 'e',
            deleted: false,
            data: data,
          ),
        ),
        throwsFormatException,
      );
    });

    test('moving, scaling, rotating, recolouring and refilling keep the shape', () {
      final rect = shapeStroke(every[2], fill: 0x401C7ED6);
      final t = Affine.rotation(math.pi / 5, pivot: const Offset(70, 60));
      final moved = TransformItems.stroke(rect, t, id: 'b');
      expect(moved.shape, rect.shape!.map(t.apply));
      expect(TransformItems.recolorStroke(rect, 0xFFFF0000, id: 'c').shape, rect.shape);
      expect(TransformItems.refillStroke(rect, null, id: 'd').shape, rect.shape);
      expect(TransformItems.restyleStroke(rect, width: 5, id: 'e').shape, rect.shape);
    });

    test('the pixel eraser leaves free-hand pieces', () {
      final rect = shapeStroke(every[2]);
      final pieces = StrokeSplitter.erase(
        rect,
        const Offset(70, 20),
        const Offset(70, 20),
        4,
        newId: () => 'p${math.Random().nextInt(1 << 30)}',
      );
      expect(pieces, isNotEmpty);
      expect(pieces!.every((p) => p.shape == null), isTrue);
    });

    test('reshaping rebuilds the outline and keeps look and fill', () {
      final rect = shapeStroke(every[2], fill: 0x401C7ED6);
      final bigger = rect.shape!.withPoint(2, const Offset(200, 160));
      final reshaped = ShapeBuilder.reshaped(rect, bigger, id: 'r');
      expect(reshaped.shape, bigger);
      expect(reshaped.fill, 0x401C7ED6);
      expect(reshaped.style, rect.style);
      expect(reshaped.points.any((p) => p.offset == const Offset(200, 160)), isTrue);
    });
  });
}
