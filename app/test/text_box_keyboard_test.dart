import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:len/ui/floating_panel.dart';

import 'content_tools_ui_test.dart';

/// Typing around a text box: undo while typing, the soft keyboard, the
/// Text tool with a keyboard (UX_AUDIT round 19).
void main() {
  final field = find.byKey(const ValueKey('text-box-field'));
  String typed(WidgetTester tester) => tester.widget<TextField>(field).controller!.text;

  testWidgets('the top bar undo steps through the typing, then the page', (tester) async {
    final (services, nb) = await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyP);
    await mouseDrag(tester, const [Offset(100, 100), Offset(200, 150), Offset(300, 120)]);
    expect(liveStrokes(services, nb.id), hasLength(1));
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 500)]);
    await tester.pumpAndSettle();
    final undo = find.byTooltip('Undo (Ctrl+Z)');
    final redo = find.byTooltip('Redo (Ctrl+Shift+Z)');
    await tester.enterText(field, 'hello');
    await tester.enterText(field, 'hello ');
    await tester.enterText(field, 'hello world');
    await tester.pump();

    await tester.tap(undo);
    await tester.pump();
    expect(typed(tester), 'hello ');
    expect(liveStrokes(services, nb.id), hasLength(1), reason: 'the stroke stays');
    await tester.tap(redo);
    await tester.pump();
    expect(typed(tester), 'hello world');
    for (var i = 0; i < 3; i++) {
      await tester.tap(undo);
    }
    await tester.pump();
    expect(typed(tester), '');
    // Past the box's first state: the box goes, then the stroke.
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(liveElements(services, nb.id), isEmpty);
    expect(liveStrokes(services, nb.id), isEmpty);
  });

  /// The caret's rect on screen.
  Rect caret(WidgetTester tester) {
    final editable = tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;
    final local = editable.getLocalRectForCaret(editable.selection!.extent);
    return MatrixUtils.transformRect(editable.getTransformTo(null), local);
  }

  testWidgets('tablets: the soft keyboard opening over a box pans it into view', (tester) async {
    await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 650)]);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 380);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'hello');
    await tester.pumpAndSettle();
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(800 - 380));
    expect(tester.getRect(field).top, greaterThan(0));
  });

  testWidgets('phones: typing on in a tall box keeps the caret above the bar', (tester) async {
    await openCanvas(tester, size: const Size(390, 844));
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(60, 300)]);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final bar = find.ancestor(
      of: find.byTooltip('Done (Esc)'),
      matching: find.byType(FloatingPanel),
    );
    await tester.enterText(field, List.generate(30, (i) => 'line $i').join('\n'));
    await tester.pumpAndSettle();
    expect(caret(tester).bottom, lessThanOrEqualTo(tester.getRect(bar).top));
    expect(caret(tester).top, greaterThan(0));

    // The caret moved back to the start (Ctrl+Home, a tap): it comes back down.
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    expect(caret(tester).top, greaterThan(0));
    expect(caret(tester).bottom, lessThanOrEqualTo(tester.getRect(bar).top));
  });

  testWidgets('with the Text tool, typing starts a box; the next goes under it', (tester) async {
    final (services, nb) = await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await key(tester, LogicalKeyboardKey.keyH); // not the highlighter
    await tester.pumpAndSettle();
    expect(typed(tester), 'h');
    final first = tester.getRect(field);
    expect(first.center.dy, closeTo(400, 30), reason: 'in the middle of the view');
    await tester.enterText(field, 'hello');
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    await key(tester, LogicalKeyboardKey.space); // whitespace starts nothing
    expect(field, findsNothing);

    await key(tester, LogicalKeyboardKey.keyE); // not the eraser
    await tester.pumpAndSettle();
    expect(typed(tester), 'e');
    final second = tester.getRect(field);
    expect(second.left, first.left);
    expect(second.top, greaterThan(first.bottom));
    expect(second.top - first.bottom, lessThan(first.height));
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(liveElements(services, nb.id), hasLength(2));

    // Esc goes back to the tool before (the pen); its shortcuts work again.
    await key(tester, LogicalKeyboardKey.escape);
    await mouseDrag(tester, const [Offset(600, 100), Offset(700, 150)]);
    expect(liveStrokes(services, nb.id), hasLength(1));
    await key(tester, LogicalKeyboardKey.keyP);
    await key(tester, LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
  });
}
