import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/pen/option_controls.dart' show percent;
import 'package:len/features/editor/toolbar/tool_options_popover.dart';
import 'package:len/features/editor/toolbar/tool_sub_bar.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';
import 'package:len/features/editor/tools/laser_options_panel.dart';
import 'package:len/features/editor/tools/laser_preview.dart';
import 'package:len/features/editor/tools/laser_slots.dart';
import 'package:len/features/editor/tools/laser_strip.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/color_dot.dart';

/// The laser pointer's quick slots in the toolbar and its options popover:
/// edited, counted and reset like the pen's.
void main() {
  Future<ToolSettings> pumpToolbar(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tools = ToolSettings()..tool = EditorTool.laser;
    addTearDown(tools.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EditorToolbar(
                  tools: tools,
                  dock: size.width < 600 ? ToolbarDock.bottom : ToolbarDock.row,
                ),
                ToolSubBar(tools: tools),
              ],
            ),
          ),
        ),
      ),
    );
    return tools;
  }

  Finder inStrip(Finder f) => find.descendant(of: find.byType(LaserStrip), matching: f);
  Finder inPopover(Finder f) => find.descendant(of: find.byType(ToolOptionsPopover), matching: f);

  testWidgets('three colour and three size slots, each picked with one tap', (tester) async {
    final tools = await pumpToolbar(tester, const Size(1280, 800));
    expect(inStrip(find.byKey(const ValueKey('color-2'))), findsOneWidget);
    expect(inStrip(find.byKey(const ValueKey('width-2'))), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('color-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('width-0')));
    await tester.pump();
    expect(tools.laser.color, LaserConfig.defaultColors[1]);
    expect(tools.laser.size, LaserConfig.defaultSizes[0]);
    expect(find.byType(ToolOptionsPopover), findsNothing);
  });

  testWidgets('tapping the selected colour edits that slot; a new colour becomes recent', (
    tester,
  ) async {
    final tools = await pumpToolbar(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const ValueKey('color-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('color-slot-editor')), findsOneWidget);
    expect(find.byType(ToolOptionsPopover), findsNothing, reason: 'not the laser options');
    // The laser's palette: six bright colours.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('color-slot-editor')),
        matching: find.byType(ColorDot),
      ),
      findsAtLeastNWidgets(LaserConfig.presets.length),
    );
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '00FFAA');
    await tester.pump();
    expect(tools.laser.colors[0], 0xFF00FFAA);
    expect(tools.laser.colors[1], LaserConfig.defaultColors[1]);
    expect(tools.recentColors, isEmpty, reason: 'noted when the editor closes');
    await tester.tapAt(const Offset(1200, 700));
    await tester.pumpAndSettle();
    expect(tools.recentColors, [0xFF00FFAA]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('size slots say their size, as the slider does', (tester) async {
    final tools = await pumpToolbar(tester, const Size(1280, 800));
    final want = percent(
      (tools.laser.sizes[2] - LaserConfig.minSize) / (LaserConfig.maxSize - LaserConfig.minSize),
    );
    expect(find.byTooltip('Size $want'), findsOneWidget);
  });

  testWidgets('long-press a size to edit it: a preview and a slider', (tester) async {
    final tools = await pumpToolbar(tester, const Size(1280, 800));
    await tester.longPress(find.byKey(const ValueKey('width-2')));
    await tester.pumpAndSettle();
    expect(tools.laser.sizeIndex, 2);
    expect(find.byKey(const ValueKey('width-slot-editor')), findsOneWidget);
    expect(find.byType(LaserPreview), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();
    expect(tools.laser.sizes[2], greaterThan(LaserConfig.defaultSizes[2]));
    expect(tools.laser.sizes[2], tools.laser.sizes[2].roundToDouble(), reason: 'whole pixels');
    expect(tools.laser.sizes[0], LaserConfig.defaultSizes[0]);
  });

  testWidgets('options: header with Reset, preview, dot or trail; no colours, sizes or counts', (
    tester,
  ) async {
    final tools = await pumpToolbar(tester, const Size(1280, 900));
    await tester.tap(find.byTooltip('Laser pointer (K)'));
    await tester.pumpAndSettle();
    expect(inPopover(find.byType(LaserOptionsPanel)), findsOneWidget);
    expect(inPopover(find.text('Reset')), findsOneWidget);
    expect(inPopover(find.byType(LaserPreview)), findsOneWidget);
    expect(inPopover(find.byType(ColorDot)), findsNothing, reason: 'colours are the slots');
    expect(inPopover(find.byType(LaserSizeSlider)), findsNothing, reason: 'sizes too');
    expect(inPopover(find.textContaining('Quick')), findsNothing, reason: 'counts: Settings');
    expect(inPopover(find.text('Feel')), findsNothing, reason: 'nothing collapsed');

    // Reset puts the rest back and keeps the slots.
    tools.laser = tools.laser.withColor(0, 0xFF00AA00);
    await tester.pump();
    await tester.tap(find.text('Dot'));
    await tester.pump();
    expect(tools.laser.mode, LaserMode.dot);
    await tester.tap(inPopover(find.text('Reset')));
    await tester.pump();
    expect(tools.laser.mode, LaserMode.trail);
    expect(tools.laser.colors[0], 0xFF00AA00);
  });

  testWidgets('phones: the options are a sheet without the quick slots', (tester) async {
    final tools = await pumpToolbar(tester, const Size(390, 800));
    // The switcher's active tool opens its options.
    await tester.tap(find.byType(ToolSwitcherButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laser'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(inPopover(find.byType(LaserOptionsPanel)), findsOneWidget);
    expect(inPopover(find.byKey(const ValueKey('color-1'))), findsNothing);
    await tester.tap(inPopover(find.text('Dot')));
    await tester.pump();
    expect(tools.laser.mode, LaserMode.dot);
  });
}
