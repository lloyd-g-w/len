import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/pen/option_controls.dart' show percent;
import 'package:len/features/editor/toolbar/tool_options_popover.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';
import 'package:len/features/editor/toolbar/toolbar_metrics.dart';
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
    expect(tester.getSize(find.byType(LaserStrip)).width, LaserStrip.widthFor(tools.laser, 44));
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

  testWidgets('options: header with Reset, preview, then the quick slot counts (1 to 5)', (
    tester,
  ) async {
    final tools = await pumpToolbar(tester, const Size(1280, 900));
    final before = ToolbarMetrics.strip(tools);
    await tester.tap(find.byTooltip('Laser pointer (K)'));
    await tester.pumpAndSettle();
    expect(inPopover(find.byType(LaserOptionsPanel)), findsOneWidget);
    expect(inPopover(find.text('Reset')), findsOneWidget);
    expect(inPopover(find.byType(LaserPreview)), findsOneWidget);
    expect(inPopover(find.byKey(const ValueKey('color-0'))), findsNothing, reason: 'anchored');
    expect(find.text('3 and 3'), findsOneWidget);
    // Open while the app runs: an earlier test may have opened it.
    if (find.byTooltip('More quick colours').evaluate().isEmpty) {
      await tester.ensureVisible(find.text('Quick colours and sizes'));
      await tester.tap(find.text('Quick colours and sizes'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byTooltip('More quick colours'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('More quick colours'));
      await tester.pump();
    }
    expect(tools.laser.colors, hasLength(5));
    expect(tools.laser.colors.toSet(), hasLength(5), reason: 'new colours differ');
    await tester.tap(find.byTooltip('More quick sizes'));
    await tester.pump();
    expect(tools.laser.sizes, hasLength(4));
    expect(tools.laser.sizes.toSet(), hasLength(4), reason: 'a new size differs');
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Fewer quick sizes'));
      await tester.pump();
    }
    expect(tools.laser.sizes, hasLength(1));
    final fewer = tester.widget<IconButton>(
      find.ancestor(of: find.byTooltip('Fewer quick sizes'), matching: find.byType(IconButton)),
    );
    expect(fewer.onPressed, isNull);
    await tester.pumpAndSettle();
    expect(inStrip(find.byKey(const ValueKey('color-4'))), findsOneWidget);
    expect(inStrip(find.byKey(const ValueKey('width-1'))), findsNothing);
    expect(ToolbarMetrics.strip(tools), before, reason: 'still 6 slots: the pen sets the reserve');

    // Reset puts the feel back and keeps the slots.
    await tester.tap(find.text('Dot'));
    await tester.pump();
    expect(tools.laser.mode, LaserMode.dot);
    await tester.tap(inPopover(find.text('Reset')));
    await tester.pump();
    expect(tools.laser.mode, LaserMode.trail);
    expect(tools.laser.colors, hasLength(5));
    expect(tools.laser.sizes, hasLength(1));
  });

  testWidgets('the panel\'s colour and size edit the selected slots', (tester) async {
    final tools = ToolSettings()..laser = const LaserConfig(colorIndex: 2);
    addTearDown(tools.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              child: SizedBox(width: 320, child: LaserOptionsPanel(tools: tools)),
            ),
          ),
        ),
      ),
    );
    final first = find.byType(ColorDot).first;
    final color = tester.widget<ColorDot>(first).color;
    await tester.tap(first);
    await tester.pump();
    expect(tools.laser.colors[2], color | 0xFF000000);
    expect(tools.laser.colors[0], LaserConfig.defaultColors[0]);
    await tester.drag(
      find.descendant(of: find.byType(LaserSizeSlider), matching: find.byType(Slider)),
      const Offset(300, 0),
    );
    await tester.pump();
    expect(tools.laser.sizes[1], LaserConfig.maxSize);
    expect(tools.laser.sizes[0], LaserConfig.defaultSizes[0]);
  });

  testWidgets('phones: the sheet shows the quick slots, which pick but do not edit', (
    tester,
  ) async {
    final tools = await pumpToolbar(tester, const Size(390, 800));
    // The switcher's active tool opens its options.
    await tester.tap(find.byType(ToolSwitcherButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laser'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(inPopover(find.byKey(const ValueKey('color-1'))), findsOneWidget);
    await tester.tap(inPopover(find.byKey(const ValueKey('color-1'))));
    await tester.pump();
    expect(tools.laser.colorIndex, 1);
    await tester.tap(inPopover(find.byKey(const ValueKey('color-1'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('color-slot-editor')), findsNothing);
  });
}
