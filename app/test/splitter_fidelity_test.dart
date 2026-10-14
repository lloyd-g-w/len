import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/geometry/stroke_splitter.dart';
import 'package:len/ink/render/centerline.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

void main() {
  test('pixel-erasing the middle leaves the rest of the ink where it was', () {
    for (final tool in InkTool.values) {
      // A wavy, sparsely sampled stroke with a strong stabiliser.
      final original = Stroke(
        id: 'o',
        surfaceId: 's',
        tool: tool,
        color: 0xFF000000,
        width: 6,
        points: [
          for (var x = 0.0; x <= 300; x += 6)
            StrokePoint(x, 30 * math.sin(x / 25), 0.4 + 0.3 * math.sin(x / 40).abs()),
        ],
        createdAt: 1,
        // Written at 100 % (pen strokes record it).
        style: StrokeStyle.defaultsFor(tool).copyWith(streamline: 0.6, unit: 1),
      );
      var n = 0;
      final parts = StrokeSplitter.erase(
        original,
        const Offset(150, -60),
        const Offset(150, 60),
        8,
        newId: () => 'f${n++}',
      )!;
      expect(parts, hasLength(2));
      final before = StrokeRenderer.pathOf(original);
      // Compare coverage away from the cut and the original ends.
      var differ = 0, inked = 0;
      for (var x = 20.0; x <= 280; x += 0.5) {
        if ((x - 150).abs() < 40) continue;
        for (var y = -45.0; y <= 45; y += 0.5) {
          final p = Offset(x, y);
          final a = before.contains(p);
          final b = parts.any((s) => StrokeRenderer.pathOf(s).contains(p));
          if (a) inked++;
          if (a != b) differ++;
        }
      }
      expect(
        differ / inked,
        lessThan(0.02),
        reason: '$tool: $differ of $inked inked samples moved',
      );
    }
  });

  test('fragments are resampled where the original was, also when cut again', () {
    // Wavy, sparsely sampled, varying pressure, stabiliser 0.4.
    final original = Stroke(
      id: 'o',
      surfaceId: 's',
      tool: InkTool.ballpoint,
      color: 0xFF000000,
      width: 2,
      points: [
        for (var x = 0.0; x <= 300; x += 2.5)
          StrokePoint(x, 20 * math.sin(x / 9), 0.3 + 0.4 * math.sin(x / 17).abs()),
      ],
      createdAt: 1,
      style: const StrokeStyle(thinning: 0.6, streamline: 0.4, unit: 1),
    );
    var n = 0;
    String newId() => 'f${n++}';
    final first = StrokeSplitter.erase(
      original,
      const Offset(100, -30),
      const Offset(100, 30),
      3,
      newId: newId,
    )!;
    final again = StrokeSplitter.erase(
      first[1],
      const Offset(200, -30),
      const Offset(200, 30),
      3,
      newId: newId,
    )!;
    final parts = [first[0], ...again];
    expect(parts, hasLength(3));
    expect([for (final p in parts) p.style.startPhase > 0], [false, true, true]);
    expect([for (final p in parts) p.style.cutEnd], [true, true, false]);

    Centerline line(Stroke s) =>
        StrokeOutline.centerline(s.points, StrokeRenderer.specFor(s.width, s.style))!;
    final whole = line(original);
    // Every sample of a fragment farther than 25 units from a cut is one of
    // the original's: same place, same radius.
    var compared = 0;
    for (final part in parts) {
      final l = line(part);
      for (var i = 0; i < l.length; i++) {
        if ((l.x[i] - 100).abs() < 25 || (l.x[i] - 200).abs() < 25) continue;
        var best = double.infinity, at = 0;
        for (var j = 0; j < whole.length; j++) {
          final d = math.pow(l.x[i] - whole.x[j], 2) + math.pow(l.y[i] - whole.y[j], 2);
          if (d < best) {
            best = d.toDouble();
            at = j;
          }
        }
        expect(math.sqrt(best), lessThan(1e-9), reason: 'sample $i of ${part.id}');
        expect((l.r[i] - whole.r[at]).abs(), lessThan(1e-6), reason: 'radius $i of ${part.id}');
        compared++;
      }
    }
    expect(compared, greaterThan(500));
  });

  test('a cut end is not a pen hook', () {
    // Straight to (50, 0), then a sharp turn down: cut just before the
    // turn, the piece's start looks like a pen-down hook.
    final original = Stroke(
      id: 'o',
      surfaceId: 's',
      tool: InkTool.ballpoint,
      color: 0xFF000000,
      width: 2,
      points: [
        for (var x = 0.0; x <= 50; x += 0.5) StrokePoint(x, 0, 0.5),
        for (var y = 0.5; y <= 40; y += 0.5) StrokePoint(50, y, 0.5),
      ],
      createdAt: 1,
      style: const StrokeStyle(unit: 1),
    );
    final parts = StrokeSplitter.erase(
      original,
      const Offset(46, -5),
      const Offset(46, 5),
      1,
      newId: () => 'f',
    )!;
    final piece = parts[1];
    Centerline line(StrokeStyle style) =>
        StrokeOutline.centerline(piece.points, StrokeRenderer.specFor(piece.width, style))!;
    // As a pen stroke, its start would be trimmed; as a cut, it is kept.
    expect(line(piece.style.copyWith(startPhase: 0)).x[0], 50);
    expect(line(piece.style).x[0], closeTo(piece.points.first.x, 1e-9));
    expect(piece.points.first.x, inInclusiveRange(48, 49));
  });
}
