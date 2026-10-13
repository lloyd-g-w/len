import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/chrome/focus_handle.dart';
import 'package:len/features/editor/chrome/puck_clearance.dart';
import 'package:len/features/editor/chrome/tool_puck.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';
import 'package:len/ui/floating_panel.dart';

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

  testWidgets('released over writing, the puck moves to the nearest clear edge', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    await toggleFocus(tester);
    // A block of writing in the middle of the page.
    for (var y = 380.0; y <= 520; y += 20) {
      for (var x = 440.0; x <= 780; x += 70) {
        await drawAt(tester, Offset(x, y));
      }
    }
    const writing = Rect.fromLTRB(440, 380, 840, 540);

    Future<void> dragTo(Offset to) async {
      final grip = find.byTooltip('Drag to move the toolbar');
      final from = tester.getCenter(grip);
      final drag = await tester.startGesture(from);
      for (var i = 1; i <= 20; i++) {
        await drag.moveTo(Offset.lerp(from, to, i / 20)!);
        await tester.pump();
      }
      await drag.up();
      await tester.pumpAndSettle();
    }

    // Over blank paper it stays where it was dropped.
    await dragTo(const Offset(1000, 700));
    final dropped = s.preferences.puckFloat!;
    expect(PuckClearance.spots, isNot(contains(dropped)));
    expect(tester.getRect(find.byType(ToolPuck)).overlaps(writing), isFalse);

    // Over the writing it moves clear, to an edge.
    await dragTo(writing.center);
    expect(PuckClearance.spots, contains(s.preferences.puckFloat));
    expect(tester.getRect(find.byType(ToolPuck)).overlaps(writing), isFalse);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  test('the puck settles on the clear spot nearest to where it was released', () {
    Rect rectAt((double, double) at) =>
        Rect.fromCenter(center: Offset(at.$1 * 1000, at.$2 * 800), width: 100, height: 40);
    // Ink everywhere along the bottom; the top is clear.
    bool blocked(Rect r) => r.bottom > 500 || r.center == const Offset(500, 400);
    expect(PuckClearance.settle((0.2, 0.3), rectAt: rectAt, blocked: blocked), (0.2, 0.3));
    expect(PuckClearance.settle((0.5, 0.5), rectAt: rectAt, blocked: blocked), (0.5, 0));
    expect(PuckClearance.settle((0.3, 0.9), rectAt: rectAt, blocked: (r) => r.bottom > 500), (
      0,
      0.5,
    ));
    expect(PuckClearance.settle((0.5, 0.5), rectAt: rectAt, blocked: (_) => true), (0.5, 0.5));
  });

  testWidgets('phones get the puck too, clear of the gesture bar', (tester) async {
    await pumpEditor(tester, size: const Size(390, 844));
    await toggleFocus(tester);
    expect(find.byType(ToolPuck), findsOneWidget);
    expect(tester.getRect(find.byType(ToolPuck)).bottom, lessThanOrEqualTo(844));
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('the exit shows in full on entering, then rests; the grip is in the puck', (
    tester,
  ) async {
    await pumpEditor(tester, size: const Size(390, 844));
    await toggleFocus(tester);
    double exitOpacity() => tester
        .widget<AnimatedOpacity>(
          find.descendant(of: find.byType(FocusHandle), matching: find.byType(AnimatedOpacity)),
        )
        .opacity;
    expect(exitOpacity(), 1);
    await tester.pump(FocusHandle.announce);
    await tester.pumpAndSettle();
    expect(exitOpacity(), FocusHandle.restingOpacity);
    // Touch has no hover: it rests firmer than with a mouse.
    expect(FocusHandle.restingOpacity, greaterThan(0.4));
    expect(tester.getSize(find.byTooltip('Show toolbars (F11)')).width, greaterThanOrEqualTo(48));

    // One capsule holds the grip and the puck's tools.
    final capsule = find.ancestor(of: find.byType(ToolPuck), matching: find.byType(FloatingPanel));
    expect(capsule, findsOneWidget);
    expect(
      find.descendant(of: capsule, matching: find.byTooltip('Drag to move the toolbar')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(ToolPuck), matching: find.byType(FloatingPanel)),
      findsNothing,
    );
    await closeEditor(tester);
  });
}
