import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/features/editor/chrome/canvas_context_menu.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/toolbar/tool_strip.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';

import 'document_editor_test.dart' show closeEditor, drawAt, inkOf, pumpEditor;

/// A quick tap with [count] fingers around [at].
Future<void> fingerTap(WidgetTester tester, int count, {Offset at = const Offset(400, 600)}) async {
  final gestures = [
    for (var i = 0; i < count; i++) await tester.startGesture(at + Offset(i * 80.0, 0)),
  ];
  for (final g in gestures) {
    await g.up();
  }
  await tester.pump();
}

void main() {
  testWidgets('two-finger tap undoes, three-finger tap redoes, with a HUD', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final page = s.pages.pagesOf(nb.id).first;
    s.settings.stylusOnly = true; // Fingers navigate, as with a stylus.
    await drawAt(tester, const Offset(300, 400));
    expect(inkOf(s, page), hasLength(2));

    await fingerTap(tester, 2);
    expect(inkOf(s, page), hasLength(1));
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);

    await fingerTap(tester, 3);
    expect(inkOf(s, page), hasLength(2));
    expect(find.text('Redo'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Switched off in the settings: nothing happens.
    s.preferences.fingerTapUndo = false;
    await fingerTap(tester, 2);
    expect(inkOf(s, page), hasLength(2));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await closeEditor(tester);
  });

  testWidgets('a finger long press opens the canvas menu; select all on page', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    s.preferences.stylusOnly = true;
    await tester.pump();
    final press = await tester.startGesture(const Offset(400, 500));
    await tester.pump(const Duration(milliseconds: 700));
    await press.up();
    await tester.pumpAndSettle();
    expect(find.byType(CanvasContextMenu), findsOneWidget);
    expect(find.text('Paste here'), findsNothing); // Nothing copied yet.
    await tester.tap(find.text('Select all on page'));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasContextMenu), findsNothing);
    expect(find.byTooltip('Delete (Del)'), findsOneWidget); // The selection's menu.
    await tester.tap(find.byTooltip('Delete (Del)'));
    await tester.pump();
    expect(inkOf(s, s.pages.pagesOf(nb.id).first), isEmpty);

    // A right click opens it too; tapping elsewhere dismisses it.
    await tester.tapAt(
      const Offset(400, 500),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('Add text here'), findsOneWidget);
    await tester.tapAt(const Offset(700, 1200));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasContextMenu), findsNothing);
    await closeEditor(tester);
  });

  testWidgets('closing a menu with a tap on the page does not draw', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(300, 700));
    await tester.pumpAndSettle();
    expect(inkOf(s, s.pages.pagesOf(nb.id).first), hasLength(1));
    // The canvas works again afterwards.
    await drawAt(tester, const Offset(300, 700));
    expect(inkOf(s, s.pages.pagesOf(nb.id).first), hasLength(2));
    await closeEditor(tester);
  });

  testWidgets('focus mode hides the chrome and comes back', (tester) async {
    await pumpEditor(tester);
    // The top bar's Undo (focus mode's puck has its own, later in the tree).
    final undo = find.byTooltip('Undo (Ctrl+Z)').first;
    bool barVisible() =>
        tester.getTopLeft(undo).dy >= 0 && undo.hitTestable().evaluate().isNotEmpty;
    expect(barVisible(), isTrue);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus mode'));
    await tester.pumpAndSettle();
    expect(barVisible(), isFalse);
    await tester.tap(find.byTooltip('Show toolbars (F11)'));
    await tester.pumpAndSettle();
    expect(barVisible(), isTrue);
    // Ctrl+. toggles too.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(barVisible(), isFalse);
    // The system back button leaves focus mode first, not the editor.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(barVisible(), isTrue);
    expect(find.byType(EditorScreen), findsOneWidget);
    await closeEditor(tester);
  });

  testWidgets('toolbar position, arrow keys and the add-page footer', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byTooltip('Pen (P)')).dy, lessThan(100)); // In the top bar.
    await tester.tap(find.text('Toolbar floating'));
    await tester.pumpAndSettle();
    expect(s.preferences.toolbarPlacement, ToolbarPlacement.floating);
    expect(tester.getCenter(find.byTooltip('Pen (P)')).dy, greaterThan(600));
    s.preferences.toolbarPlacement = ToolbarPlacement.docked;
    await tester.pumpAndSettle();

    // Arrow keys scroll page by page; End goes to the last page.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);

    // Scroll past the last page: "Add page" appends one.
    await tester.sendEventToBinding(
      PointerScrollEvent(position: const Offset(640, 450), scrollDelta: const Offset(0, 5000)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add page'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id), hasLength(4));
    expect(find.text('4 / 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('docked: in the bar when it fits, else a row under it; phones at the bottom', (
    tester,
  ) async {
    ToolbarDock dock() => tester.widget<EditorChrome>(find.byType(EditorChrome)).layout.dock;
    await pumpEditor(tester, size: const Size(1280, 900));
    expect(dock(), ToolbarDock.inline);
    expect(tester.getCenter(find.byTooltip('Pen (P)')).dy, lessThan(60));
    await closeEditor(tester);

    await pumpEditor(tester, size: const Size(800, 1300));
    expect(dock(), ToolbarDock.row);
    final bar = tester.getRect(find.byTooltip('Undo (Ctrl+Z)'));
    expect(tester.getCenter(find.byTooltip('Pen (P)')).dy, greaterThan(bar.bottom));
    expect(tester.getCenter(find.byTooltip('Pen (P)')).dy, lessThan(120));
    await closeEditor(tester);

    await pumpEditor(tester, size: const Size(390, 844));
    expect(dock(), ToolbarDock.bottom);
    expect(find.byTooltip('Pen (P)'), findsNothing); // The switcher shows the tool.
    expect(tester.getCenter(find.byType(ToolSwitcherButton)).dy, greaterThan(760));
    await closeEditor(tester);
  });

  testWidgets('the tool switcher lines up Insert with the tools', (tester) async {
    await pumpEditor(tester, size: const Size(390, 844));
    await tester.tap(find.byType(ToolSwitcherButton));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('Insert')).dy,
      closeTo(tester.getCenter(find.text('Laser')).dy, 0.5),
    );
    await tester.tapAt(const Offset(200, 300));
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('no divider trails the tools when the tool has no quick controls', (tester) async {
    await pumpEditor(tester, size: const Size(390, 844));
    double opacity() => tester
        .widget<Opacity>(
          find.descendant(of: find.byType(StripDivider), matching: find.byType(Opacity)),
        )
        .opacity;
    expect(opacity(), 1); // The pen: its colour and width slots follow.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL); // Lasso: nothing follows.
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await closeEditor(tester);
  });

  testWidgets('a chrome menu keeps 8 dp from the screen edge on a phone', (tester) async {
    await pumpEditor(tester, size: const Size(390, 844));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    final items = find.byType(MenuItemButton);
    final panel = tester.getRect(
      find.ancestor(of: items.first, matching: find.byType(Material)).first,
    );
    expect(panel.right, lessThanOrEqualTo(390 - 8));
    expect(panel.left, greaterThanOrEqualTo(8));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('phones open Page and View in place of the ⋯ menu, with a way back', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(390, 844));
    final pages = s.pages.pagesOf(nb.id).length;
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page'));
    await tester.pumpAndSettle();
    // The page commands replace the menu instead of covering it.
    expect(find.text('Duplicate page'), findsOneWidget);
    expect(find.text('Search in notebook'), findsNothing);
    await tester.tap(find.text('Page')); // The back row.
    await tester.pumpAndSettle();
    expect(find.text('Search in notebook'), findsOneWidget);
    expect(find.text('Duplicate page'), findsNothing);
    await tester.tap(find.text('Page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add page after'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id), hasLength(pages + 1));
    // Reopened (also after Esc in a submenu), the menu starts at the top.
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Search in notebook'), findsOneWidget);
    // Recordings only once there are any; no ellipsis on what asks nothing.
    expect(find.text('Record audio'), findsOneWidget);
    expect(find.text('Recordings'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('wide ⋯ submenus show one rounded chevron, not a second arrow', (tester) async {
    await pumpEditor(tester, size: const Size(1280, 800));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    final view = find.ancestor(of: find.text('View'), matching: find.byType(SubmenuButton));
    expect(
      find.descendant(of: view, matching: find.byIcon(Symbols.chevron_right_rounded)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.arrow_right), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('quick controls cut off by a narrow bar fade at the edge', (tester) async {
    await pumpEditor(tester, size: const Size(390, 844));
    expect(find.byKey(const ValueKey('scroll-fade')), findsNothing); // Everything fits.
    await closeEditor(tester);
    await pumpEditor(tester, size: const Size(280, 700));
    expect(find.byKey(const ValueKey('scroll-fade')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('the phone editor meets the tap-target and label guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpEditor(tester, size: const Size(390, 844));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    // The search bar too.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await closeEditor(tester);
    semantics.dispose();
  });

  testWidgets('Home goes to the first page of a paged notebook', (tester) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await closeEditor(tester);
  });
}
