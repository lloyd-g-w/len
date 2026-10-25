import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/documents/export/export_sheet.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';
import 'package:len/features/editor/chrome/editor_top_bar.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_layers.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/pen/slot_button.dart';
import 'package:len/features/editor/toolbar/tool_cluster.dart';
import 'package:len/features/editor/toolbar/tool_options_popover.dart';
import 'package:len/features/editor/tools/laser_strip.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';

import 'content_tools_ui_test.dart' show openCanvas;
import 'document_editor_test.dart' show closeEditor, pumpEditor;

/// The editor toolbar in the editor: it never rebuilds the canvas, Insert ⊕,
/// the "⋯" menu and its shortcuts.
void main() {
  ToolSettings toolsOf(WidgetTester tester) =>
      tester.widget<EditorToolbar>(find.byType(EditorToolbar)).tools;

  testWidgets('switching tools, picking slots and opening the options rebuild only the toolbar', (
    tester,
  ) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    final builds = <Type, int>{};
    debugOnRebuildDirtyWidget = (element, _) =>
        builds.update(element.widget.runtimeType, (n) => n + 1, ifAbsent: () => 1);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    for (final tool in [
      'Highlighter (H)',
      'Eraser (E)',
      'Lasso (L)',
      'Shapes (S)',
      'Text (T)',
      'Laser pointer (K)',
      'Pen (P)',
    ]) {
      await tester.tap(find.byTooltip(tool));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('color-1')));
    await tester.tap(find.byKey(const ValueKey('width-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pen (P)'));
    await tester.pumpAndSettle();
    expect(find.byType(ToolOptionsPopover), findsOneWidget);
    await tester.tapAt(const Offset(1200, 800));
    await tester.pumpAndSettle();
    debugOnRebuildDirtyWidget = null;

    expect(toolsOf(tester).activeConfig.colorIndex, 1);
    for (final type in [
      EditorLayers,
      EditorCanvas,
      PagedDocumentView,
      EditorChrome,
      EditorTopBar,
      EditorToolbar,
    ]) {
      expect(builds[type], isNull, reason: '$type rebuilt ${builds[type]} times');
    }
    expect(builds[ListenableBuilder], greaterThan(0), reason: 'the toolbar parts did');
    await closeEditor(tester);
  });

  testWidgets('Esc closes the options popover, and the keyboard returns to the editor', (
    tester,
  ) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    await tester.tap(find.byTooltip('Pen (P)'));
    await tester.pumpAndSettle();
    expect(find.byType(ToolOptionsPopover), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ToolOptionsPopover), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(toolsOf(tester).tool, EditorTool.eraser);
    await closeEditor(tester);
  });

  testWidgets('Insert ⊕ offers images and PDF pages in notebooks (adding pages lives in the '
      'page menu)', (tester) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();
    expect(find.text('Image…'), findsOneWidget);
    expect(find.text('Pages from PDF…'), findsOneWidget);
    expect(find.textContaining('template'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('Insert ⊕ on a canvas offers images only', (tester) async {
    await openCanvas(tester);
    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();
    expect(find.text('Image…'), findsOneWidget);
    expect(find.text('Pages from PDF…'), findsNothing);
  });

  testWidgets('the ⋯ menu: search, export, page, view, settings; draw with finger on touch '
      'screens (with a mouse once a stylus was seen); Ctrl+E exports', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    Future<void> openMenu() async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
    }

    await openMenu();
    for (final item in ['Search in notebook', 'Export…', 'Page', 'View', 'Settings']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    for (final gone in ['Rename notebook…', 'Show tool names', 'Customise toolbar…', 'Present']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    // Automatic on a touch screen: fingers draw until a stylus is seen;
    // the switch is on and turns palm rejection on.
    await tester.tap(find.text('Draw with finger'));
    await tester.pumpAndSettle();
    expect(toolsOf(tester).stylusOnly, isTrue);
    await openMenu();
    await tester.tap(find.text('Draw with finger'));
    await tester.pumpAndSettle();
    expect(toolsOf(tester).stylusOnly, isFalse);

    // With a mouse it shows only once a stylus was seen.
    Targets.debugTouchFirst = false;
    addTearDown(() => Targets.debugTouchFirst = null);
    s.preferences.stylusOnly = null;
    await tester.pumpAndSettle();
    await openMenu();
    expect(find.text('Draw with finger'), findsNothing, reason: 'no stylus seen yet');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    s.preferences.stylusOnly = true;
    await tester.pumpAndSettle();
    await openMenu();
    expect(find.text('Draw with finger'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(ExportSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('a narrow tool row (a split pane on touch) shrinks its cells; every tool shows', (
    tester,
  ) async {
    Targets.debugTouchFirst = true;
    addTearDown(() => Targets.debugTouchFirst = null);
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    for (final (width, cell) in [(300.0, 40.0), (634.0, 48.0), (900.0, 48.0)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: EditorToolbar(tools: tools, dock: ToolbarDock.row),
              ),
            ),
          ),
        ),
      );
      final row = tester.getRect(find.byType(EditorToolbar));
      final pen = tester.getRect(find.byTooltip('Pen (P)'));
      final laser = tester.getRect(find.byTooltip('Laser pointer (K)'));
      expect(pen.left, greaterThanOrEqualTo(row.left), reason: '$width');
      expect(laser.right, lessThanOrEqualTo(row.right), reason: '$width');
      expect(laser.center.dx - pen.center.dx, 6 * cell, reason: '$width');
      // The tools alone, centred: no quick controls in the main bar.
      expect(find.byKey(const ValueKey('color-0')), findsNothing);
      final cluster = tester.getRect(find.byType(ToolCluster));
      expect(cluster.center.dx, closeTo(row.center.dx, 0.5), reason: '$width');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('phones: the switcher and the previous tool at the bottom, the sub-bar above them '
      'scrolling when its slots do not fit', (tester) async {
    await pumpEditor(tester, size: const Size(320, 640));
    final tools = toolsOf(tester);
    final screen = tester.getRect(find.byType(EditorChrome));
    final switcher = tester.getRect(find.byKey(const ValueKey('tool-switcher')));
    expect(find.byKey(const ValueKey('previous-tool')), findsOneWidget);
    final pill = tester.getRect(find.byKey(const ValueKey('tool-sub-bar')));
    expect(pill.bottom, lessThan(switcher.top));
    expect(pill.center.dx, closeTo(screen.center.dx, 0.5));
    tools.updateConfig(
      InkTool.ballpoint,
      (c) => c.addColor(0xFF00AA00).addColor(0xFF7048E8).addWidth(6).addWidth(8),
    );
    await tester.pumpAndSettle();
    final wide = tester.getRect(find.byKey(const ValueKey('tool-sub-bar')));
    expect(wide.left, greaterThanOrEqualTo(screen.left));
    expect(wide.right, lessThanOrEqualTo(screen.right));
    expect(find.byKey(const ValueKey('scroll-fade')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('the laser has colour and size slots; picking one sets its colour', (tester) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    await tester.tap(find.byTooltip('Laser pointer (K)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('color-1')));
    await tester.pumpAndSettle();
    expect(toolsOf(tester).laser.color, LaserConfig.defaultColors[1]);
    final strip = find.byType(LaserStrip);
    expect(find.descendant(of: strip, matching: find.byType(SlotButton)), findsNWidgets(6));
    await tester.tap(find.byKey(const ValueKey('width-2')));
    await tester.pumpAndSettle();
    expect(toolsOf(tester).laser.size, LaserConfig.defaultSizes[2]);
    await closeEditor(tester);
  });
}
