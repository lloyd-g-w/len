import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ui/color_dot.dart';

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

/// Makes the system clipboard hold [text] (for this test).
void mockClipboardText(String? text) {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var clip = text;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') return clip == null ? null : {'text': clip};
    if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null));
}

Future<void> paste(WidgetTester tester) async {
  await ctrl(tester, LogicalKeyboardKey.keyV);
  for (var i = 0; i < 4; i++) {
    await tester.pump(); // clipboard reads
  }
}

void main() {
  testWidgets('lasso Style shows colours: a swatch recolours the selection', (tester) async {
    final (services, nb) = await openCanvas(
      tester,
      seed: (s, nb) => s.strokes.save([seedStroke(nb.id)]),
    );
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(150, 400)]);
    expect(find.byTooltip('Colour'), findsNothing); // Folded into Style.
    await tester.tap(find.byTooltip('Style'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('More colours'), findsOneWidget);
    final other = find.byWidgetPredicate((w) => w is ColorDot && w.color != 0xFF1F2937).first;
    final colour = tester.widget<ColorDot>(other).color;
    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(liveStrokes(services, nb.id).single.color, colour);
    expect(tester.widget<ColorDot>(other).selected, isTrue);
  });

  testWidgets('Ctrl+V pastes plain text as a new, selected text box; copied ink wins after', (
    tester,
  ) async {
    mockClipboardText('Pasted line one\nand two');
    final (services, nb) = await openCanvas(
      tester,
      seed: (s, nb) => s.strokes.save([seedStroke(nb.id)]),
    );
    await paste(tester);
    final box = liveElements(services, nb.id).single;
    final data = TextData.fromJson(box.data);
    expect(data.text, 'Pasted line one\nand two');
    expect(data.autoWidth, isTrue);
    expect(box.rect.center.dx, closeTo(640, 1));
    expect(find.byTooltip('Style'), findsOneWidget); // selected with the lasso

    // Copy the ink: the clipboard's text is older now, so ink is pasted.
    await key(tester, LogicalKeyboardKey.escape);
    await mouseDrag(tester, const [Offset(150, 401)]);
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await tester.pump();
    await paste(tester);
    expect(liveStrokes(services, nb.id), hasLength(2));
    expect(liveElements(services, nb.id), hasLength(1));
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(liveElements(services, nb.id), isEmpty);
  });

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
