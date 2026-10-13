import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/ink/input/canvas_gestures.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/navigation/kinetic_pan.dart';
import 'package:len/ink/navigation/viewport_animator.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

import 'canvas_gestures_test.dart' show down, move, up, ms;

/// How navigation feels, measured: the input controller fed with real
/// gesture sequences (timed events), on a plain viewport with inertia.
void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late ViewportController viewport;
  late ViewportAnimator animator;
  late ToolSettings tools;
  late InkInputController input;
  late List<int> taps;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    viewport = ViewportController(minScale: 0.25, maxScale: 4)..setSize(const Size(800, 600));
    animator = ViewportAnimator(viewport);
    tools = ToolSettings(stylusOnly: true);
    taps = [];
    input = InkInputController(
      model: model,
      viewport: viewport,
      tools: tools,
      live: LiveInk(),
      kinetic: KineticPan(animator),
      gestures: CanvasGestures(onMultiFingerTap: taps.add),
    );
  });

  tearDown(() {
    animator.dispose();
    model.dispose();
    db.close();
  });

  /// Two fingers at [a] and [b] moving to [a2] and [b2] in [steps] frames
  /// of 8 ms, from time [t0] (ms). Returns the end time.
  int twoFingers(Offset a, Offset b, Offset a2, Offset b2, {int steps = 20, int t0 = 0}) {
    input
      ..handleDown(down(1, a, t: t0))
      ..handleDown(down(2, b, t: t0));
    var t = t0;
    for (var i = 1; i <= steps; i++) {
      t += 8;
      input
        ..handleMove(move(1, Offset.lerp(a, a2, i / steps)!, t: t))
        ..handleMove(move(2, Offset.lerp(b, b2, i / steps)!, t: t));
    }
    return t;
  }

  group('pinch', () {
    testWidgets('keeps the point under the fingers under the fingers', (tester) async {
      const a = Offset(300, 300), b = Offset(500, 300);
      input
        ..handleDown(down(1, a))
        ..handleDown(down(2, b));
      var t = 0;
      Offset at(int i, int finger) =>
          (finger == 1 ? a : b) + Offset((finger == 1 ? -6.0 : 6.0) * i, 3.0 * i);
      // Past any slop first.
      for (var i = 1; i <= 6; i++) {
        t += 8;
        input
          ..handleMove(move(1, at(i, 1), t: t))
          ..handleMove(move(2, at(i, 2), t: t));
      }
      final centre = (at(6, 1) + at(6, 2)) / 2;
      final world = viewport.toWorld(centre);
      for (var i = 7; i <= 30; i++) {
        t += 8;
        input
          ..handleMove(move(1, at(i, 1), t: t))
          ..handleMove(move(2, at(i, 2), t: t));
      }
      final end = (at(30, 1) + at(30, 2)) / 2;
      expect(viewport.scale, greaterThan(1.5));
      expect((viewport.toScreen(world) - end).distance, lessThan(0.5));
    });

    testWidgets('a second finger landing or a finger lifting never jumps the view', (tester) async {
      input
        ..handleDown(down(1, const Offset(300, 300)))
        ..handleMove(move(1, const Offset(340, 300), t: 10))
        ..handleMove(move(1, const Offset(380, 300), t: 20));
      final panned = viewport.offset;
      input.handleDown(down(2, const Offset(600, 300), t: 30));
      expect(viewport.offset, panned);
      expect(viewport.scale, 1);
      // Pinch out.
      for (var i = 1; i <= 10; i++) {
        input.handleMove(move(2, Offset(600 + 10.0 * i, 300), t: 30 + 8 * i));
      }
      final pinched = (viewport.offset, viewport.scale);
      input.handleUp(up(2, const Offset(700, 300), t: 120));
      expect((viewport.offset, viewport.scale), pinched);
      // The remaining finger pans exactly by what it moves.
      input.handleMove(move(1, const Offset(390, 305), t: 130));
      expect(viewport.offset - pinched.$1, const Offset(10, 5));
      expect(viewport.scale, pinched.$2);
    });

    testWidgets('a two-finger pan does not zoom, even with jittering fingers', (tester) async {
      input
        ..handleDown(down(1, const Offset(300, 300)))
        ..handleDown(down(2, const Offset(420, 300)));
      for (var i = 1; i <= 20; i++) {
        final jitter = i.isEven ? 1.5 : -1.5;
        input
          ..handleMove(move(1, Offset(300, 300 + 12.0 * i), t: 8 * i))
          ..handleMove(move(2, Offset(420 + jitter, 300 + 12.0 * i), t: 8 * i));
      }
      expect(viewport.scale, 1);
      expect(viewport.offset.dy, greaterThan(200));
    });

    testWidgets('a two-finger pan flings', (tester) async {
      input
        ..handleDown(down(1, const Offset(300, 300)))
        ..handleDown(down(2, const Offset(420, 300)));
      for (var i = 1; i <= 20; i++) {
        final jitter = i.isEven ? 1.0 : -1.0;
        input
          ..handleMove(move(1, Offset(300, 300 + 12.0 * i), t: 8 * i))
          ..handleMove(move(2, Offset(420 + jitter, 300 + 12.0 * i), t: 8 * i));
      }
      input
        ..handleUp(up(1, const Offset(300, 540), t: 165))
        ..handleUp(up(2, const Offset(420, 540), t: 166));
      expect(animator.isAnimating, isTrue);
      await tester.pumpAndSettle();
    });
  });

  group('fling', () {
    testWidgets('glides at the finger\'s speed, slows down, stops on touch', (tester) async {
      // 1500 px/s: 12 px every 8 ms.
      input.handleDown(down(1, const Offset(400, 500)));
      for (var i = 1; i <= 15; i++) {
        input.handleMove(move(1, Offset(400, 500 - 12.0 * i), t: 8 * i));
      }
      input.handleUp(up(1, const Offset(400, 320), t: 124));
      expect(animator.isAnimating, isTrue);
      final released = viewport.offset.dy;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final first = viewport.offset.dy;
      await tester.pump(const Duration(milliseconds: 20));
      final speed = (viewport.offset.dy - first) / 0.02;
      expect(speed, closeTo(-1500, 150));
      await tester.pump(const Duration(milliseconds: 200));
      final later = viewport.offset.dy;
      await tester.pump(const Duration(milliseconds: 20));
      expect((viewport.offset.dy - later) / 0.02, greaterThan(speed)); // slower
      expect(released - viewport.offset.dy, lessThan(750)); // still gliding
      // A finger landing catches it, and doesn't move the page by itself.
      input.handleDown(down(2, const Offset(400, 400), t: 500));
      final caught = viewport.offset;
      await tester.pump(const Duration(milliseconds: 100));
      input.handleUp(up(2, const Offset(400, 400), t: 560));
      await tester.pumpAndSettle();
      expect(viewport.offset, caught);
    });
  });

  group('limits', () {
    testWidgets('zoom gives way past the limit and springs back', (tester) async {
      // 4× is the limit: pinch 8×.
      viewport.setView(scale: 3, offset: Offset.zero);
      final end = twoFingers(
        const Offset(380, 300),
        const Offset(420, 300),
        const Offset(80, 300),
        const Offset(720, 300),
      );
      expect(viewport.scale, greaterThan(4));
      expect(viewport.scale, lessThan(4 * ViewportController.stretch));
      final focal = viewport.toWorld(const Offset(400, 300));
      input
        ..handleUp(up(1, const Offset(80, 300), t: end + 5))
        ..handleUp(up(2, const Offset(720, 300), t: end + 6));
      await tester.pumpAndSettle();
      expect(viewport.scale, 4);
      expect((viewport.toScreen(focal) - const Offset(400, 300)).distance, lessThan(0.5));
    });
  });

  group('taps', () {
    testWidgets('a two-finger tap with wobbling fingers never moves the view', (tester) async {
      input
        ..handleDown(down(1, const Offset(300, 300)))
        ..handleDown(down(2, const Offset(400, 300), t: 15))
        ..handleMove(move(1, const Offset(305, 304), t: 40))
        ..handleMove(move(2, const Offset(396, 297), t: 50))
        ..handleUp(up(1, const Offset(306, 304), t: 110))
        ..handleUp(up(2, const Offset(396, 297), t: 120));
      expect(taps, [2]);
      expect(viewport.offset, Offset.zero);
      expect(viewport.scale, 1);
    });

    testWidgets('a quick, small pinch zooms and does not undo', (tester) async {
      final end = twoFingers(
        const Offset(300, 300),
        const Offset(400, 300),
        const Offset(285, 300),
        const Offset(415, 300),
        steps: 10,
      );
      input
        ..handleUp(up(1, const Offset(285, 300), t: end + 10))
        ..handleUp(up(2, const Offset(415, 300), t: end + 10));
      expect(viewport.scale, greaterThan(1));
      expect(taps, isEmpty);
    });
  });

  group('palm', () {
    void penStroke(int t) {
      const k = PointerDeviceKind.stylus;
      input
        ..handleDown(down(9, const Offset(100, 100), kind: k, t: t))
        ..handleMove(move(9, const Offset(140, 100), kind: k, t: t + 20))
        ..handleUp(up(9, const Offset(140, 100), kind: k, t: t + 40));
    }

    testWidgets('a palm landing between pen strokes neither pans nor draws', (tester) async {
      for (final fingersDraw in [false, true]) {
        tools.stylusOnly = !fingersDraw;
        penStroke(1000);
        input
          ..handleDown(down(5, const Offset(500, 400), t: 1150))
          ..handleMove(move(5, const Offset(560, 380), t: 1180))
          ..handleMove(move(5, const Offset(620, 380), t: 1210))
          ..handleUp(up(5, const Offset(620, 380), t: 1240));
        expect(viewport.offset, Offset.zero, reason: 'fingers draw: $fingersDraw');
      }
      expect(model.loadedStrokeCount, 2); // The pen's strokes only.
    });

    testWidgets('the stylus never pans', (tester) async {
      const k = PointerDeviceKind.stylus;
      input.handleDown(down(9, const Offset(100, 100), kind: k));
      for (var i = 1; i < 10; i++) {
        input.handleMove(move(9, Offset(100 + 30.0 * i, 100), kind: k, t: 8 * i));
      }
      input.handleUp(up(9, const Offset(370, 100), kind: k, t: 90));
      expect(viewport.offset, Offset.zero);
    });

    testWidgets('fingers navigate again once the pen is away', (tester) async {
      penStroke(1000);
      input
        ..handleDown(down(5, const Offset(500, 400), t: 2000))
        ..handleMove(move(5, const Offset(560, 400), t: 2030))
        ..handleMove(move(5, const Offset(600, 400), t: 2060));
      expect(viewport.offset.dx, greaterThan(20));
    });
  });

  group('trackpad', () {
    PointerPanZoomStartEvent start(Offset at) =>
        PointerPanZoomStartEvent(pointer: 7, position: at, timeStamp: Duration.zero);
    PointerPanZoomUpdateEvent update(Offset at, Offset pan, Offset delta, double scale, int t) =>
        PointerPanZoomUpdateEvent(
          pointer: 7,
          position: at,
          pan: pan,
          panDelta: delta,
          scale: scale,
          timeStamp: ms(t),
        );

    testWidgets('pinch zooms about the cursor to exactly the gesture scale', (tester) async {
      const cursor = Offset(250, 180);
      final world = viewport.toWorld(cursor);
      input.handlePanZoomStart(start(cursor));
      for (var i = 1; i <= 20; i++) {
        input.handlePanZoomUpdate(update(cursor, Offset.zero, Offset.zero, 1 + 0.05 * i, 8 * i));
      }
      expect(viewport.scale, closeTo(2, 1e-9));
      expect((viewport.toScreen(world) - cursor).distance, lessThan(1e-6));
    });

    testWidgets('pans, glides after lifting, and a touch stops the glide', (tester) async {
      const cursor = Offset(400, 300);
      input.handlePanZoomStart(start(cursor));
      for (var i = 1; i <= 10; i++) {
        input.handlePanZoomUpdate(
          update(cursor, Offset(0, -20.0 * i), const Offset(0, -20), 1, 8 * i),
        );
      }
      expect(viewport.offset, const Offset(0, -200));
      input.handlePanZoomEnd(
        PointerPanZoomEndEvent(pointer: 7, position: cursor, timeStamp: ms(85)),
      );
      expect(animator.isAnimating, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Fingers back on the trackpad stop it.
      input.handleSignal(PointerScrollInertiaCancelEvent(position: cursor));
      expect(animator.isAnimating, isFalse);
    });
  });

  group('wheel', () {
    testWidgets('Ctrl+wheel zooms about the cursor, in sane steps', (tester) async {
      const cursor = Offset(600, 120);
      final world = viewport.toWorld(cursor);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      input.handleSignal(const PointerScrollEvent(position: cursor, scrollDelta: Offset(0, -100)));
      final notch = viewport.scale;
      expect(notch, inInclusiveRange(1.1, 1.3));
      expect((viewport.toScreen(world) - cursor).distance, lessThan(1e-6));
      // A violent spin is not a 100× jump.
      input.handleSignal(const PointerScrollEvent(position: cursor, scrollDelta: Offset(0, -3000)));
      expect(viewport.scale / notch, lessThanOrEqualTo(2));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('the wheel scrolls by its delta and stops a glide', (tester) async {
      input.handleSignal(
        const PointerScrollEvent(position: Offset(400, 300), scrollDelta: Offset(0, 53)),
      );
      expect(viewport.offset, const Offset(0, -53));
      animator.fling(const Offset(0, 2000));
      input.handleSignal(
        const PointerScrollEvent(position: Offset(400, 300), scrollDelta: Offset(0, 53)),
      );
      expect(animator.isAnimating, isFalse);
    });
  });
}
