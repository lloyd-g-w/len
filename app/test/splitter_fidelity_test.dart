import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/geometry/stroke_splitter.dart';
import 'package:len/ink/render/stroke_renderer.dart';

void main() {
  test('pixel-erasing the middle leaves the rest of the ink where it was', () {
    for (final tool in [InkTool.ballpoint, InkTool.fountain, InkTool.brush]) {
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
        style: StrokeStyle.defaultsFor(tool).copyWith(streamline: 0.6),
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
      expect(differ / inked, lessThan(0.05), reason: '$tool: $differ of $inked inked samples moved');
    }
  });
}
