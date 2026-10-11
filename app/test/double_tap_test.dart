import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/double_tap_zoom.dart';
import 'package:len/ink/input/canvas_gestures.dart';
import 'package:len/ink/input/double_tap_detector.dart';
import 'package:len/ink/navigation/viewport_animator.dart';
import 'package:len/ink/viewport.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  group('DoubleTapDetector', () {
    late List<Offset> fired;
    late DoubleTapDetector d;
    setUp(() {
      fired = [];
      d = DoubleTapDetector(onDoubleTap: fired.add);
    });

    void tap(int id, Offset at, int t, {int hold = 80, bool eligible = true}) {
      d.down(id, at, ms(t), eligible: eligible);
      d.up(id, at, ms(t + hold));
    }

    test('two quick taps close together fire once, at the second tap', () {
      tap(1, const Offset(100, 100), 0);
      expect(fired, isEmpty);
      tap(2, const Offset(110, 104), 200);
      expect(fired, [const Offset(110, 104)]);
      // A third tap starts over.
      tap(3, const Offset(110, 104), 400);
      expect(fired, hasLength(1));
    });

    test('a slow second tap, a far one or a long press is not a double tap', () {
      tap(1, Offset.zero, 0);
      tap(2, Offset.zero, 80 + 400); // Gap too long.
      expect(fired, isEmpty);
      tap(3, const Offset(200, 0), 600); // Too far from the previous tap.
      expect(fired, isEmpty);
      tap(4, const Offset(200, 0), 800, hold: 400); // Held too long.
      tap(5, const Offset(200, 0), 1300);
      expect(fired, isEmpty);
    });

    test('a moving finger (pan) is not a tap', () {
      tap(1, Offset.zero, 0);
      d.down(2, Offset.zero, ms(150), eligible: true);
      d.move(2, const Offset(40, 0));
      d.up(2, const Offset(40, 0), ms(200));
      expect(fired, isEmpty);
    });

    test('a second finger (two-finger tap undo) never makes a double tap', () {
      tap(1, Offset.zero, 0);
      d.down(2, Offset.zero, ms(150), eligible: true);
      d.down(3, const Offset(80, 0), ms(160), eligible: true);
      d.up(2, Offset.zero, ms(220));
      d.up(3, const Offset(80, 0), ms(230));
      tap(4, Offset.zero, 300);
      expect(fired, isEmpty);
    });

    test('ineligible touches (drawing finger, palm near a pen) are ignored', () {
      tap(1, Offset.zero, 0, eligible: false);
      tap(2, Offset.zero, 150, eligible: false);
      expect(fired, isEmpty);
    });
  });

  group('CanvasGestures double tap', () {
    PointerDownEvent down(int id, int t, {PointerDeviceKind kind = PointerDeviceKind.touch}) =>
        PointerDownEvent(pointer: id, kind: kind, position: const Offset(50, 50), timeStamp: ms(t));
    PointerUpEvent up(int id, int t, {PointerDeviceKind kind = PointerDeviceKind.touch}) =>
        PointerUpEvent(pointer: id, kind: kind, position: const Offset(50, 50), timeStamp: ms(t));

    test('fires for navigating fingers only, not near a stylus', () {
      var count = 0;
      final g = CanvasGestures(onDoubleTap: (_) => count++);
      addTearDown(g.dispose);
      void doubleTap(int t, {required bool navigates}) {
        g.down(down(1, t), navigates: navigates);
        g.up(up(1, t + 50));
        g.down(down(2, t + 150), navigates: navigates);
        g.up(up(2, t + 200));
      }

      doubleTap(0, navigates: false); // Fingers draw: dots, not a zoom.
      expect(count, 0);
      doubleTap(1000, navigates: true);
      expect(count, 1);
      // A pen just lifted: the touches are likely the palm.
      g.down(down(9, 2000, kind: PointerDeviceKind.stylus), navigates: true);
      g.up(up(9, 2100, kind: PointerDeviceKind.stylus));
      doubleTap(2200, navigates: true);
      expect(count, 1);
    });
  });

  group('DoubleTapZoom', () {
    testWidgets('toggles home ⇄ 2× about the tap, then back to the last zoom', (tester) async {
      final viewport = ViewportController()..setSize(const Size(800, 600));
      final animator = ViewportAnimator(viewport);
      addTearDown(animator.dispose);
      final zoom = DoubleTapZoom(viewport: viewport, animator: animator, home: () => 1);
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      const at = Offset(200, 150);
      final world = viewport.toWorld(at);
      zoom.toggle(at);
      await settle();
      expect(viewport.scale, closeTo(2, 1e-6));
      expect(viewport.toScreen(world).dx, closeTo(at.dx, 0.5)); // Tap point stays put.
      // Zoom further by pinching, then double tap: back home …
      viewport.zoomAt(at, 1.5);
      zoom.toggle(at);
      await settle();
      expect(viewport.scale, closeTo(1, 1e-6));
      // … and again: to where it was (3×), not 2×.
      zoom.toggle(at);
      await settle();
      expect(viewport.scale, closeTo(3, 1e-6));
    });
  });
}
