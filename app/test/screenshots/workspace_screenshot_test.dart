import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/features/editor/toolbar/toolbar_config.dart';
import 'package:len/features/editor/toolbar/toolbar_editor.dart';
import 'package:len/ink/tool_settings.dart';

import 'screenshot_harness.dart';
import 'toolbar_screenshot_test.dart' show writtenNotebook;

// Screenshots of the workspace features: split view, the toolbar in edit
// mode with favourite pens, presentation mode.

const tablet = Size(1280, 800);
const desktop = Size(1440, 900);
const phone = Size(390, 844);

const favourites = [
  FavouritePen(tool: EditorTool.pen, color: 0xFF1A2233, width: 1.5),
  FavouritePen(tool: EditorTool.pen, color: 0xFFDC2626, width: 2.5),
  FavouritePen(tool: EditorTool.highlighter, color: 0xFFFACC15, width: 16),
];

/// The seeded library with "Lecture notes" and "Whiteboard" open in tabs.
Future<AppServices> openTabs(WidgetTester tester, Size size, ThemeMode mode) async {
  setWindow(tester, size);
  final s = seededServices();
  addTearDown(s.dispose);
  final lecture = writtenNotebook(s);
  final board = s.notebooks.list().firstWhere((n) => n.kind == NotebookKind.canvas);
  s.openNotebooks
    ..open(board)
    ..open(lecture);
  await pumpApp(tester, s, const EditorWorkspace(), mode: mode);
  return s;
}

Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  setUpAll(loadRealFonts);

  for (final (name, size) in [('tablet', tablet), ('desktop', desktop)]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('split view $name ${mode.name}', (tester) async {
        final s = await openTabs(tester, size, mode);
        await tester.tap(find.byTooltip('Open in split view'));
        await settle(tester);
        await shoot(tester, 'split_menu_${name}_${mode.name}');
        await tester.tap(find.text('Whiteboard').last);
        await settle(tester);
        expect(find.byType(EditorScreen), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await shoot(tester, 'split_${name}_${mode.name}');

        // Dragging a lasso selection over the other pane.
        final page = find.byType(PagedDocumentView);
        final at = tester.getTopLeft(page) + const Offset(150, 230);
        await tester.tapAt(at, buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
        await settle(tester);
        await tester.tap(find.text('Select all on page'));
        await settle(tester);
        final frame = tester.getCenter(page) - const Offset(80, 140);
        final drag = await tester.startGesture(frame, kind: PointerDeviceKind.mouse);
        for (var i = 1; i <= 12; i++) {
          await drag.moveTo(frame + Offset(i * 50.0, 0));
          await tester.pump();
        }
        await settle(tester);
        await shoot(tester, 'split_drag_${name}_${mode.name}');
        await drag.up();
        await settle(tester);
        s.openNotebooks.closeSplit();
        await settle(tester);
        await close(tester);
      });
    }
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('split view: one notebook twice, parked in portrait ${mode.name}', (tester) async {
      final s = await openTabs(tester, tablet, mode);
      s.openNotebooks.openSplit(s.openNotebooks.activeId!);
      await settle(tester);
      expect(find.byType(EditorScreen), findsNWidgets(2));
      await shoot(tester, 'split_same_tablet_${mode.name}');
      // Turned to portrait: the second pane is parked, alive.
      setWindow(tester, const Size(800, 1280));
      await settle(tester);
      expect(find.byType(EditorScreen), findsOneWidget);
      await shoot(tester, 'split_parked_portrait_${mode.name}');
      setWindow(tester, tablet);
      await settle(tester);
      expect(find.byType(EditorScreen), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await shoot(tester, 'split_restored_tablet_${mode.name}');
      await close(tester);
    });
  }

  for (final (name, size, dpr) in [('tablet', tablet, 1.0), ('phone', phone, 2.0)]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('toolbar edit mode $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final s = seededServices();
        addTearDown(s.dispose);
        var config = const ToolbarConfig().toggle(EditorTool.laser);
        for (final f in favourites) {
          config = config.addFavourite(f);
        }
        s.preferences.toolbarConfig = config;
        await pumpApp(tester, s, EditorScreen(notebook: writtenNotebook(s)), mode: mode);
        Rect toolbar() => tester.getRect(find.byType(EditorToolbar)).inflate(8);
        await shoot(tester, 'toolbar_favourites_${name}_${mode.name}', crop: toolbar());
        if (name == 'phone') {
          await tester.tap(find.bySemanticsLabel(RegExp('Switch tools')));
          await settle(tester);
          await shoot(tester, 'toolbar_switcher_favourites_${mode.name}');
          await tester.tapAt(const Offset(200, 300));
          await settle(tester);
        }
        await tester.tap(find.byTooltip('More options'));
        await settle(tester);
        await tester.tap(find.text('Toolbar'));
        await settle(tester);
        if (name == 'tablet') await shoot(tester, 'toolbar_menu_${mode.name}');
        await tester.tap(find.text('Customise toolbar…'));
        await settle(tester);
        expect(find.byType(ToolbarEditor), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'toolbar_edit_${name}_${mode.name}');
        await shoot(
          tester,
          'toolbar_edit_crop_${name}_${mode.name}',
          crop: tester.getRect(find.byType(ToolbarEditor)).inflate(8),
        );
        await close(tester);
      });
    }
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('presentation ${mode.name}', (tester) async {
      setWindow(tester, tablet);
      final s = seededServices();
      addTearDown(s.dispose);
      await pumpApp(tester, s, EditorScreen(notebook: writtenNotebook(s)), mode: mode);
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await tester.tap(find.text('Present'));
      await settle(tester);
      // A laser stroke over the page.
      final laser = await tester.startGesture(
        const Offset(500, 300),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 1; i <= 12; i++) {
        await laser.moveTo(Offset(500 + i * 18.0, 300 + (i % 4) * 10.0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await shoot(tester, 'present_${mode.name}');
      await laser.up();
      await close(tester);
    });
  }
}
