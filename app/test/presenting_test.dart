import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/chrome/tool_puck.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;

Future<void> twoFingerHold(
  WidgetTester tester, {
  Duration hold = const Duration(milliseconds: 700),
}) async {
  final a = await tester.startGesture(const Offset(300, 500));
  final b = await tester.startGesture(const Offset(420, 500));
  await tester.pump(hold);
  await a.up();
  await b.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('in focus mode, a two-finger long press hides the puck and the way out', (
    tester,
  ) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    s.preferences.stylusOnly = true; // Fingers navigate.
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(find.byType(ToolPuck), findsOneWidget);

    await twoFingerHold(tester);
    expect(find.byType(ToolPuck), findsNothing);
    expect(find.byTooltip('Show toolbars (F11)').hitTestable(), findsNothing);

    // Again: back.
    await twoFingerHold(tester);
    expect(find.byType(ToolPuck), findsOneWidget);

    // A quick two-finger tap is still undo, not this.
    await twoFingerHold(tester, hold: const Duration(milliseconds: 100));
    expect(find.byType(ToolPuck), findsOneWidget);

    // Leaving focus mode (F11) ends presenting too.
    await twoFingerHold(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(find.byType(ToolPuck), findsOneWidget);
    await closeEditor(tester);
  });

  testWidgets('outside focus mode a two-finger long press does nothing', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    s.preferences.stylusOnly = true;
    await twoFingerHold(tester);
    expect(find.byTooltip('More options').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });
}
