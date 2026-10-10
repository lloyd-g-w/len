import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/pen/pen_options_panel.dart';
import 'package:len/features/editor/pen/slot_editors.dart';
import 'package:len/features/editor/pen/stroke_preview.dart';
import 'package:len/ink/input/hold_to_straighten.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/color_picker/color_picker.dart';

void main() {
  group('hold to straighten', () {
    late AppDatabase db;
    late SurfaceModel model;
    late ToolSettings tools;
    late LiveInk live;
    late InkInputController input;

    setUp(() {
      db = AppDatabase.inMemory();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd'),
      );
      tools = ToolSettings(stylusOnly: true);
      live = LiveInk();
      input = InkInputController(
        model: model,
        viewport: ViewportController()..setSize(const Size(800, 600)),
        tools: tools,
        live: live,
      );
    });

    tearDown(() {
      model.dispose();
      db.close();
    });

    PointerMoveEvent move(Offset at) =>
        PointerMoveEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: at, pressure: 0.5);

    Future<void> drawWobblyAndHold(WidgetTester tester) async {
      input.handleDown(
        const PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: Offset(10, 10),
          pressure: 0.5,
        ),
      );
      for (var i = 1; i <= 20; i++) {
        input.handleMove(move(Offset(10 + i * 10.0, 10 + (i.isEven ? 6 : -6))));
      }
      await tester.pump(HoldToStraighten.holdDuration + const Duration(milliseconds: 50));
      input.handleUp(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus));
    }

    testWidgets('resting the pen commits a single straight stroke', (tester) async {
      await drawWobblyAndHold(tester);
      expect(model.loadedStrokeCount, 1);
      final edit = model.history.takeUndo()!;
      final stroke = edit.added.single;
      expect(stroke.points.first.offset, const Offset(10, 10));
      expect(stroke.points.every((p) => (p.y - 10 - (p.x - 10) * (6 / 200)).abs() < 1e-3), isTrue);
    });

    testWidgets('the setting can turn it off', (tester) async {
      tools.holdToStraighten = false;
      await drawWobblyAndHold(tester);
      final stroke = model.history.takeUndo()!.added.single;
      expect(stroke.points.map((p) => p.y).toSet().length, greaterThan(2));
    });
  });

  group('toolbar', () {
    Future<ToolSettings> pumpToolbar(WidgetTester tester, Size size) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tools = ToolSettings();
      addTearDown(tools.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: EditorToolbar(tools: tools, onStylusOnlyChanged: (_) {}),
            ),
          ),
        ),
      );
      return tools;
    }

    testWidgets('colours and widths are chosen independently with one tap', (tester) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      await tester.tap(find.byKey(const ValueKey('color-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('width-2')));
      await tester.pump();
      expect(tools.activeConfig.colorIndex, 1);
      expect(tools.activeConfig.widthIndex, 2);
      expect(find.byType(ColorPicker), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the selected colour opens the picker for that slot', (tester) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      await tester.tap(find.byKey(const ValueKey('color-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('color-2')));
      await tester.pumpAndSettle();
      expect(find.byType(ColorPicker), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing, reason: 'a popover on tablets');
      await tester.enterText(find.byType(TextField), 'FF0000');
      await tester.pump();
      expect(tools.activeConfig.colors[2], 0xFFFF0000);
      expect(tools.activeConfig.color, 0xFFFF0000);
      expect(tools.activeConfig.colors[0], PenDefaults.pen.colors[0]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long-press a width to edit it with a live preview, or remove it', (tester) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      await tester.longPress(find.byKey(const ValueKey('width-0')));
      await tester.pumpAndSettle();
      expect(find.byType(WidthSlotEditor), findsOneWidget);
      expect(find.byType(StrokePreview), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pump();
      expect(tools.activeConfig.widths[0], greaterThan(PenDefaults.pen.widths[0]));
      await tester.tap(find.byTooltip('Remove width'));
      await tester.pumpAndSettle();
      expect(tools.activeConfig.widths, hasLength(2));
      expect(find.byType(WidthSlotEditor), findsNothing);
    });

    testWidgets('"+" adds a colour slot and opens its picker', (tester) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      await tester.tap(find.byTooltip('Add colour'));
      await tester.pumpAndSettle();
      expect(tools.activeConfig.colors, hasLength(4));
      expect(tools.activeConfig.colorIndex, 3);
      expect(find.byType(ColorPicker), findsOneWidget);
    });

    testWidgets('the highlighter has its own slots', (tester) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      await tester.tap(find.byTooltip('Highlighter (H)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('color-2')));
      await tester.pump();
      expect(tools.configOf(InkTool.highlighter).colorIndex, 2);
      expect(tools.configOf(InkTool.ballpoint).colorIndex, 0);
    });

    testWidgets('tapping the active pen opens its settings (sheet on phones)', (tester) async {
      final tools = await pumpToolbar(tester, const Size(390, 800));
      await tester.tap(find.byTooltip('Pen (P)'));
      await tester.pumpAndSettle();
      expect(find.byType(PenOptionsPanel), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      for (final removed in ['Fountain', 'Brush', 'Pencil', 'Marker']) {
        expect(find.text(removed), findsNothing);
      }
      await tester.tap(find.text('Tapered ends'));
      await tester.pump();
      expect(tools.configOf(InkTool.ballpoint).taper, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the toolbar fits a phone on two rows and a tablet on one', (tester) async {
      await pumpToolbar(tester, const Size(390, 800));
      final phone = tester.getSize(find.byType(EditorToolbar));
      expect(phone.width, lessThanOrEqualTo(390));
      expect(phone.height, greaterThan(80), reason: 'two rows');
      await pumpToolbar(tester, const Size(1194, 834));
      expect(tester.getSize(find.byType(EditorToolbar)).height, lessThan(60), reason: 'one row');
      expect(tester.takeException(), isNull);
    });

    testWidgets('eraser options switch to the partial eraser', (tester) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      await tester.tap(find.byTooltip('Eraser (E)'));
      await tester.pump();
      await tester.tap(find.byTooltip('Eraser (E)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Partial'));
      await tester.pump();
      expect(tools.eraser.mode, EraserMode.pixel);
      await tester.tap(find.text('Erase highlighter only'));
      await tester.pump();
      expect(tools.eraser.highlighterOnly, isTrue);
    });
  });
}
