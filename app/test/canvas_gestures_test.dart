import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/canvas_gestures.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/long_press_detector.dart';
import 'package:len/ink/input/multi_finger_tap.dart';
import 'package:len/ink/input/stylus_buttons.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';

Duration ms(int v) => Duration(milliseconds: v);

PointerDownEvent down(
  int id,
  Offset at, {
  int t = 0,
  PointerDeviceKind kind = PointerDeviceKind.touch,
  int buttons = kPrimaryButton,
}) => PointerDownEvent(
  pointer: id,
  kind: kind,
  position: at,
  timeStamp: ms(t),
  buttons: buttons,
  pressure: 0.5,
);

PointerMoveEvent move(
  int id,
  Offset at, {
  int t = 0,
  PointerDeviceKind kind = PointerDeviceKind.touch,
  int buttons = kPrimaryButton,
}) => PointerMoveEvent(
  pointer: id,
  kind: kind,
  position: at,
  timeStamp: ms(t),
  buttons: buttons,
  pressure: 0.5,
);

PointerUpEvent up(
  int id,
  Offset at, {
  int t = 0,
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) => PointerUpEvent(pointer: id, kind: kind, position: at, timeStamp: ms(t));

void main() {
  group('MultiFingerTapDetector', () {
    test('two quick, still fingers are a two-finger tap', () {
      final d = MultiFingerTapDetector();
      d.down(1, const Offset(100, 100), ms(0));
      d.down(2, const Offset(200, 100), ms(30));
      expect(d.up(1, const Offset(102, 101), ms(120)), isNull); // One still down.
      expect(d.up(2, const Offset(201, 99), ms(140)), 2);
    });

    test('three fingers are a three-finger tap', () {
      final d = MultiFingerTapDetector();
      for (var i = 0; i < 3; i++) {
        d.down(i, Offset(100.0 * i, 0), ms(i * 20));
      }
      for (var i = 0; i < 2; i++) {
        expect(d.up(i, Offset(100.0 * i, 0), ms(150)), isNull);
      }
      expect(d.up(2, const Offset(200, 0), ms(160)), 3);
    });

    test('a pinch or pan is not a tap', () {
      final d = MultiFingerTapDetector();
      d.down(1, const Offset(100, 100), ms(0));
      d.down(2, const Offset(200, 100), ms(10));
      d.move(2, const Offset(260, 100));
      d.up(1, const Offset(100, 100), ms(100));
      expect(d.up(2, const Offset(260, 100), ms(110)), isNull);
    });

    test('a slow press is not a tap', () {
      final d = MultiFingerTapDetector();
      d.down(1, Offset.zero, ms(0));
      d.down(2, const Offset(50, 0), ms(10));
      d.up(1, Offset.zero, ms(500));
      expect(d.up(2, const Offset(50, 0), ms(510)), isNull);
    });

    test('one finger is not a multi-finger tap', () {
      final d = MultiFingerTapDetector();
      d.down(1, Offset.zero, ms(0));
      expect(d.up(1, Offset.zero, ms(50)), isNull);
    });

    test('ignored while or just after a stylus is near (palm)', () {
      final d = MultiFingerTapDetector()..noteStylus(ms(1000));
      d.down(1, Offset.zero, ms(1200));
      d.down(2, const Offset(50, 0), ms(1210));
      d.up(1, Offset.zero, ms(1300));
      expect(d.up(2, const Offset(50, 0), ms(1310)), isNull);
      // Long after the pen left, taps work again.
      d.down(1, Offset.zero, ms(3000));
      d.down(2, const Offset(50, 0), ms(3010));
      d.up(1, Offset.zero, ms(3100));
      expect(d.up(2, const Offset(50, 0), ms(3110)), 2);
    });

    test('a stylus landing during the tap spoils it', () {
      final d = MultiFingerTapDetector();
      d.down(1, Offset.zero, ms(0));
      d.down(2, const Offset(50, 0), ms(10));
      d.noteStylus(ms(50), down: true);
      d.up(1, Offset.zero, ms(100));
      expect(d.up(2, const Offset(50, 0), ms(110)), isNull);
    });

    test('four fingers are ignored', () {
      final d = MultiFingerTapDetector();
      for (var i = 0; i < 4; i++) {
        d.down(i, Offset(60.0 * i, 0), ms(0));
      }
      for (var i = 0; i < 3; i++) {
        d.up(i, Offset(60.0 * i, 0), ms(100));
      }
      expect(d.up(3, const Offset(180, 0), ms(100)), isNull);
    });
  });

  group('LongPressDetector', () {
    // testWidgets runs in fake time: pumping elapses the long-press timer.
    testWidgets('fires after a still hold, not after a move or a second finger', (tester) async {
      {
        final fired = <Offset>[];
        final d = LongPressDetector(onLongPress: fired.add);
        d.down(1, const Offset(10, 10));
        await tester.pump(ms(600));
        expect(fired, [const Offset(10, 10)]);
        d.up(1);

        d.down(2, const Offset(10, 10));
        d.move(2, const Offset(40, 10));
        await tester.pump(ms(600));
        d.up(2);

        d.down(3, const Offset(10, 10));
        d.down(4, const Offset(90, 10));
        await tester.pump(ms(600));
        d
          ..up(3)
          ..up(4);

        d.down(5, const Offset(10, 10), eligible: false); // e.g. drawing
        await tester.pump(ms(600));
        d.up(5);
        expect(fired, hasLength(1));

        // A mouse button lifted meanwhile (never a finger down here) does
        // not hide finger 6, still resting, from finger 8's press.
        d
          ..down(6, const Offset(10, 10))
          ..down(7, const Offset(90, 10))
          ..up(99)
          ..up(7)
          ..down(8, const Offset(50, 50));
        await tester.pump(ms(600));
        expect(fired, hasLength(1));
      }
    });

    test('right click in place opens, a right drag does not', () {
      final clicks = <Offset>[];
      final d = SecondaryClickDetector(onClick: clicks.add);
      d
        ..down(1, const Offset(5, 5))
        ..up(1)
        ..down(2, const Offset(5, 5))
        ..move(2, const Offset(50, 5))
        ..up(2);
      expect(clicks, [const Offset(5, 5)]);
    });
  });

  group('routeStylus', () {
    const s = PointerDeviceKind.stylus;
    test('side button follows the setting; eraser end always erases', () {
      expect(routeStylus(s, kPrimaryButton, PenButtonAction.eraser), StylusRoute.tool);
      expect(routeStylus(s, kPrimaryStylusButton, PenButtonAction.eraser), StylusRoute.eraser);
      expect(routeStylus(s, kPrimaryStylusButton, PenButtonAction.lasso), StylusRoute.lasso);
      expect(routeStylus(s, kPrimaryStylusButton, PenButtonAction.none), StylusRoute.tool);
      expect(
        routeStylus(PointerDeviceKind.invertedStylus, 0, PenButtonAction.none),
        StylusRoute.eraser,
      );
      expect(
        routeStylus(PointerDeviceKind.touch, kPrimaryStylusButton, PenButtonAction.eraser),
        StylusRoute.tool,
      );
    });
  });

  group('InkInputController with gestures', () {
    late AppDatabase db;
    late SurfaceModel model;
    late ViewportController viewport;
    late ToolSettings tools;
    late ContentTools content;
    late InkInputController input;
    late List<int> taps;
    late List<Offset> menus;
    var action = PenButtonAction.eraser;

    setUp(() {
      db = AppDatabase.inMemory();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd'),
      );
      viewport = ViewportController()..setSize(const Size(800, 600));
      tools = ToolSettings(stylusOnly: true);
      final live = LiveInk();
      content = ContentTools(
        model: model,
        viewport: viewport,
        tools: tools,
        live: live,
        clipboard: InkClipboard(),
      );
      taps = [];
      menus = [];
      action = PenButtonAction.eraser;
      input = InkInputController(
        model: model,
        viewport: viewport,
        tools: tools,
        live: live,
        content: content,
        gestures: CanvasGestures(onMultiFingerTap: taps.add, onContextMenu: menus.add),
        penButtonAction: () => action,
      );
    });

    tearDown(() {
      content.dispose();
      model.dispose();
      db.close();
    });

    void stroke(int id, Offset from, Offset to, {int buttons = kPrimaryButton, int t = 0}) {
      const k = PointerDeviceKind.stylus;
      input
        ..handleDown(down(id, from, kind: k, buttons: buttons, t: t))
        ..handleMove(move(id, Offset.lerp(from, to, 0.5)!, kind: k, buttons: buttons, t: t))
        ..handleMove(move(id, to, kind: k, buttons: buttons, t: t))
        ..handleUp(up(id, to, kind: k, t: t));
    }

    test('two- and three-finger taps are reported; the view barely moves', () {
      input
        ..handleDown(down(1, const Offset(100, 100)))
        ..handleDown(down(2, const Offset(300, 100), t: 20))
        ..handleUp(up(1, const Offset(100, 100), t: 100))
        ..handleUp(up(2, const Offset(300, 100), t: 110));
      for (var i = 0; i < 3; i++) {
        input.handleDown(down(10 + i, Offset(100.0 + 80 * i, 300), t: 1000));
      }
      for (var i = 0; i < 3; i++) {
        input.handleUp(up(10 + i, Offset(100.0 + 80 * i, 300), t: 1100));
      }
      expect(taps, [2, 3]);
      expect(viewport.offset, Offset.zero);
    });

    test('a pinch zooms and is not a tap', () {
      input
        ..handleDown(down(1, const Offset(100, 100)))
        ..handleDown(down(2, const Offset(300, 100)))
        ..handleMove(move(2, const Offset(400, 100), t: 50))
        ..handleUp(up(1, const Offset(100, 100), t: 100))
        ..handleUp(up(2, const Offset(400, 100), t: 100));
      expect(taps, isEmpty);
      expect(viewport.scale, greaterThan(1));
    });

    test('with fingers drawing, a two-finger tap leaves no ink', () {
      tools.stylusOnly = false;
      input
        ..handleDown(down(1, const Offset(100, 100)))
        ..handleMove(move(1, const Offset(103, 101), t: 10))
        ..handleDown(down(2, const Offset(300, 100), t: 30))
        ..handleUp(up(1, const Offset(103, 101), t: 100))
        ..handleUp(up(2, const Offset(300, 100), t: 110));
      expect(taps, [2]);
      expect(model.loadedStrokeCount, 0);
    });

    test('a palm next to the pen is not a tap', () {
      stroke(1, const Offset(10, 10), const Offset(100, 10), t: 1000);
      input
        ..handleDown(down(5, const Offset(500, 500), t: 1100))
        ..handleDown(down(6, const Offset(560, 520), t: 1120))
        ..handleUp(up(5, const Offset(500, 500), t: 1200))
        ..handleUp(up(6, const Offset(560, 520), t: 1220));
      expect(taps, isEmpty);
    });

    testWidgets('a navigating finger held still opens the context menu', (tester) async {
      input.handleDown(down(1, const Offset(200, 200)));
      await tester.pump(ms(700));
      input.handleUp(up(1, const Offset(200, 200), t: 700));
      expect(menus, [const Offset(200, 200)]);
    });

    test('right click opens the context menu; right drag pans', () {
      const m = PointerDeviceKind.mouse;
      input
        ..handleDown(down(1, const Offset(50, 50), kind: m, buttons: kSecondaryMouseButton))
        ..handleUp(up(1, const Offset(50, 50), kind: m))
        ..handleDown(down(2, const Offset(50, 50), kind: m, buttons: kSecondaryMouseButton))
        ..handleMove(move(2, const Offset(150, 50), kind: m, buttons: kSecondaryMouseButton))
        ..handleUp(up(2, const Offset(150, 50), kind: m));
      expect(menus, [const Offset(50, 50)]);
      expect(viewport.offset.dx, 100);
    });

    test('side button set to lasso selects; the selection then moves with the pen', () {
      stroke(1, const Offset(100, 100), const Offset(200, 100));
      expect(model.loadedStrokeCount, 1);
      action = PenButtonAction.lasso;
      // Loop around the stroke with the button held.
      const k = PointerDeviceKind.stylus;
      const b = kPrimaryStylusButton;
      input.handleDown(down(2, const Offset(80, 60), kind: k, buttons: b));
      for (final p in const [Offset(220, 60), Offset(220, 140), Offset(80, 140), Offset(80, 62)]) {
        input.handleMove(move(2, p, kind: k, buttons: b));
      }
      input.handleUp(up(2, const Offset(80, 62), kind: k));
      expect(content.selection.strokes, hasLength(1));
      expect(model.loadedStrokeCount, 1); // No ink drawn by the lasso.
      expect(tools.tool, EditorTool.pen);

      // Without the button: dragging the selection moves it.
      stroke(3, const Offset(150, 100), const Offset(150, 300));
      expect(content.selection.strokes, hasLength(1));
      expect(model.strokesNear(const Rect.fromLTWH(0, 250, 800, 100)), isNotEmpty);

      // Pressing elsewhere drops the selection and draws again.
      stroke(4, const Offset(500, 500), const Offset(600, 500));
      expect(content.selection.isEmpty, isTrue);
      expect(model.loadedStrokeCount, 2);

      // A tap that only drops a selection leaves no dot (R13-1); the next
      // tap is a dot.
      content.selection.select(model.strokesNear(const Rect.fromLTWH(0, 0, 800, 800)), const []);
      input
        ..handleDown(down(5, const Offset(400, 700), kind: k, t: 2000))
        ..handleUp(up(5, const Offset(400, 700), kind: k, t: 2200));
      expect(content.selection.isEmpty, isTrue);
      expect(model.loadedStrokeCount, 2);
      input
        ..handleDown(down(6, const Offset(400, 700), kind: k, t: 3000))
        ..handleUp(up(6, const Offset(400, 700), kind: k, t: 3200));
      expect(model.loadedStrokeCount, 3);
    });

    test('the side-button lasso follows the lasso options', () {
      stroke(1, const Offset(100, 100), const Offset(200, 100));
      action = PenButtonAction.lasso;
      tools.lasso = const LassoConfig(shape: LassoShape.rectangle, cover: LassoCover.whole);
      const k = PointerDeviceKind.stylus;
      const b = kPrimaryStylusButton;
      void drag(int pointer, Offset from, Offset to) => input
        ..handleDown(down(pointer, from, kind: k, buttons: b))
        ..handleMove(move(pointer, Offset.lerp(from, to, 0.5)!, kind: k, buttons: b))
        ..handleMove(move(pointer, to, kind: k, buttons: b))
        ..handleUp(up(pointer, to, kind: k));
      // A rectangle short of the stroke's end takes nothing (wholly inside).
      drag(2, const Offset(80, 60), const Offset(180, 140));
      expect(content.selection.isEmpty, isTrue);
      // One around all of it takes it: a straight drag, no loop.
      drag(3, const Offset(80, 60), const Offset(220, 140));
      expect(content.selection.strokes, hasLength(1));
      expect(model.loadedStrokeCount, 1);
    });

    testWidgets('a palm resting next to the pen is not a two-finger hold', (tester) async {
      var holds = 0;
      input.gestures!.onTwoFingerHold = () => holds++;
      const k = PointerDeviceKind.stylus;
      // Writing, the palm lands as two still contacts.
      input
        ..handleDown(down(1, const Offset(10, 10), kind: k))
        ..handleDown(down(5, const Offset(500, 500), t: 50))
        ..handleDown(down(6, const Offset(560, 520), t: 60))
        ..handleMove(move(1, const Offset(100, 10), kind: k, t: 300));
      await tester.pump(ms(700));
      input
        ..handleUp(up(1, const Offset(100, 10), kind: k, t: 700))
        ..handleUp(up(5, const Offset(500, 500), t: 720))
        ..handleUp(up(6, const Offset(560, 520), t: 720));
      // The pen hovering, the palm lands again.
      input
        ..handleHover(
          const PointerHoverEvent(
            kind: k,
            position: Offset(100, 10),
            timeStamp: Duration(milliseconds: 900),
          ),
        )
        ..handleDown(down(7, const Offset(500, 500), t: 950))
        ..handleDown(down(8, const Offset(560, 520), t: 960));
      await tester.pump(ms(700));
      input
        ..handleUp(up(7, const Offset(500, 500), t: 1700))
        ..handleUp(up(8, const Offset(560, 520), t: 1700));
      expect(holds, 0);
      // Fingers alone still hold.
      input
        ..handleDown(down(9, const Offset(300, 300), t: 5000))
        ..handleDown(down(10, const Offset(400, 300), t: 5010));
      await tester.pump(ms(700));
      expect(holds, 1);
    });

    test('a cancelled stylus contact does not block finger taps for good', () {
      const k = PointerDeviceKind.stylus;
      input
        ..handleDown(down(1, const Offset(10, 10), kind: k, t: 1000))
        ..handleCancel(
          const PointerCancelEvent(pointer: 1, kind: k, timeStamp: Duration(milliseconds: 1050)),
        );
      // Long after the pen went away, a two-finger tap undoes again.
      input
        ..handleDown(down(5, const Offset(300, 300), t: 5000))
        ..handleDown(down(6, const Offset(400, 300), t: 5010))
        ..handleUp(up(5, const Offset(300, 300), t: 5100))
        ..handleUp(up(6, const Offset(400, 300), t: 5110));
      expect(taps, [2]);
    });

    test('side button set to none just draws', () {
      action = PenButtonAction.none;
      stroke(1, const Offset(100, 100), const Offset(200, 100), buttons: kPrimaryStylusButton);
      expect(model.loadedStrokeCount, 1);
      expect(model.strokesNear(const Rect.fromLTWH(0, 0, 800, 600)).single.tool, InkTool.ballpoint);
    });
  });
}
