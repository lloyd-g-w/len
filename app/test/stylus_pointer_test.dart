import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/ink/ink_surface.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/stylus_pointer.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

/// The system's stylus hover pointer (the S Pen's dot) hides exactly where
/// the canvas draws its own hover preview, so the two don't overlap.
void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late ToolSettings tools;
  late ViewportController viewport;
  late LiveInk live;
  late StylusPointer pointer;
  late List<bool> sent;
  late InkInputController input;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    tools = ToolSettings(stylusOnly: true);
    viewport = ViewportController()..setSize(const Size(700, 600));
    live = LiveInk();
    sent = [];
    pointer = StylusPointer(send: sent.add);
    input = InkInputController(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      penButtonAction: () => PenButtonAction.eraser,
      stylusPointer: pointer,
    );
  });

  tearDown(() {
    pointer.detach();
    live.dispose();
    model.dispose();
    db.close();
  });

  const toolbar = Offset(50, 300);
  const canvas = Offset(400, 300);

  /// A toolbar (0–100) beside the canvas; the pointer watches the app.
  Future<TestGesture> pen(
    WidgetTester tester, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    Offset at = canvas,
  }) async {
    pointer.attach();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            const SizedBox(
              width: 100,
              child: MouseRegion(
                cursor: SystemMouseCursors.basic,
                child: ColoredBox(color: Colors.white),
              ),
            ),
            Expanded(
              child: InkSurface(
                model: model,
                viewport: viewport,
                input: input,
                live: live,
                paper: Paper(PaperStyle.blank),
              ),
            ),
          ],
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: kind);
    await gesture.addPointer(location: at);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(at + const Offset(4, 4));
    await tester.pump();
    return gesture;
  }

  Future<void> expire(WidgetTester tester) => tester.pump(LiveInk.stylusHoverTimeout * 2);

  for (final tool in [EditorTool.pen, EditorTool.highlighter, EditorTool.eraser]) {
    testWidgets('hidden over the canvas with the ${tool.name}', (tester) async {
      tools.tool = tool;
      await pen(tester);
      expect(pointer.hidden, isTrue);
      expect(sent, [true]);
      expect(input.cursor.value, SystemMouseCursors.none);
      await expire(tester);
    });
  }

  for (final tool in [EditorTool.lasso, EditorTool.text]) {
    testWidgets('shown over the canvas with the ${tool.name}', (tester) async {
      tools.tool = tool;
      await pen(tester);
      expect(pointer.hidden, isFalse);
      expect(sent, isEmpty);
      await expire(tester);
    });
  }

  testWidgets('hidden for the eraser end, whatever the tool', (tester) async {
    tools.tool = EditorTool.lasso;
    await pen(tester, kind: PointerDeviceKind.invertedStylus);
    expect(pointer.hidden, isTrue, reason: 'the eraser end shows the ring');
    await expire(tester);
  });

  testWidgets('hidden for the side button set to erase', (tester) async {
    tools.tool = EditorTool.lasso;
    final gesture = await pen(tester);
    expect(pointer.hidden, isFalse);
    tester.binding.handlePointerEvent(
      const PointerHoverEvent(
        kind: PointerDeviceKind.stylus,
        device: 0,
        position: canvas,
        buttons: kPrimaryStylusButton,
      ),
    );
    await tester.pump();
    expect(pointer.hidden, isTrue);
    await gesture.moveTo(canvas); // The button released.
    expect(pointer.hidden, isFalse);
    await expire(tester);
  });

  testWidgets('shown over the toolbar, hidden again back on the canvas', (tester) async {
    final gesture = await pen(tester, at: toolbar);
    expect(pointer.hidden, isFalse);
    await gesture.moveTo(canvas);
    expect(pointer.hidden, isTrue);
    await gesture.moveTo(toolbar);
    expect(pointer.hidden, isFalse);
    expect(sent, [true, false]);
    await expire(tester);
  });

  testWidgets('follows a tool picked while the pen rests, at once', (tester) async {
    await pen(tester);
    expect(pointer.hidden, isTrue);
    tools.tool = EditorTool.lasso;
    expect(pointer.hidden, isFalse, reason: 'no frame needed');
    tools.tool = EditorTool.eraser;
    expect(pointer.hidden, isTrue);
    tools.tool = EditorTool.text;
    expect(pointer.hidden, isFalse);
    tools.tool = EditorTool.highlighter;
    expect(pointer.hidden, isTrue);
    expect(sent, [true, false, true, false, true]);
    await expire(tester);
  });

  testWidgets('a tool picked after the pen moved to the toolbar leaves it shown', (tester) async {
    tools.tool = EditorTool.lasso;
    final gesture = await pen(tester);
    await gesture.moveTo(toolbar);
    tools.tool = EditorTool.pen;
    expect(pointer.hidden, isFalse);
    await expire(tester);
  });

  testWidgets('a mouse never touches the stylus pointer; its cursor hides as before', (
    tester,
  ) async {
    tools.tool = EditorTool.eraser;
    await pen(tester, kind: PointerDeviceKind.mouse);
    expect(input.cursor.value, SystemMouseCursors.none);
    expect(sent, isEmpty);
  });

  testWidgets('detaching shows the pointer again', (tester) async {
    await pen(tester);
    expect(pointer.hidden, isTrue);
    pointer.detach();
    expect(pointer.hidden, isFalse);
    expect(sent, [true, false]);
    await expire(tester);
  });
}
