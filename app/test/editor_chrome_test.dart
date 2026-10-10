import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/features/editor/chrome/canvas_context_menu.dart';
import 'package:len/features/editor/chrome/toolbar_slot.dart';
import 'package:len/features/editor/editor_screen.dart';

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
    s.preferences.twoFingerTapUndo = false;
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
    bool barVisible() =>
        tester.getTopLeft(find.byTooltip('Undo (Ctrl+Z)')).dy >= 0 &&
        find.byTooltip('Undo (Ctrl+Z)').hitTestable().evaluate().isNotEmpty;
    expect(barVisible(), isTrue);
    await tester.tap(find.byTooltip('Focus mode (F11)'));
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
    await tester.tap(find.text('Toolbar position'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bottom'));
    await tester.pumpAndSettle();
    expect(s.preferences.toolbarPlacement, ToolbarPlacement.bottom);
    expect(tester.getCenter(find.byTooltip('Pen (P)')).dy, greaterThan(700));

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

  testWidgets('automatic placement: top only from 960 px when the toolbar fits', (tester) async {
    expect(
      resolvePlacement(ToolbarPlacement.auto, 800, toolbarWidth: 600),
      ToolbarPlacement.bottom,
    );
    expect(resolvePlacement(ToolbarPlacement.auto, 1280, toolbarWidth: 700), ToolbarPlacement.top);
    expect(
      resolvePlacement(ToolbarPlacement.auto, 960, toolbarWidth: 950),
      ToolbarPlacement.bottom,
    );
    expect(resolvePlacement(ToolbarPlacement.top, 400, toolbarWidth: 700), ToolbarPlacement.top);

    final (_, _) = await pumpEditor(tester, size: const Size(800, 1300));
    expect(tester.getCenter(find.byTooltip('Pen (P)')).dy, greaterThan(1100));
    await closeEditor(tester);
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
