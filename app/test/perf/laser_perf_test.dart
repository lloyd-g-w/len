import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/render/laser_painter.dart';
import 'package:len/ink/tools/laser.dart';
import 'package:len/ink/viewport.dart';

import '../content_tools_ui_test.dart' show openCanvas, key;

/// Laser pointer cost: per pointer move in the editor (widgets rebuilt,
/// render objects painted) and per frame for a full trail (record +
/// rasterise), against the previous painter (a blurred line per segment).
void main() {
  testWidgets('laser pointer: a move repaints only the laser', (tester) async {
    await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyK);
    final gesture = await tester.startGesture(
      const Offset(200, 300),
      kind: PointerDeviceKind.mouse,
    );
    // Warm up (the toolbar settles after the tool change).
    for (var i = 0; i < 120; i++) {
      await gesture.moveTo(Offset(200 + i * 3.0, 500));
      await tester.pump(const Duration(milliseconds: 8));
    }
    var rebuilds = 0;
    final painted = <String>[];
    debugOnRebuildDirtyWidget = (e, _) => rebuilds++;
    debugProfilePaintsEnabled = true;
    debugOnProfilePaint = (r) => painted.add(r.runtimeType.toString());
    const moves = 240;
    final watch = Stopwatch()..start();
    for (var i = 0; i < moves; i++) {
      await gesture.moveTo(Offset(200 + i * 3.0, 300 + 100 * math.sin(i / 10)));
      await tester.pump(const Duration(milliseconds: 8));
    }
    watch.stop();
    debugOnRebuildDirtyWidget = null;
    debugOnProfilePaint = null;
    debugProfilePaintsEnabled = false;
    await gesture.up();
    _report(
      'editor: ${(rebuilds / moves).toStringAsFixed(2)} rebuilds/move, '
      '${(painted.length / moves).toStringAsFixed(2)} paints/move, '
      '${(watch.elapsedMicroseconds / moves).toStringAsFixed(0)} µs/move (test harness)',
    );
    expect(rebuilds, 0);
    expect(painted.length, lessThanOrEqualTo(moves + 2));
    expect(painted.toSet(), {'RenderCustomPaint'});
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('laser pointer: frame cost of a full trail', (tester) async {
    // One second of 240 Hz input along a wavy line, half of it faded.
    final viewport = ViewportController();
    final trail = LaserTrail()..down(const Offset(100, 400));
    for (var i = 1; i < 240; i++) {
      trail.move(Offset(100 + i * 4.0, 400 + 150 * math.sin(i / 15)));
      trail.tick(i * 1000 / 240);
    }
    const size = Size(1280, 800);
    Future<int> frame(void Function(Canvas) paint) async {
      final watch = Stopwatch()..start();
      final recorder = ui.PictureRecorder();
      paint(Canvas(recorder));
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.width.toInt(), size.height.toInt());
      watch.stop();
      image.dispose();
      picture.dispose();
      return watch.elapsedMicroseconds;
    }

    Future<double> median(void Function(Canvas) paint) async {
      final times = [for (var i = 0; i < 15; i++) await frame(paint)]..sort();
      return times[times.length ~/ 2] / 1000;
    }

    await tester.runAsync(() async {
      final now = LaserPainter(trail: trail, viewport: viewport);
      final after = await median((c) => now.paint(c, size));
      final before = await median((c) => _legacyPaint(c, trail, viewport));
      final empty = await median((c) {});
      double record(void Function(Canvas) paint) {
        for (var i = 0; i < 50; i++) {
          paint(Canvas(ui.PictureRecorder()));
        }
        final watch = Stopwatch()..start();
        for (var i = 0; i < 100; i++) {
          final r = ui.PictureRecorder();
          paint(Canvas(r));
          r.endRecording().dispose();
        }
        return watch.elapsedMicroseconds / 100 / 1000;
      }

      final recordAfter = record((c) => now.paint(c, size));
      final recordBefore = record((c) => _legacyPaint(c, trail, viewport));
      _report(
        'full trail (${trail.length} points), recording only (debug JIT): '
        'before ${recordBefore.toStringAsFixed(2)} ms, after ${recordAfter.toStringAsFixed(2)} ms',
      );
      _report(
        'full trail (${trail.length} points, rasterised, net of an empty frame): '
        'before ${(before - empty).toStringAsFixed(2)} ms (${2 * trail.length} lines, half '
        'blurred), after ${(after - empty).toStringAsFixed(2)} ms (2 meshes + dot)',
      );
    });
    trail.dispose();
    viewport.dispose();
  });
}

void _report(String line) {
  // ignore: avoid_print
  print('laser perf: $line');
}

/// The painter before the rewrite: two lines per segment, one blurred.
void _legacyPaint(Canvas canvas, LaserTrail trail, ViewportController viewport) {
  const red = Color(0xFFFF2D2D);
  final glow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 12
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  final core = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 4;
  for (var i = 0; i < trail.length; i++) {
    final alpha = trail.alphaAt(i);
    if (alpha <= 0) continue;
    final b = viewport.toScreen(trail.pointAt(i));
    final a = trail.startsAt(i) ? b : viewport.toScreen(trail.pointAt(i - 1));
    glow.color = red.withValues(alpha: 0.55 * alpha);
    core.color = Color.lerp(red, const Color(0xFFFFFFFF), 0.35)!.withValues(alpha: alpha);
    canvas
      ..drawLine(a, b, glow)
      ..drawLine(a, b, core);
  }
}
