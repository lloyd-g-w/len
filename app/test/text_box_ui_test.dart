import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ui/color_dot.dart';
import 'package:len/ui/floating_panel.dart';
import 'package:len/ui/menus.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'content_tools_ui_test.dart';
import 'support/real_async.dart';

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
    expect(find.text('Custom'), findsOneWidget); // The pen's colour block.
    final other = find.byWidgetPredicate((w) => w is ColorDot && w.color != 0xFF1F2937).first;
    final colour = tester.widget<ColorDot>(other).color;
    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(liveStrokes(services, nb.id).single.color, colour);
    expect(tester.widget<ColorDot>(other).selected, isTrue);
  });

  testWidgets('lasso Style: a custom colour applies once it rests', (tester) async {
    final (services, nb) = await openCanvas(
      tester,
      seed: (s, nb) => s.strokes.save([seedStroke(nb.id)]),
    );
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(150, 400)]);
    await tester.tap(find.byTooltip('Style'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '00AA00');
    await tester.pump();
    expect(liveStrokes(services, nb.id).single.color, isNot(0xFF00AA00), reason: 'not yet');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(liveStrokes(services, nb.id).single.color, 0xFF00AA00);
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
    expect(find.byTooltip('Style'), findsOneWidget); // selected, the pen kept

    // Copy the ink: it replaces the clipboard (a picture of it, no text),
    // so ink is pasted.
    var written = false;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (call) async {
      if (call.method != 'write') return call.method == 'files' ? const <Object>[] : null;
      await Clipboard.setData(const ClipboardData(text: ''));
      return written = true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('pasteboard'),
        (call) async => call.method == 'files' ? const <Object>[] : null,
      ),
    );
    await key(tester, LogicalKeyboardKey.escape);
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(150, 401)]);
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await pumpUntil(tester, () => written, reason: 'the copy to reach the clipboard');
    await paste(tester);
    expect(liveStrokes(services, nb.id), hasLength(2));
    expect(liveElements(services, nb.id), hasLength(1));
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(liveElements(services, nb.id), isEmpty);
  });

  testWidgets('phones: a box typed near the bottom stays above the docked format bar', (
    tester,
  ) async {
    await openCanvas(tester, size: const Size(390, 844));
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(120, 690)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    final bar = find.ancestor(
      of: find.byTooltip('Done (Esc)'),
      matching: find.byType(FloatingPanel),
    );
    Future<void> expectClear() async {
      await tester.pumpAndSettle();
      expect(
        tester.getRect(field).bottom,
        lessThanOrEqualTo(tester.getRect(bar).top),
        reason: 'the box is not under the bar',
      );
    }

    await expectClear();
    await tester.enterText(field, 'milk\neggs\nbread\nbutter');
    await expectClear();
    expect(tester.takeException(), isNull);
  });

  testWidgets('phones: a box too tall for the room keeps its caret above the format bar', (
    tester,
  ) async {
    await openCanvas(tester, size: const Size(390, 844));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(120, 300)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    await tester.enterText(field, List.generate(16, (i) => 'Line ${i + 1}').join('\n'));
    await tester.pumpAndSettle();
    final bar = find.ancestor(
      of: find.byTooltip('Done (Esc)'),
      matching: find.byType(FloatingPanel),
    );
    final editable = tester.allRenderObjects.whereType<RenderEditable>().single;
    final caret = editable.getLocalRectForCaret(
      TextPosition(offset: editable.text!.toPlainText().length),
    );
    final caretBottom = editable.localToGlobal(caret.bottomLeft).dy;
    expect(caretBottom, lessThanOrEqualTo(tester.getRect(bar).top), reason: 'caret in view');
    expect(caretBottom, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phones: the bottom tool row gives way to the keyboard (R20-5)', (tester) async {
    await openCanvas(tester, size: const Size(390, 844));
    final row = find.byType(ToolSwitcherButton).hitTestable();
    expect(row, findsOneWidget);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(120, 300)]);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    final bar = find.ancestor(
      of: find.byTooltip('Done (Esc)'),
      matching: find.byType(FloatingPanel),
    );
    // The format bar docks on the keyboard, where the row was.
    expect(tester.getRect(bar).bottom, greaterThan(844 - 300 - 24));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone held sideways: the box stays above the soft keyboard', (tester) async {
    await openCanvas(tester, size: const Size(844, 390));
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 300)]);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 190);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    await tester.enterText(field, 'Exam on Friday\nRevise');
    await tester.pumpAndSettle();
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(390 - 190));
    expect(tester.getRect(field).top, greaterThan(0));
    expect(tester.takeException(), isNull);
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
    // The lists menu shows the paragraph is a checklist.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('paragraph-menu')),
        matching: find.byIcon(Symbols.checklist_rounded),
      ),
      findsOneWidget,
    );

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
    await tester.tap(find.widgetWithText(MenuRow<String>, 'Serif'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Larger'));
    await tester.pump();
    expect(find.text('32'), findsOneWidget);
    await tester.tap(find.byTooltip('Done (Esc)'));
    await tester.pumpAndSettle();
    final data = TextData.fromJson(liveElements(services, nb.id).single.data);
    expect(data.spans.single.style, const SpanStyle(size: 32, font: TextFont.lora));
  });

  testWidgets('text: the field ignores the system text size, so it wraps like the canvas', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 400)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    await tester.enterText(field, 'Hello');
    await tester.pump();
    final editable = tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    final data = (editable.widget.controller as RichTextController).data;
    expect(
      editable.renderEditable.size.height,
      closeTo(TextLayout.heightOf(data, double.infinity), 1),
    );
  });

  testWidgets('text: Ctrl+Z in a box undoes with formatting, Ctrl+Shift+Z redoes', (tester) async {
    final (services, nb) = await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 400)]);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('text-box-field')), 'milk');
    await ctrl(tester, LogicalKeyboardKey.keyA);
    await ctrl(tester, LogicalKeyboardKey.keyB);
    await key(tester, LogicalKeyboardKey.backspace);
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    await ctrl(tester, LogicalKeyboardKey.keyZ, shift: true);
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final data = TextData.fromJson(liveElements(services, nb.id).single.data);
    expect(data.text, 'milk');
    expect(data.spans, const [StyledRange(0, 4, SpanStyle(bold: true))]);
  });
}
