import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/features/documents/overview/page_commands.dart';
import 'package:len/features/editor/chrome/canvas_context_menu.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';
import 'package:len/features/editor/document/add_page_footer.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/toolbar/tool_strip.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';
import 'package:len/ui/design_tokens.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'document_editor_test.dart' show closeEditor, drawAt, inkOf, pumpEditor;
import 'support/semantics_actions.dart';

/// The text of a menu row (its child, maybe wrapped in semantics).
String? _label(MenuItemButton row) => switch (row.child) {
  final Text t => t.data,
  Semantics(child: final Text t) => t.data,
  _ => null,
};

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
    expect(find.text('Paste here'), findsNothing); // Both clipboards are empty.
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
    // Content only: page commands live in ⋯ → Page.
    expect(find.text('Add page after'), findsNothing);
    expect(find.text('Bookmark page'), findsNothing);
    await tester.tapAt(const Offset(700, 1200));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasContextMenu), findsNothing);
    await closeEditor(tester);
  });

  testWidgets('Paste here shows when the system clipboard holds something or Len copied ink', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Object? peek = const ['text'];
    var peeks = 0;
    messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (call) async {
      if (call.method == 'peek') peeks++;
      return switch (call.method) {
        'peek' => peek,
        'files' => const <Object>[],
        _ => null,
      };
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('pasteboard'),
        (call) async => const {'files', 'peek'}.contains(call.method) ? const <Object>[] : null,
      ),
    );
    Future<bool> offersPaste() async {
      await tester.tapAt(
        const Offset(400, 500),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('Add text here'), findsOneWidget);
      final offered = find.text('Paste here').evaluate().isNotEmpty;
      await tester.tapAt(const Offset(700, 1200));
      await tester.pumpAndSettle();
      return offered;
    }

    expect(await offersPaste(), isTrue, reason: 'text');
    peek = const ['image'];
    expect(await offersPaste(), isTrue, reason: 'an image');
    peek = const <Object>[];
    expect(await offersPaste(), isFalse, reason: 'nothing');
    peek = null; // The platform can't tell (Firefox, Safari): the tap reads it.
    expect(await offersPaste(), isTrue, reason: 'unknown');
    expect(peeks, 4);

    // Ink copied in Len: offered without asking the system clipboard.
    peek = const <Object>[];
    await drawAt(tester, const Offset(300, 700));
    s.clipboard.put(inkOf(s, s.pages.pagesOf(nb.id).first), const [], Rect.zero);
    expect(await offersPaste(), isTrue, reason: 'Len’s own clipboard');
    expect(peeks, 4);
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

  testWidgets('⋯ → View: seven rows, its switches go both ways', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    Future<void> openView() async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
    }

    await openView();
    final view = find.ancestor(of: find.text('Fit width'), matching: find.byType(MenuItemButton));
    final rows = find.descendant(
      // The innermost menu panel (Flutter's private _MenuPanel): View's own.
      of: find
          .ancestor(
            of: view,
            matching: find.byWidgetPredicate((w) => '${w.runtimeType}' == '_MenuPanel'),
          )
          .first,
      matching: find.byType(MenuItemButton),
    );
    expect(
      [for (final e in rows.evaluate()) _label(e.widget as MenuItemButton)],
      [
        'Fit page',
        'Fit width',
        'Automatic zoom',
        'One page at a time',
        'Floating toolbar',
        'Zoom window',
        'Focus mode',
      ],
    );
    for (final (label, single, floating) in [
      ('One page at a time', 'single', ToolbarPlacement.docked),
      ('Floating toolbar', 'single', ToolbarPlacement.floating),
      ('One page at a time', 'continuous', ToolbarPlacement.floating),
      ('Floating toolbar', 'continuous', ToolbarPlacement.docked),
    ]) {
      if (find.text(label).evaluate().isEmpty) await openView();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(s.settings.pageFlow, single, reason: label);
      expect(s.preferences.toolbarPlacement, floating, reason: label);
    }
    await closeEditor(tester);
  });

  testWidgets('toolbar position, arrow keys and the add-page footer', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byTooltip('Pen (P)')).dy, lessThan(100)); // In the top bar.
    await tester.tap(find.text('Floating toolbar'));
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
    expect(find.text('Hold for a template'), findsOneWidget, reason: 'until held once');
    await tester.tap(find.text('Add page'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id), hasLength(4));
    expect(find.text('4 / 4'), findsOneWidget);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: const Offset(640, 450), scrollDelta: const Offset(0, 5000)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hold for a template'), findsOneWidget);
    await tester.longPress(find.text('Add page'));
    await tester.pumpAndSettle();
    expect(find.text('Music staff'), findsWidgets, reason: 'the template chooser');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Add page'), findsOneWidget);
    expect(find.text('Hold for a template'), findsNothing, reason: 'learnt');
    expect(s.settings.seenTips, contains('add-page-hold'));
    // With a pointer the gesture is a right click (R14-6).
    Targets.debugTouchFirst = false;
    expect(AddPageFooter.caption, 'Right-click for a template');
    Targets.debugTouchFirst = null;

    // It follows the last page as the document scrolls, and leaves the
    // screen with it.
    final doc = tester.widget<AddPageFooter>(find.byType(AddPageFooter)).doc;
    for (final dy in [10.0, 15.0]) {
      doc.viewport.panBy(Offset(0, dy));
      await tester.pump();
      final button = tester.getRect(find.byType(OutlinedButton));
      final page = doc.lastPageOnScreen!;
      expect(button.top, moreOrLessEquals(page.bottom + AddPageFooter.gap));
      expect(button.center.dx, moreOrLessEquals(page.center.dx));
      expect(button.height, AddPageFooter.height);
    }
    doc.viewport.panBy(const Offset(0, 3000));
    await tester.pump();
    expect(find.text('Add page'), findsNothing);
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

    // A phone held sideways: one row, the switcher inside the top bar.
    await pumpEditor(tester, size: const Size(844, 390));
    expect(dock(), ToolbarDock.slim);
    expect(tester.getCenter(find.byType(ToolSwitcherButton)).dy, lessThan(60));
    expect(tester.widget<EditorChrome>(find.byType(EditorChrome)).layout.covered.top, 52);
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
    await tester.tap(find.text('Duplicate page'));
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

  testWidgets('Page ▸ is the one page menu; "Add page after" held asks for a template', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 800));
    final pages = s.pages.pagesOf(nb.id).length;
    Future<void> openPageMenu() async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Page'));
      await tester.pumpAndSettle();
    }

    await openPageMenu();
    for (final c in PageCommand.menu) {
      expect(find.text(c.labelFor()), findsOneWidget, reason: c.name);
    }
    // Hovering the row says how to reach the template (screen readers get
    // an action instead).
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('Add page after')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Hold or right-click for a template'), findsOneWidget);
    expect(find.text('Add page with template…'), findsNothing);
    expect(find.text('Add page to outline…'), findsNothing);
    await tester.longPress(find.text('Add page after'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate page'), findsNothing, reason: 'the menu closed');
    expect(find.text('Music staff'), findsWidgets, reason: 'the template chooser');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Music staff'), findsNothing, reason: 'Esc closes the chooser');
    expect(s.pages.pagesOf(nb.id), hasLength(pages));

    await openPageMenu();
    await tester.tap(find.text('Add page after'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id), hasLength(pages + 1));
    await closeEditor(tester);
  });

  testWidgets('screen readers offer "Add page with template" on "Add page after"', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpEditor(tester, size: const Size(1280, 800));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page'));
    await tester.pumpAndSettle();
    await performCustomAction(tester, 'Add page after', 'Add page with template');
    expect(find.text('Duplicate page'), findsNothing, reason: 'the menu closed');
    expect(find.text('Music staff'), findsWidgets, reason: 'the template chooser');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    semantics.dispose();
    await closeEditor(tester);
  });

  for (final touch in [true, false]) {
    testWidgets('shortcut hints follow the input, not the width (touch: $touch)', (tester) async {
      Targets.debugTouchFirst = touch;
      addTearDown(() => Targets.debugTouchFirst = null);
      await pumpEditor(tester, size: const Size(1280, 800));
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Search in notebook'), findsOneWidget);
      expect(find.text('Ctrl+F'), touch ? findsNothing : findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await closeEditor(tester);
    });
  }

  testWidgets('phones show ↷ only while there is something to redo', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(390, 844));
    final redo = find.byTooltip('Redo (Ctrl+Shift+Z)');
    expect(redo, findsNothing);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)').first);
    await tester.pumpAndSettle();
    expect(redo, findsOneWidget);
    await tester.tap(redo);
    await tester.pumpAndSettle();
    expect(redo, findsNothing);
    expect(s.pages.pagesOf(nb.id), hasLength(greaterThan(1)));
    await closeEditor(tester);
  });

  testWidgets('wide ⋯ submenus show one rounded chevron, not a second arrow', (tester) async {
    await pumpEditor(tester, size: const Size(1280, 800));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    final view = find.ancestor(of: find.text('View'), matching: find.byType(SubmenuButton));
    expect(
      find.descendant(of: view, matching: find.byIcon(Symbols.chevron_right_sharp)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.arrow_right), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('a single page shows no "1 / 1" indicator', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(390, 844));
    final indicator = find.byKey(const ValueKey('page-indicator'));
    expect(indicator, findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete page'));
      await tester.pumpAndSettle();
    }
    expect(s.pages.pagesOf(nb.id), hasLength(1));
    expect(indicator, findsNothing);
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
