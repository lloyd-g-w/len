import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/clock.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/chrome/editor_tips.dart';
import 'package:len/features/editor/chrome/tip_banner.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';

/// Time from fake_async, so the budget's minutes pass in the test.
class _FakeClock extends Clock {
  _FakeClock(this.async);

  final FakeAsync async;

  @override
  int nowMs() => 1000000 + async.elapsed.inMilliseconds;
}

/// One device: what has been seen and when a tip last showed, shared by
/// its editors (notebook openings).
class _Device {
  _Device(this.async);

  final FakeAsync async;
  final seen = <String>{};
  int? lastShownAt;
  final messages = ValueNotifier(false);
  final tools = ToolSettings();
  final pen = LiveInk();
  final selected = ValueNotifier(false);
  PenButtonAction penButton = PenButtonAction.eraser;

  /// Opens a notebook: a new editor with its own controller.
  TipsController open() =>
      TipsController(
        seen: seen.contains,
        markSeen: seen.add,
        lastShownAt: () => lastShownAt,
        shownAt: (ms) => lastShownAt = ms,
        clock: _FakeClock(async),
        messages: messages,
      )..followTools(
        tools,
        selection: selected,
        selected: () => selected.value,
        pen: pen,
        penButton: () => penButton,
      );

  void penDown() => pen
    ..begin(tool: InkTool.ballpoint, color: 0xFF000000, width: 2)
    ..add(const StrokePoint(0, 0, 0.5));

  void penUp() => pen.finish();

  /// A short stroke.
  void write() {
    penDown();
    penUp();
  }
}

