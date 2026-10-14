import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/geometry/stroke_splitter.dart';
import 'package:len/ink/stroke_hit_test.dart';

import 'support/property.dart';

/// A stroke and an eraser sweep near it.
typedef _Case = ({Stroke stroke, Offset a, Offset b, double radius});

Stroke _randomStroke(math.Random r, {String id = 'o'}) {
  final tool = Gens.oneOf(InkTool.values)(r);
  var at = Offset(r.nextDouble() * 200, r.nextDouble() * 200);
  var heading = r.nextDouble() * 2 * math.pi;
  final n = Gens.intIn(1, 40)(r);
  final points = <StrokePoint>[];
  for (var i = 0; i < n; i++) {
    points.add(StrokePoint(at.dx, at.dy, 0.05 + r.nextDouble() * 0.95));
    heading += (r.nextDouble() - 0.5) * 1.5;
    final step = r.nextBool() ? r.nextDouble() * 3 : r.nextDouble() * 30;
    at += Offset(math.cos(heading), math.sin(heading)) * step;
  }
  final defaults = StrokeStyle.defaultsFor(tool);
  return Stroke(
    id: id,
    surfaceId: 's',
    tool: tool,
    color: 0xFF000000 | r.nextInt(0xFFFFFF),
    width: 0.5 + r.nextDouble() * 12,
    points: points,
    createdAt: r.nextInt(1000),
    style: r.nextBool()
        ? defaults
        : defaults.copyWith(streamline: r.nextDouble(), unit: 0.5 + r.nextDouble() * 2),
  );
}

_Case _case(math.Random r) {
  final stroke = _randomStroke(r);
  // Mostly across the stroke; sometimes a tap, sometimes anywhere.
  final p = stroke.points[r.nextInt(stroke.points.length)].offset;
  Offset near() => p + Offset(r.nextDouble() * 60 - 30, r.nextDouble() * 60 - 30);
  final a = r.nextDouble() < 0.2 ? Offset(r.nextDouble() * 300, r.nextDouble() * 300) : near();
  final b = r.nextDouble() < 0.2 ? a : near();
  return (stroke: stroke, a: a, b: b, radius: 0.5 + r.nextDouble() * 20);
}

String _describe(_Case c) =>
    'eraser ${c.a} → ${c.b} r=${c.radius}\n${c.stroke.tool} w=${c.stroke.width} '
    '${c.stroke.style}\n${[for (final p in c.stroke.points) '(${p.x}, ${p.y}, ${p.pressure})']}';

double _distToSweep(Offset p, _Case c) => math.sqrt(StrokeHitTest.segmentDistSq(p, p, c.a, c.b));

/// Distance from [p] to the polyline of [points].
double _distToLine(Offset p, List<StrokePoint> points) {
  if (points.length == 1) return (p - points.single.offset).distance;
  var best = double.infinity;
  for (var i = 1; i < points.length; i++) {
    final d = StrokeHitTest.segmentDistSq(p, p, points[i - 1].offset, points[i].offset);
    best = math.min(best, d);
  }
  return math.sqrt(best);
}

List<Stroke>? _erase(_Case c, [Stroke? stroke]) {
  var n = 0;
  return StrokeSplitter.erase(stroke ?? c.stroke, c.a, c.b, c.radius, newId: () => 'f${n++}');
}

