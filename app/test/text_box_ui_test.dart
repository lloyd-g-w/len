import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';

import 'content_tools_ui_test.dart';

/// Presses [key] with Ctrl (and [shift]).
Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('text: shortcuts format, lists toggle, checkboxes tick (editing and not)', (
    tester,
  ) async {
    final (services, nb) = await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 400)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    await tester.enterText(field, 'milk\neggs');
    await ctrl(tester, LogicalKeyboardKey.keyA);
    await ctrl(tester, LogicalKeyboardKey.keyB);
    await ctrl(tester, LogicalKeyboardKey.keyU);
    await ctrl(tester, LogicalKeyboardKey.digit9, shift: true);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Checklist (Ctrl+Shift+9)'), findsOneWidget);

    // Tick the second item while editing (after collapsing the selection,
    // whose handles would cover the marker).
    await key(tester, LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('list-marker-1')));
    await tester.pump();
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final element = liveElements(services, nb.id).single;
    var data = TextData.fromJson(element.data);
    expect(data.text, 'milk\neggs');
    expect(data.spans, const [StyledRange(0, 9, SpanStyle(bold: true, underline: true))]);
    expect(data.paras, const [
      ParaStyle(list: ListKind.check),
      ParaStyle(list: ListKind.check, checked: true),
    ]);
    expect(data.autoWidth, isTrue);

    // With the Text tool, tapping a committed checkbox ticks it without
    // opening the editor.
    await mouseDrag(tester, [element.rect.topLeft + const Offset(13, 15)]);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    data = TextData.fromJson(liveElements(services, nb.id).single.data);
    expect(data.paras.map((p) => p.checked), [true, true]);
  });

  testWidgets('text: the font picker and size buttons format the selection', (tester) async {
    final (services, nb) = await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 400)]);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('text-box-field')), 'Hello world');
    await ctrl(tester, LogicalKeyboardKey.keyA);
    await tester.tap(find.byKey(const ValueKey('font-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<TextFont>, 'Serif'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Larger'));
    await tester.pump();
    expect(find.text('32'), findsOneWidget);
    await tester.tap(find.byTooltip('Done (Esc)'));
    await tester.pumpAndSettle();
    final data = TextData.fromJson(liveElements(services, nb.id).single.data);
    expect(data.spans.single.style, const SpanStyle(size: 32, font: TextFont.lora));
  });
}
