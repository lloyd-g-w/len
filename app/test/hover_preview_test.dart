import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/ink/input/ink_drawing.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

/// A hovering pen previews its ink (R15-1); the eraser ring shows on any
/// paper (R15-2).
PointerHoverEvent _hover(
  Offset at, {
  PointerDeviceKind kind = PointerDeviceKind.stylus,
  int buttons = 0,
  int ms = 0,
}) => PointerHoverEvent(
  kind: kind,
  position: at,
  buttons: buttons,
  timeStamp: Duration(milliseconds: ms),
);

void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late ToolSettings tools;
  late ViewportController viewport;
  late LiveInk live;
  late InkInputController input;
  var button = PenButtonAction.eraser;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    tools = ToolSettings(stylusOnly: true);
    viewport = ViewportController()..setSize(const Size(800, 600));
    live = LiveInk();
    button = PenButtonAction.eraser;
    input = InkInputController(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      penButtonAction: () => button,
    );
  });

  tearDown(() {
    live.dispose();
    model.dispose();
    db.close();
  });

  test('a hovering pen previews its ink: colour at half opacity, width at medium pressure', () {
    viewport.setView(scale: 2, offset: const Offset(10, 20));
    input.handleHover(_hover(const Offset(100, 80)));
    final config = tools.configOf(tools.activeInk);
    expect(live.penCenter, viewport.toWorld(const Offset(100, 80)));
    expect(live.penRadius, config.width / 2);
    expect(
      live.penColor.toARGB32(),
      Color(config.color).withValues(alpha: InkDrawing.previewOpacity).toARGB32(),
    );
    expect(live.eraserCenter, isNull);
  });

  test('the highlighter previews at its own opacity', () {
    tools.tool = EditorTool.highlighter;
    input.handleHover(_hover(const Offset(100, 80)));
    final config = tools.configOf(tools.activeInk);
    expect(live.penColor.a, closeTo(config.opacity, 0.01));
    expect(live.penColor.a, lessThan(InkDrawing.previewOpacity));
  });

  test('no preview for a mouse, the eraser end, other tools or a side button routing away', () {
    input.handleHover(_hover(const Offset(10, 10), kind: PointerDeviceKind.mouse));
    expect(live.penCenter, isNull);
    input.handleHover(_hover(const Offset(10, 10), kind: PointerDeviceKind.invertedStylus));
    expect(live.penCenter, isNull);
    expect(live.eraserCenter, isNotNull);
    input.handleHover(_hover(const Offset(10, 10), buttons: kPrimaryStylusButton));
    expect(live.penCenter, isNull, reason: 'the side button erases');
    button = PenButtonAction.none;
    input.handleHover(_hover(const Offset(10, 10), buttons: kPrimaryStylusButton));
    expect(live.penCenter, isNotNull, reason: 'a side button doing nothing writes');
    tools.tool = EditorTool.lasso;
    input.handleHover(_hover(const Offset(10, 10)));
    expect(live.penCenter, isNull);
  });

  test('the preview goes at pen-down, on exit and when a finger touches', () {
    input.handleHover(_hover(const Offset(100, 80)));
    input.handleDown(
      const PointerDownEvent(
        kind: PointerDeviceKind.stylus,
        position: Offset(100, 80),
        buttons: kPrimaryButton,
        pressure: 0.5,
      ),
    );
    expect(live.penCenter, isNull);
    input.handleUp(const PointerUpEvent(kind: PointerDeviceKind.stylus, position: Offset(100, 80)));
    input.handleHover(_hover(const Offset(100, 80)));
    input.handleExit();
    expect(live.penCenter, isNull);
    input.handleHover(_hover(const Offset(100, 80)));
    input.handleDown(
      const PointerDownEvent(
        pointer: 2,
        position: Offset(400, 300),
        timeStamp: Duration(seconds: 5), // Long after the pen.
      ),
    );
    expect(live.penCenter, isNull);
  });

  test('a stylus\'s cursors go once it stops reporting (it left range: no exit on Android)', () {
    fakeAsync((async) {
      input.handleHover(_hover(const Offset(100, 80)));
      async.elapse(LiveInk.stylusHoverTimeout * 0.8);
      input.handleHover(_hover(const Offset(101, 80)));
      async.elapse(LiveInk.stylusHoverTimeout * 0.8);
      expect(live.penCenter, isNotNull, reason: 'still streaming');
      async.elapse(LiveInk.stylusHoverTimeout * 0.3);
      expect(live.penCenter, isNull);
      tools.tool = EditorTool.eraser;
      input.handleHover(_hover(const Offset(100, 80)));
      expect(live.eraserCenter, isNotNull);
      async.elapse(LiveInk.stylusHoverTimeout * 1.1);
      expect(live.eraserCenter, isNull);
      // A mouse sends an exit: its eraser ring stays while it rests.
      input.handleHover(_hover(const Offset(100, 80), kind: PointerDeviceKind.mouse));
      async.elapse(LiveInk.stylusHoverTimeout * 3);
      expect(live.eraserCenter, isNotNull);
    });
  });

  test('the eraser ring stays while the pen erases, resting', () {
    fakeAsync((async) {
      tools.tool = EditorTool.eraser;
      input.handleHover(_hover(const Offset(100, 80)));
      input.handleDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.stylus,
          position: Offset(100, 80),
          buttons: kPrimaryButton,
          pressure: 0.5,
        ),
      );
      async.elapse(LiveInk.stylusHoverTimeout * 2);
      expect(live.eraserCenter, isNotNull, reason: 'the pen touches: it did not leave');
      input.handleUp(
        const PointerUpEvent(kind: PointerDeviceKind.stylus, position: Offset(100, 80)),
      );
      async.elapse(LiveInk.stylusHoverTimeout * 1.1);
      expect(live.eraserCenter, isNull, reason: 'lifted and gone');
    });
  });

  testWidgets('hover cursors on white and dark paper', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget panel(Color paper, void Function(LiveInk) show) {
      final ink = LiveInk();
      addTearDown(ink.dispose);
      show(ink);
      final view = ViewportController()..setView(scale: 2, offset: Offset.zero);
      addTearDown(view.dispose);
      return Expanded(
        child: ColoredBox(
          color: paper,
          child: CustomPaint(
            painter: LiveInkPainter(live: ink, viewport: view),
            size: Size.infinite,
          ),
        ),
      );
    }

    void pen(LiveInk ink) =>
        ink.showPen(const Offset(40, 20), radius: 1.25, color: const Color(0x801C4ED8));
    void marker(LiveInk ink) =>
        ink.showPen(const Offset(40, 20), radius: 8, color: const Color(0x59FACC15));
    void eraser(LiveInk ink) => ink.showEraser(const Offset(40, 20), 6);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            for (final paper in [PaperColor.white.paper, PaperColor.dark.paper])
              Expanded(
                child: Row(
                  children: [panel(paper, pen), panel(paper, marker), panel(paper, eraser)],
                ),
              ),
          ],
        ),
      ),
    );
    await expectLater(find.byType(Column), matchesGoldenFile('goldens/hover_cursors.png'));
  });
}