void main() {
  const rest = TipsController.calmFor;

  group('the tip budget', () {
    test('a tip waits until the pen has rested 2 s', () {
      fakeAsync((async) {
        final d = _Device(async);
        final tips = d.open();
        d.penDown();
        tips.offer(EditorTip.penButton);
        async.elapse(const Duration(seconds: 5));
        expect(tips.value, isNull, reason: 'never while the pen is down');
        d.penUp();
        async.elapse(rest - const Duration(milliseconds: 100));
        expect(tips.value, isNull, reason: 'not yet rested');
        d.write(); // Writing on starts the rest again.
        async.elapse(rest - const Duration(milliseconds: 100));
        expect(tips.value, isNull);
        async.elapse(const Duration(milliseconds: 100));
        expect(tips.value?.tip, EditorTip.penButton);
        tips.dispose();
      });
    });

    test('a tip shown with the pen at rest a while comes at once', () {
      fakeAsync((async) {
        final d = _Device(async);
        final tips = d.open();
        d.tools.tool = EditorTool.lasso;
        async.flushMicrotasks();
        expect(tips.value?.tip, EditorTip.lasso);
        tips.dispose();
      });
    });

    test('it counts as seen after 3 s on screen; until then it stays due', () {
      fakeAsync((async) {
        final d = _Device(async);
        var tips = d.open();
        d.tools.tool = EditorTool.lasso;
        async.elapse(TipsController.seenAfter - const Duration(milliseconds: 250));
        d.tools.tool = EditorTool.pen; // Gone before it was read.
        async.flushMicrotasks();
        expect(tips.value, isNull);
        expect(d.seen, isEmpty);
        tips.dispose();

        async.elapse(TipsController.between);
        tips = d.open();
        d.tools.tool = EditorTool.lasso;
        async.flushMicrotasks();
        expect(tips.value?.tip, EditorTip.lasso, reason: 'still due');
        async.elapse(TipsController.seenAfter);
        expect(d.seen, {EditorTip.lasso.name});
        async.elapse(TipsController.visibleFor);
        expect(tips.value, isNull, reason: 'goes by itself');
        tips.dispose();

        async.elapse(TipsController.between);
        tips = d.open();
        d.tools
          ..tool = EditorTool.pen
          ..tool = EditorTool.lasso;
        async.flushMicrotasks();
        expect(tips.value, isNull, reason: 'seen: never again');
        tips.dispose();
      });
    });

    test('it fades while the pen is down, and its time stops', () {
      fakeAsync((async) {
        final d = _Device(async);
        final tips = d.open();
        tips.offer(EditorTip.holdToSnap);
        async.flushMicrotasks();
        expect(tips.writing.value, isFalse);
        d.penDown();
        expect(tips.writing.value, isTrue);
        async.elapse(const Duration(seconds: 30));
        expect(tips.value?.tip, EditorTip.holdToSnap, reason: 'time stopped');
        expect(d.seen, isEmpty);
        d.penUp();
        expect(tips.writing.value, isFalse);
        async.elapse(TipsController.seenAfter);
        expect(d.seen, {EditorTip.holdToSnap.name});
        tips.dispose();
      });
    });

    test('one tip per opening', () {
      fakeAsync((async) {
        final d = _Device(async);
        final tips = d.open();
        tips.offer(EditorTip.holdToSnap);
        async.elapse(TipsController.visibleFor);
        expect(tips.value, isNull);
        async.elapse(TipsController.between * 2);
        tips.offer(EditorTip.penButton);
        async.elapse(rest);
        expect(tips.value, isNull, reason: 'this opening had its tip');
        tips.dispose();
      });
    });

    test('at least 10 minutes between tips, across openings', () {
      fakeAsync((async) {
        final d = _Device(async);
        var tips = d.open();
        tips.offer(EditorTip.holdToSnap);
        async.elapse(TipsController.visibleFor);
        tips.dispose();

        tips = d.open();
        async.elapse(TipsController.between - const Duration(seconds: 11));
        tips.offer(EditorTip.penButton);
        async.elapse(rest);
        expect(tips.value, isNull, reason: 'too soon');
        async.elapse(const Duration(seconds: 1));
        tips.offer(EditorTip.penButton);
        async.flushMicrotasks();
        expect(tips.value?.tip, EditorTip.penButton, reason: 'the next trigger');
        tips.dispose();
      });
    });

    test('none within 60 s of a snack bar; a shown one waits behind it', () {
      fakeAsync((async) {
        final d = _Device(async);
        final tips = d.open();
        d.messages.value = true;
        tips.offer(EditorTip.penButton);
        async.flushMicrotasks();
        expect(tips.value, isNull, reason: 'a snack bar is up');
        async.elapse(const Duration(seconds: 4));
        d.messages.value = false;
        async.elapse(TipsController.afterMessage - const Duration(seconds: 1));
        tips.offer(EditorTip.penButton);
        async.flushMicrotasks();
        expect(tips.value, isNull, reason: 'too soon after it');
        async.elapse(const Duration(seconds: 1));
        tips.offer(EditorTip.penButton);
        async.flushMicrotasks();
        expect(tips.value?.tip, EditorTip.penButton);

        d.messages.value = true; // Hides the tip: its time stops.
        async.elapse(const Duration(seconds: 30));
        expect(d.seen, isEmpty);
        async.flushMicrotasks();
        expect(tips.value, isNotNull);
        d.messages.value = false;
        async.elapse(TipsController.seenAfter);
        expect(d.seen, {EditorTip.penButton.name});
        tips.dispose();
      });
    });

    test('a tip never replaces another; the later one waits for its next trigger', () {
      fakeAsync((async) {
        final d = _Device(async);
        var tips = d.open();
        tips.offer(EditorTip.holdToSnap);
        d.tools.tool = EditorTool.lasso;
        async.flushMicrotasks();
        expect(tips.value?.tip, EditorTip.holdToSnap);
        async.elapse(TipsController.visibleFor);
        expect(tips.value, isNull, reason: 'the lasso tip did not queue');
        tips.dispose();

        async.elapse(TipsController.between);
        tips = d.open();
        d.tools
          ..tool = EditorTool.pen
          ..tool = EditorTool.lasso;
        async.flushMicrotasks();
        expect(tips.value?.tip, EditorTip.lasso);
        tips.dispose();
      });
    });

    test('of tips due together: side button, hold to snap, lasso', () {
      fakeAsync((async) {
        final d = _Device(async);
        var tips = d.open();
        d.penDown();
        d.tools.tool = EditorTool.lasso;
        tips
          ..offer(EditorTip.lasso)
          ..offer(EditorTip.penButton);
        d.penUp();
        tips.shapeDrawn();
        async.elapse(rest);
        expect(tips.value?.tip, EditorTip.penButton);
        async.elapse(TipsController.visibleFor);
        tips.dispose();

        async.elapse(TipsController.between);
        tips = d.open();
        d.write();
        tips
          ..offer(EditorTip.lasso)
          ..shapeDrawn();
        async.elapse(rest);
        expect(tips.value?.tip, EditorTip.holdToSnap);
        async.elapse(TipsController.visibleFor);
        tips.dispose();

        async.elapse(TipsController.between);
        tips = d.open();
        d.write();
        tips.offer(EditorTip.lasso);
        async.elapse(rest);
        expect(tips.value?.tip, EditorTip.lasso);
        tips.dispose();
      });
    });

    test('scribble: picking the eraser again; writing on puts hold to snap off', () {
      fakeAsync((async) {
        final d = _Device(async);
        final tips = d.open();
        d.tools.tool = EditorTool.eraser;
        async.flushMicrotasks();
        expect(tips.value, isNull, reason: 'the first pick');
        d.write();
        tips.shapeDrawn();
        d.write(); // Writing on before the rest: hold to snap waits for the next shape.
        d.tools
          ..tool = EditorTool.pen
          ..tool = EditorTool.eraser;
        async.elapse(rest);
        expect(tips.value?.text, 'Or scribble over ink with the pen to erase it');
        tips.dispose();
      });
    });

    test('tips that the settings make moot never show', () {
      fakeAsync((async) {
        final d = _Device(async)..penButton = PenButtonAction.none;
        d.tools
          ..holdToStraighten = false
          ..scribbleToErase = false;
        final tips = d.open();
        tips
          ..offer(EditorTip.penButton)
          ..shapeDrawn();
        for (var i = 0; i < 3; i++) {
          d.tools
            ..tool = EditorTool.eraser
            ..tool = EditorTool.pen;
        }
        async.elapse(rest);
        expect(tips.value, isNull);
        d.penButton = PenButtonAction.lasso;
        tips.offer(EditorTip.penButton);
        async.flushMicrotasks();
        expect(tips.value?.text, 'Hold the pen’s side button to select with the lasso');
        tips.dispose();
      });
    });

    test('the lasso tip: not over a selection; a selection is the tip done', () {
      fakeAsync((async) {
        final d = _Device(async);
        final tips = d.open();
        d.selected.value = true;
        d.tools.tool = EditorTool.lasso;
        async.flushMicrotasks();
        expect(tips.value, isNull, reason: 'it would cover the selection');
        d.selected.value = false;
        d.tools
          ..tool = EditorTool.pen
          ..tool = EditorTool.lasso;
        async.flushMicrotasks();
        expect(tips.value?.tip, EditorTip.lasso);
        d.selected.value = true;
        async.flushMicrotasks();
        expect(tips.value, isNull);
        expect(d.seen, {EditorTip.lasso.name}, reason: 'the user did what it says');
        tips.dispose();
      });
    });
  });

  group('the banner', () {
    late _Device device;
    late TipsController tips;

    Future<List<PointerDeviceKind>> pumpBanner(WidgetTester tester) async {
      device = _Device(FakeAsync());
      tips = TipsController(seen: (_) => false, markSeen: (_) {}, messages: device.messages)
        ..followTools(device.tools, pen: device.pen);
      addTearDown(tips.dispose);
      final page = <PointerDeviceKind>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => page.add(e.kind),
                ),
              ),
              Center(child: TipBanner(controller: tips)),
            ],
          ),
        ),
      );
      tips.offer(EditorTip.holdToSnap);
      await tester.pumpAndSettle();
      return page;
    }

    testWidgets('pen strokes and taps on it go through to the page', (tester) async {
      final page = await pumpBanner(tester);
      final card = find.text('Hold the pen still at the end of a line or shape to snap it clean');
      expect(card, findsOneWidget);
      final at = tester.getCenter(card);
      final pen = await tester.startGesture(at, kind: PointerDeviceKind.stylus);
      await pen.moveBy(const Offset(40, 0));
      await pen.up();
      await tester.tapAt(at);
      expect(page, [PointerDeviceKind.stylus, PointerDeviceKind.touch]);
      expect(tips.value, isNotNull, reason: 'the tip took nothing');
      await tester.pump(TipsController.visibleFor);
      await tester.pumpAndSettle();
    });

    testWidgets('it fades while the pen is down', (tester) async {
      await pumpBanner(tester);
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find.descendant(of: find.byType(TipBanner), matching: find.byType(AnimatedOpacity)),
          )
          .opacity;
      expect(opacity(), 1);
      device.penDown();
      await tester.pumpAndSettle();
      expect(opacity(), 0);
      device.penUp();
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      await tester.pump(TipsController.visibleFor);
      await tester.pumpAndSettle();
    });
  });
}
