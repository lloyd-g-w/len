import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/documents/export/export_sheet.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';
import 'package:len/features/editor/chrome/editor_top_bar.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_layers.dart';
import 'package:len/features/editor/editor_toolbar.dart';
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

  testWidgets('a narrow tool row (a split pane on touch) shrinks its cells; everything shows', (
    tester,
  ) async {
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    for (final width in [634.0, 700.0, 900.0]) {
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
      for (final key in ['color-0', 'width-2']) {
        final slot = tester.getRect(find.byKey(ValueKey(key)));
        expect(row.contains(slot.topLeft) && row.contains(slot.bottomRight), isTrue, reason: key);
      }
      expect(tester.getRect(find.byTooltip('Pen (P)')).left, greaterThanOrEqualTo(row.left));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('phones: the bottom row fits 3 + 3 slots down to 320 dp, touch-sized when it can '
      '(beside the previous tool when the slots keep 40 dp)', (tester) async {
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    for (final (width, cell, previous) in [
      (430.0, 44.0, true),
      (390.0, 41.0, true),
      (320.0, 36.0, false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: width,
                child: EditorToolbar(tools: tools, dock: ToolbarDock.bottom),
              ),
            ),
          ),
        ),
      );
      for (final tool in [EditorTool.pen, EditorTool.shape]) {
        tools.tool = tool;
        await tester.pumpAndSettle();
        final slot = tester.getRect(find.byKey(const ValueKey('width-2')));
        final row = tester.getRect(find.byType(EditorToolbar));
        expect(slot.right, lessThanOrEqualTo(row.right), reason: '$width ${tool.name}');
        expect(slot.width, cell, reason: '$width ${tool.name}');
        expect(
          find.byKey(const ValueKey('previous-tool')),
          previous ? findsOneWidget : findsNothing,
          reason: '$width',
        );
      }
    }
  });

  testWidgets('the laser has three colour slots; picking one sets its colour', (tester) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    await tester.tap(find.byTooltip('Laser pointer (K)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('laser-slot-1')));
    await tester.pumpAndSettle();
    expect(toolsOf(tester).laser.color, LaserStrip.colors[1]);
    await closeEditor(tester);
  });
}
