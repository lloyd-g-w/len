import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/chrome/tool_puck.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';

import 'document_editor_test.dart' show closeEditor, drawAt, inkOf, pumpEditor;

Future<void> toggleFocus(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.f11);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('focus mode keeps the tools at hand in a puck: switch tools, undo', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    expect(find.byType(ToolPuck), findsNothing, reason: 'only in focus mode');
    await toggleFocus(tester);
    expect(find.byType(ToolPuck), findsOneWidget);
    // Bottom centre by default.
    final puck = tester.getCenter(find.byType(ToolPuck));
    expect(puck.dx, closeTo(640, 30));
    expect(puck.dy, greaterThan(800));

    // Draw, then undo from the puck.
    final page = s.pages.pagesOf(nb.id).first;
    await drawAt(tester, const Offset(400, 400));
    expect(inkOf(s, page), hasLength(2));
    await tester.tap(
      find.descendant(of: find.byType(ToolPuck), matching: find.byTooltip('Undo (Ctrl+Z)')),
    );
    await tester.pumpAndSettle();
    expect(inkOf(s, page), hasLength(1));

    // The tool switcher picks another tool.
    await tester.tap(
      find.descendant(of: find.byType(ToolPuck), matching: find.byType(ToolSwitcherButton)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highlighter'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Highlighter: tap to switch tools'), findsOneWidget);

    // Dragged to the right edge, it snaps there and is remembered.
    final grip = find.byTooltip('Drag to move the toolbar');
    final from = tester.getCenter(grip);
    final drag = await tester.startGesture(from);
    for (var i = 1; i <= 20; i++) {
      await drag.moveTo(Offset.lerp(from, const Offset(1270, 300), i / 20)!);
      await tester.pump();
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(s.preferences.puckFloat, (1.0, 0.5));
    expect(tester.getCenter(find.byType(ToolPuck)).dx, greaterThan(1180));

    // Leaving focus mode hides it; the exit button works.
    await tester.tap(find.byTooltip('Show toolbars (F11)'));
    await tester.pumpAndSettle();
    expect(find.byType(ToolPuck), findsNothing);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('phones get the puck too, clear of the gesture bar', (tester) async {
    await pumpEditor(tester, size: const Size(390, 844));
    await toggleFocus(tester);
    expect(find.byType(ToolPuck), findsOneWidget);
    expect(tester.getRect(find.byType(ToolPuck)).bottom, lessThanOrEqualTo(844));
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });
}
