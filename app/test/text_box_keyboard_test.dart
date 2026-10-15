import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
