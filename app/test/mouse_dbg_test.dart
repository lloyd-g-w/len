import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'support/mouse_writing.dart';

void main() {
  test('dbg', () {
    final paths = straightLines();
    final rec = mouseRecording(paths, model: const MouseModel(hz: 1000, delivery: Delivery.coalesced), speed: 600, pen: penOf(4, 0));
    final replay = ReplayResult.run(rec.recording);
    for (final (k, s) in replay.strokes.indexed) {
      final line = StrokeOutline.centerline(s.points, StrokeRenderer.specFor(s.width, s.style))!;
      final a = paths[k].points.first, b = paths[k].points.last;
      final dir = (b - a) / (b - a).distance;
      var worst = 0.0; var at = 0.0;
      for (var i = 0; i < line.length; i++) {
        final p = Offset(line.x[i], line.y[i]) - a;
        final off = (p.dx * -dir.dy + p.dy * dir.dx).abs();
        if (off > worst) { worst = off; at = p.dx * dir.dx + p.dy * dir.dy; }
      }
      print('line $k: worst ${worst.toStringAsFixed(2)} at ${at.toStringAsFixed(1)} of ${(b - a).distance.toStringAsFixed(0)}; events ${[for (final e in rec.events[k].take(4)) e.position]}');
    }
  });
}
