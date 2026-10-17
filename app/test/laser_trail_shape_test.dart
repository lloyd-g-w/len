import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/laser_painter.dart';
import 'package:len/ink/render/laser_ribbon.dart';
import 'package:len/ink/render/laser_strokes.dart';
import 'package:len/ink/tools/laser.dart';
import 'package:len/ink/viewport.dart';

/// The laser trail drawn through the pen's engine: its ends, pressure
/// sensitivity and stabiliser show; strokes are shaped once and kept
/// between frames.
void main() {
  /// A straight trail from (60, 50) to (260, 50), drawn and held (so it
  /// shows in full), pressed hard in the middle.
  LaserTrail straight(LaserConfig config, {bool lift = true}) {
    final trail = LaserTrail()..config = config.copyWith(fade: LaserFade.pause);
    const n = 80;
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final p = Offset(60 + 200 * t, 50);
      final pressure = 0.1 + 0.9 * math.sin(t * math.pi);
      i == 0 ? trail.down(p, pressure: pressure) : trail.move(p, pressure: pressure);
      trail.tick(t * 500);
    }
    if (lift) {
      trail
        ..up()
        ..tick(500);
    }
    return trail;
  }

  /// The trail painted without its dot, as RGBA rows 320 × 100.
  Future<_Pixels> paint(WidgetTester tester, LaserTrail trail) async {
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    addTearDown(trail.dispose);
    // The dot would cover the end: paint after it has gone.
    trail.hover(null);
    late _Pixels pixels;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final glow = LaserRibbon.glow()..color = const Color(0xFFFF0000);
      final core = LaserRibbon.core()..color = const Color(0xFFFF0000);
      LaserStrokes()
        ..sync(trail, viewport.scale)
        ..emit(glow, core, trail, glowScale: LaserPainter.glowScale, scale: viewport.scale);
      glow.draw(canvas);
      core.draw(canvas);
      final image = await recorder.endRecording().toImage(320, 100);
      final data = await image.toByteData();
      pixels = _Pixels(data!.buffer.asUint8List(), 320);
      image.dispose();
    });
    return pixels;
  }

  const size = 10; // The core's width (the third default size).
  const config = LaserConfig(sizeIndex: 2);

  testWidgets('flat ends stop at the end points; round ones reach half a width past', (
    tester,
  ) async {
    final flat = await paint(tester, straight(config));
    final round = await paint(tester, straight(config.copyWith(ends: const PenEnds())));
    // Inside the line both are solid.
    expect(flat.alpha(160, 50), greaterThan(200));
    expect(round.alpha(160, 50), greaterThan(200));
    // A few pixels past each end only the round cap covers.
    for (final x in [263, 57]) {
      expect(round.alpha(x, 50), greaterThan(flat.alpha(x, 50) + 80), reason: 'x $x');
    }
    expect(flat.alpha(260 + size, 50), lessThan(40), reason: 'only the faint glow');
  });

  testWidgets('tapered ends narrow to a point; the start only with taper at start', (tester) async {
    final flat = await paint(tester, straight(config));
    const tapered = PenEnds(style: StrokeEnds.tapered, taperLength: 4);
    final both = await paint(tester, straight(config.copyWith(ends: tapered)));
    final start = await paint(
      tester,
      straight(config.copyWith(ends: tapered.copyWith(taperAt: TaperAt.start))),
    );
    // Near the ends, the tapered core is narrower than the flat one.
    expect(both.coreWidth(66), lessThan(flat.coreWidth(66) - 2));
    expect(both.coreWidth(254), lessThan(flat.coreWidth(254) - 2));
    expect(start.coreWidth(66), lessThan(flat.coreWidth(66) - 2));
    expect(start.coreWidth(254), closeTo(flat.coreWidth(254), 1), reason: 'end untapered');
    // The middle is as wide as ever.
    expect(both.coreWidth(160), closeTo(flat.coreWidth(160), 1));
  });

  testWidgets('pressure varies the width only with pressure sensitivity on', (tester) async {
    final off = await paint(tester, straight(config));
    final on = await paint(tester, straight(config.copyWith(thinning: 1)));
    // Off: one width all along, whatever the pressure.
    expect(off.coreWidth(80), closeTo(off.coreWidth(160), 1));
    // On: wide where pressed hard (the middle), thin where light.
    expect(on.coreWidth(160), greaterThan(off.coreWidth(160) + 2));
    expect(on.coreWidth(80), lessThan(on.coreWidth(160) - 3));
  });

  testWidgets('the stabiliser smooths a shaky trail', (tester) async {
    LaserTrail shaky(double streamline) {
      final trail = LaserTrail()
        ..config = config.copyWith(fade: LaserFade.pause, streamline: streamline);
      for (var i = 0; i <= 100; i++) {
        final p = Offset(60 + 2.0 * i, 50 + (i.isEven ? 1.5 : -1.5));
        i == 0 ? trail.down(p) : trail.move(p);
        trail.tick(i * 5.0);
      }
      return trail
        ..up()
        ..tick(600);
    }

    double wobble(LaserTrail trail) {
      final stroke = (LaserStrokes()..sync(trail, 1)).strokes.single..update();
      final ys = stroke.shaper.y.toList();
      var sum = 0.0;
      for (var i = ys.length ~/ 4; i < ys.length * 3 ~/ 4; i++) {
        sum += (ys[i] - 50).abs();
      }
      trail.dispose();
      return sum / (ys.length / 2);
    }

    expect(wobble(shaky(1)), lessThan(wobble(shaky(0)) / 2));
  });

  group('LaserStrokes', () {
    test('shapes each stroke once and feeds it only new points', () {
      final trail = LaserTrail()..config = config;
      addTearDown(trail.dispose);
      final strokes = LaserStrokes();
      trail.down(Offset.zero);
      for (var i = 1; i < 20; i++) {
        trail.move(Offset(i * 3.0, 0));
      }
      trail.tick(0);
      strokes.sync(trail, 1);
      expect(strokes.length, 1);
      trail
        ..up()
        ..down(const Offset(0, 40))
        ..move(const Offset(30, 40))
        ..tick(10);
      strokes.sync(trail, 1);
      expect(strokes.length, 2);
      // A frame that only fades adds nothing.
      trail.tick(200);
      strokes.sync(trail, 1);
      expect(strokes.length, 2);
      // Expired strokes go.
      trail.tick(5000);
      strokes.sync(trail, 1);
      expect(strokes.length, 0);
    });

    test('a long press keeps only the showing part of its stroke (rebased)', () {
      final trail = LaserTrail()..config = config.copyWith(duration: const Duration(seconds: 1));
      addTearDown(trail.dispose);
      final strokes = LaserStrokes();
      final glow = LaserRibbon.glow(), core = LaserRibbon.core();
      trail.down(Offset.zero);
      // 20 s at 240 Hz along a circle, frames at 60 Hz.
      for (var i = 1; i < 4800; i++) {
        final a = i / 200;
        trail.move(Offset(300 + 200 * math.cos(a), 300 + 200 * math.sin(a)));
        if (i % 4 == 0) {
          trail.tick(i * 1000 / 240);
          strokes
            ..sync(trail, 1)
            ..emit(glow, core, trail, glowScale: 2.4, scale: 1);
        }
      }
      expect(strokes.length, 1);
      expect(
        strokes.strokes.single.shaper.inputCount,
        lessThan(1500),
        reason: 'not the 4800 points drawn',
      );
    });
  });
}

class _Pixels {
  _Pixels(this.rgba, this.width);

  final Uint8List rgba;
  final int width;

  int alpha(int x, int y) => rgba[(y * width + x) * 4 + 3];

  /// Rows around y = 50 at column [x] whose opacity is the core's (above
  /// what the glow alone reaches).
  int coreWidth(int x) {
    var n = 0;
    for (var y = 20; y < 80; y++) {
      if (alpha(x, y) > 200) n++;
    }
    return n;
  }
}
