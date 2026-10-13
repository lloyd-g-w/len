import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/pen/pen_options_panel.dart';
import 'package:len/features/editor/pen/stroke_preview.dart';
import 'package:len/features/editor/toolbar/tool_options_popover.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';
import 'package:len/ink/input/hold_to_straighten.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

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
              child: EditorToolbar(
                tools: tools,
                dock: size.width < 600 ? ToolbarDock.bottom : ToolbarDock.row,
              ),
            ),
          ),
        ),
      );
      return tools;
    }

    /// The options popover's copy of a slot (the toolbar's is first).
    Finder inPopover(Finder f) => find.descendant(of: find.byType(ToolOptionsPopover), matching: f);

    testWidgets('colours and widths are chosen independently with one tap', (tester) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      await tester.tap(find.byKey(const ValueKey('color-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('width-2')));
      await tester.pump();
      expect(tools.activeConfig.colorIndex, 1);
      expect(tools.activeConfig.widthIndex, 2);
      expect(find.byType(ToolOptionsPopover), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the selected colour edits that slot alone; '
        'a new colour becomes a recent one', (tester) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      await tester.tap(find.byKey(const ValueKey('color-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('color-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('color-slot-editor')), findsOneWidget);
      expect(find.byType(ToolOptionsPopover), findsNothing, reason: 'not the pen options');
      expect(find.text('Feel'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing, reason: 'a popover on tablets');
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'FF0000');
      await tester.pump();
      expect(tools.activeConfig.colors[2], 0xFFFF0000);
      expect(tools.activeConfig.color, 0xFFFF0000);
      expect(tools.activeConfig.colors[0], PenDefaults.pen.colors[0]);
      expect(tools.recentColors, isEmpty, reason: 'noted when the editor closes');
      await tester.tapAt(const Offset(1200, 700));
      await tester.pumpAndSettle();
      expect(tools.recentColors, [0xFFFF0000]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long-press a size to edit it: a slider in mm with a live preview, nothing else', (
      tester,
    ) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      await tester.longPress(find.byKey(const ValueKey('width-0')));
      await tester.pumpAndSettle();
      expect(tools.activeConfig.widthIndex, 0);
      expect(find.byKey(const ValueKey('width-slot-editor')), findsOneWidget);
      expect(find.byType(StrokePreview), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Custom'), findsNothing);
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pump();
      expect(tools.activeConfig.widths[0], greaterThan(PenDefaults.pen.widths[0]));
      expect(tools.activeConfig.widths[1], PenDefaults.pen.widths[1]);
    });

    testWidgets('phones: slot editors are compact sheets', (tester) async {
      await pumpToolbar(tester, const Size(390, 800));
      await tester.tap(find.byKey(const ValueKey('color-0')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('color-slot-editor')), findsOneWidget);
      expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(320));
      expect(tester.takeException(), isNull);
    });

    testWidgets('quick colours and sizes: 3 each by default, 1 to 5, independent', (tester) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      expect(tools.activeConfig.colors, hasLength(3));
      expect(tools.activeConfig.widths, hasLength(3));
      await tester.tap(find.byTooltip('Pen (P)'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('More quick colours'), findsNothing, reason: 'folded under Toolbar');
      await tester.ensureVisible(find.text('Toolbar'));
      await tester.tap(find.text('Toolbar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('More quick colours'));
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('More quick colours'));
        await tester.pump();
      }
      expect(tools.activeConfig.colors, hasLength(5));
      expect(tools.activeConfig.colors.toSet(), hasLength(5), reason: 'new colours differ');
      expect(tools.activeConfig.widths, hasLength(3));
      final more = tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip('More quick colours'), matching: find.byType(IconButton)),
      );
      expect(more.onPressed, isNull);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Fewer quick sizes'));
        await tester.pump();
      }
      expect(tools.activeConfig.widths, hasLength(1));
      expect(tools.activeConfig.colors, hasLength(5));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('width-1')), findsNothing);
      // The anchored popover leaves the slots to the toolbar right above it.
      expect(find.byKey(const ValueKey('color-4')), findsOneWidget);
      expect(inPopover(find.byKey(const ValueKey('color-4'))), findsNothing);
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

    testWidgets('phones: one tap swaps the pen and the previous tool', (tester) async {
      final tools = await pumpToolbar(tester, const Size(390, 800));
      final previous = find.byKey(const ValueKey('previous-tool'));
      expect(find.byTooltip('Switch to eraser'), findsOneWidget);
      await tester.tap(previous);
      await tester.pump();
      expect(tools.tool, EditorTool.eraser);
      expect(find.byTooltip('Switch to pen'), findsOneWidget);
      await tester.tap(previous);
      await tester.pump();
      expect(tools.tool, EditorTool.pen);
      tools.tool = EditorTool.highlighter;
      await tester.pump();
      await tester.tap(previous);
      await tester.pump();
      expect(tools.tool, EditorTool.pen);
      // Slots stay at least 40 dp beside it; with 5 + 5 it steps aside.
      expect(tester.getSize(find.byKey(const ValueKey('color-0'))).width, greaterThanOrEqualTo(40));
      tools.updateConfig(
        InkTool.ballpoint,
        (c) => c.addColor(0xFF00AA00).addColor(0xFF7048E8).addWidth(6).addWidth(8),
      );
      await tester.pump();
      expect(previous, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phones: the tool switcher changes tools; the active one opens its options', (
      tester,
    ) async {
      final tools = await pumpToolbar(tester, const Size(390, 800));
      await tester.tap(find.byType(ToolSwitcherButton));
      await tester.pumpAndSettle();
      expect(find.byType(ToolSwitcherPanel), findsOneWidget);
      await tester.tap(find.text('Highlighter'));
      await tester.pumpAndSettle();
      expect(tools.tool, EditorTool.highlighter);
      expect(find.byType(ToolSwitcherPanel), findsNothing);

      await tester.tap(find.byType(ToolSwitcherButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ToolSwitcherButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pen'));
      await tester.pumpAndSettle();
      expect(find.byType(ToolOptionsPopover), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      // The sheet covers the toolbar, so it shows the quick slots itself.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byKey(const ValueKey('color-0')),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Feel'));
      await tester.pumpAndSettle();
      expect(find.byType(PenOptionsPanel), findsOneWidget);
      await tester.ensureVisible(find.text('Hold to snap shapes'));
      await tester.tap(find.text('Hold to snap shapes'));
      await tester.pump();
      expect(tools.holdToStraighten, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the active tool opens its options, for every tool', (tester) async {
      final tools = await pumpToolbar(tester, const Size(1280, 800));
      for (final (tooltip, title) in [
        ('Highlighter (H)', 'Highlighter'),
        ('Eraser (E)', 'Eraser'),
        ('Lasso (L)', 'Lasso'),
        ('Shapes (S)', 'Shapes'),
        ('Text (T)', 'Text'),
        ('Laser pointer (K)', 'Laser pointer'),
        ('Pen (P)', 'Pen'),
      ]) {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
        expect(find.byType(ToolOptionsPopover), findsNothing, reason: '$title: first selects');
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
        expect(inPopover(find.text(title)), findsOneWidget, reason: title);
        await tester.tapAt(const Offset(1200, 700));
        await tester.pumpAndSettle();
      }
      expect(tools.tool, EditorTool.pen);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one compact row on phones, tools and slots in a row on tablets', (tester) async {
      await pumpToolbar(tester, const Size(390, 800));
      final phone = tester.getSize(find.byType(EditorToolbar));
      expect(phone.width, lessThanOrEqualTo(390));
      expect(phone.height, lessThanOrEqualTo(56), reason: 'one row');
      expect(find.byType(ToolSwitcherButton), findsOneWidget);
      expect(find.byKey(const ValueKey('color-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('width-2')), findsOneWidget);
      // Every target stays S Pen-sized (44 on touch-first devices).
      for (final key in ['color-0', 'width-0']) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.width, greaterThanOrEqualTo(36));
        expect(size.height, greaterThanOrEqualTo(36));
      }
      await pumpToolbar(tester, const Size(1194, 834));
      expect(tester.getSize(find.byType(EditorToolbar)).height, 48, reason: 'one row');
      expect(find.byType(ToolSwitcherButton), findsNothing);
      expect(find.byTooltip('Lasso (L)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching tools keeps the tools in place', (tester) async {
      final tools = await pumpToolbar(tester, const Size(800, 800));
      final pen = tester.getCenter(find.byTooltip('Pen (P)'));
      for (final tool in EditorTool.values) {
        tools.tool = tool;
        await tester.pumpAndSettle();
        expect(tester.getCenter(find.byTooltip('Pen (P)')), pen, reason: tool.name);
      }
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