void main() {
  test('an eraser that misses the ink changes nothing', () async {
    await forAll(
      (r) {
        final c = _case(r);
        // Moved well away: beyond the eraser and the widest ink.
        final left = math.min(c.a.dx, c.b.dx) - c.radius;
        final away = Offset(c.stroke.bounds.right - left + c.stroke.width + r.nextDouble(), 0);
        return (stroke: c.stroke, a: c.a + away, b: c.b + away, radius: c.radius);
      },
      (c) => expect(_erase(c), isNull),
      runs: 300,
      describe: _describe,
    );
  });

  test('pieces lie on the original line and keep its look', () async {
    await forAll(
      _case,
      (c) {
        final pieces = _erase(c);
        if (pieces == null) return;
        final s = c.stroke;
        final ids = <String>{};
        for (final piece in pieces) {
          expect(ids.add(piece.id), isTrue, reason: 'ids are fresh');
          expect(piece.id, isNot(s.id));
          expect(piece.points.length, greaterThanOrEqualTo(2));
          expect(piece.tool, s.tool);
          expect(piece.color, s.color);
          expect(piece.width, s.width);
          expect(piece.createdAt, s.createdAt);
          expect(piece.surfaceId, s.surfaceId);
          final st = piece.style, so = s.style;
          expect(
            [st.opacity, st.thinning, st.streamline, st.ends],
            [so.opacity, so.thinning, so.streamline, so.ends],
          );
          if (so.unit > 0) expect(st.unit, so.unit);
          final pressures = [for (final p in s.points) p.pressure];
          for (final p in piece.points) {
            expect(_distToLine(p.offset, s.points), lessThan(1e-6), reason: '$p off the line');
            expect(p.pressure, inInclusiveRange(0, 1));
            if (p != piece.points.first) {
              expect(p.pressure, inInclusiveRange(pressures.reduce(math.min) - 1e-9, 1));
              expect(p.pressure, lessThanOrEqualTo(pressures.reduce(math.max) + 1e-9));
            }
          }
        }
      },
      runs: 400,
      describe: _describe,
    );
  });

  test('no piece keeps ink under the eraser', () async {
    await forAll(
      _case,
      (c) {
        final pieces = _erase(c);
        if (pieces == null) return;
        for (final piece in pieces) {
          for (final p in piece.points) {
            // A cut start's pressure is reset to match the ink there, so
            // only its position is checked against the eraser itself.
            final reach =
                c.radius + (p == piece.points.first ? 0 : StrokeHitTest.inkRadius(c.stroke, p));
            expect(_distToSweep(p.offset, c), greaterThan(reach - 1e-9), reason: '$p survived');
          }
        }
      },
      runs: 400,
      describe: _describe,
    );
  });

  test('ink clear of the eraser survives', () async {
    await forAll(
      _case,
      (c) {
        final pieces = _erase(c);
        final s = c.stroke;
        if (pieces == null) {
          // Nothing erased: no point was within reach.
          for (final p in s.points) {
            final reach = c.radius + StrokeHitTest.inkRadius(s, p);
            expect(_distToSweep(p.offset, c), greaterThan(reach - 1e-9));
          }
          return;
        }
        if (s.points.length == 1) return expect(pieces, isEmpty);
        // Beyond the eraser, the widest ink and one densifying step from the
        // cut, every input point is kept, in exactly one piece.
        final clear = c.radius + s.width + c.radius / 2 + 0.5;
        final kept = [for (final piece in pieces) ...piece.points.map((p) => (p.x, p.y))];
        for (final p in s.points) {
          if (_distToSweep(p.offset, c) <= clear) continue;
          expect(kept.where((k) => k == (p.x, p.y)), isNotEmpty, reason: '$p lost');
        }
      },
      runs: 400,
      describe: _describe,
    );
  });

  // A piece's cut start takes the pressure of the ink drawn there (see
  // `StrokeSplitter._settledStart`), which may be wider than the raw input
  // the cut was judged by, so the same sweep may trim that start a little
  // more (deliberate). It settles within a few rounds and never cuts a
  // piece in two or touches its far end.
  test('erasing the pieces again with the same sweep at most trims their cut start', () async {
    await forAll(
      _case,
      (c) {
        final pieces = _erase(c);
        if (pieces == null) return;
        for (var piece in pieces) {
          final start = piece.points.first.offset, end = piece.points.last;
          var rounds = 0;
          for (var again = _erase(c, piece); again != null; again = _erase(c, piece)) {
            expect(++rounds, lessThanOrEqualTo(4), reason: 'does not settle');
            expect(again.length, lessThanOrEqualTo(1), reason: 'piece cut in two');
            if (again.isEmpty) break;
            piece = again.single;
            expect(piece.points.last, end, reason: 'far end trimmed');
          }
          expect(
            (piece.points.first.offset - start).distance,
            lessThanOrEqualTo(c.radius + c.stroke.width),
          );
        }
      },
      runs: 400,
      describe: _describe,
    );
  });

  test('a drag cuts like its segments; dragging again only trims cut starts', () async {
    await forAll(
      (r) {
        final c = _case(r);
        final path = [c.a];
        for (var i = Gens.intIn(1, 6)(r); i > 0; i--) {
          path.add(path.last + Offset(r.nextDouble() * 40 - 20, r.nextDouble() * 40 - 20));
        }
        return (stroke: c.stroke, path: path, radius: c.radius);
      },
      (c) {
        var n = 0;
        List<Stroke> drag(List<Stroke> strokes) {
          for (var i = 1; i < c.path.length; i++) {
            final a = c.path[i - 1], b = c.path[i];
            strokes = [
              for (final s in strokes)
                ...StrokeSplitter.erase(s, a, b, c.radius, newId: () => 'd${n++}') ?? [s],
            ];
          }
          return strokes;
        }

        final once = drag([c.stroke]);
        for (final s in once) {
          for (final p in s.points.skip(s == c.stroke ? 0 : 1)) {
            for (var i = 1; i < c.path.length; i++) {
              final d = StrokeHitTest.segmentDistSq(p.offset, p.offset, c.path[i - 1], c.path[i]);
              final reach = c.radius + StrokeHitTest.inkRadius(s, p);
              expect(math.sqrt(d), greaterThan(reach - 1e-9), reason: '$p survived');
            }
          }
        }
        final twice = drag(once);
        expect(twice.length, lessThanOrEqualTo(once.length));
        final ends = {for (final s in once) s.points.last};
        for (final s in twice) {
          expect(ends, contains(s.points.last), reason: 'a piece cut in two');
        }
      },
      runs: 200,
      describe: (c) => '${c.path} r=${c.radius}\n${c.stroke.points}',
    );
  });
}
